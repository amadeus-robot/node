defmodule Entry do

    @doc """
    entry %{
        header %{
            slot: 9,
            height: 6,
            prev_slot: 5,
            prev_hash: <<>>,
            signer: <>,
            dr <hash(prev_dr)>
            vr <sign(prev_vr)>
            txs_hash: <32>
        }
        txs []
        hash <header>
        sig <hash>
        optional|mask <bits>
    }
    """

    def unpack(entry_packed) when is_binary(entry_packed) do
        e = :erlang.binary_to_term(entry_packed, [:safe])
        unpack(e)
    end
    def unpack(entry_map) when is_map(entry_map) do
        eh = :erlang.binary_to_term(entry_map.header, [:safe])
        Map.put(entry_map, :header_unpacked, eh)
    end
    def unpack(nil), do: nil

    def pack(entry_unpacked) when is_binary(entry_unpacked) do entry_unpacked end
    def pack(entry_unpacked) do
        entry_unpacked
        |> Map.take([:header, :txs, :hash, :signature, :mask])
        |> :erlang.term_to_binary([:deterministic])
    end

    def sign(entry_unpacked) do
        sk = Application.fetch_env!(:ama, :trainer_sk)

        txs_hash = Blake3.hash(Enum.join(entry_unpacked.txs))
        entry_unpacked = put_in(entry_unpacked, [:header_unpacked, :txs_hash], txs_hash)
        h = :erlang.term_to_binary(entry_unpacked.header_unpacked, [:deterministic])

        hash = Blake3.hash(h)
        signature = BlsEx.sign!(sk, hash, BLS12AggSig.dst_entry())
        %{
            header: h,
            header_unpacked: entry_unpacked.header_unpacked,
            txs: entry_unpacked.txs,
            hash: hash,
            signature: signature,
        }
    end

    def unpack_and_validate(entry_packed) do
        try do

        entry_size = Application.fetch_env!(:ama, :entry_size)
        if byte_size(entry_packed) >= entry_size, do: throw(%{error: :too_large})
        e = :erlang.binary_to_term(entry_packed, [:safe])
        |> Map.take([:header, :txs, :hash, :signature, :mask])
        if entry_packed != :erlang.term_to_binary(e, [:deterministic]), do: throw %{error: :not_deterministicly_encoded}
        eh = :erlang.binary_to_term(e.header, [:safe])
        |> Map.take([:slot, :prev_slot, :height, :prev_hash, :signer, :dr, :vr, :txs_hash])
        if e.header != :erlang.term_to_binary(eh, [:deterministic]), do: throw %{error: :not_deterministicly_encoded_header}

        e = Map.put(e, :header_unpacked, eh)

        res_sig = validate_signature(e.header, e.signature, e.header_unpacked.signer, e[:mask])
        res_entry = validate_entry(e)
        cond do
            res_sig.error != :ok -> throw res_sig
            res_entry.error != :ok -> throw res_entry
            true -> %{error: :ok, entry: e}
        end
        catch
            :throw,r -> r
            e,r -> IO.inspect {Entry, :unpack_and_validate, e, r, __STACKTRACE__}; %{error: :unknown}
        end
    end

    def validate_signature(header, signature, signer, mask \\ nil) do
        try do
        hash = Blake3.hash(header)
        if mask do
            header_unpacked = :erlang.binary_to_term(header, [:safe])

            trainers = Consensus.trainers_for_height(header_unpacked.height)
            trainers_signed = BLS12AggSig.unmask_trainers(trainers, mask)
            if nil in trainers_signed, do: throw(%{error: :wrong_epoch})

            aggpk = BlsEx.aggregate_public_keys!(trainers_signed)

            if !BlsEx.verify?(aggpk, signature, hash, BLS12AggSig.dst_entry()), do: throw(%{error: :invalid_signature})
        else
            if !BlsEx.verify?(signer, signature, hash, BLS12AggSig.dst_entry()), do: throw(%{error: :invalid_signature})
        end
        %{error: :ok, hash: hash}
        catch
            :throw,r -> r
            e,r -> IO.inspect {Entry, :validate_signature, e, r}; %{error: :unknown}
        end
    end

    def validate_entry(e) do
        try do
        eh = e.header_unpacked
        if !is_integer(eh.slot), do: throw(%{error: :slot_not_integer})
        if !is_integer(eh.prev_slot), do: throw(%{error: :prev_slot_not_integer})
        if !is_integer(eh.height), do: throw(%{error: :height_not_integer})
        if !is_binary(eh.prev_hash), do: throw(%{error: :prev_hash_not_binary})
        if byte_size(eh.prev_hash) != 32, do: throw(%{error: :prev_hash_not_256_bits})
        if !is_binary(eh.dr), do: throw(%{error: :dr_not_binary})
        if byte_size(eh.dr) != 32, do: throw(%{error: :dr_not_256_bits})
        if !is_binary(eh.vr), do: throw(%{error: :vr_not_binary})
        if byte_size(eh.vr) != 96, do: throw(%{error: :vr_not_96_bytes})
        if !is_binary(eh.signer), do: throw(%{error: :signer_not_binary})
        if byte_size(eh.signer) != 48, do: throw(%{error: :signer_not_48_bytes})
        if !is_binary(eh.txs_hash), do: throw(%{error: :txs_hash_not_binary})
        if byte_size(eh.txs_hash) != 32, do: throw(%{error: :txs_hash_not_256_bits})

        if !!e[:mask] and !is_bitstring(e.mask), do: throw(%{error: :mask_not_bitstring})

        if !is_list(e.txs), do: throw(%{error: :txs_not_list})
        if length(e.txs) > 30, do: throw(%{error: :TEMPORARY_txs_only_30_per_entry})
        if eh.txs_hash != Blake3.hash(Enum.join(e.txs)), do: throw(%{error: :txs_hash_invalid})

        is_special_meeting_block = !!e[:mask]
        Enum.each(e.txs, fn(tx_packed)->
            %{error: err, txu: txu} = TX.validate(tx_packed, is_special_meeting_block)
            if err != :ok, do: throw(err)
        end)

        throw(%{error: :ok})
        catch
            :throw,r -> r
            e,r -> IO.inspect {Entry, :validate_entry, e, r}; %{error: :unknown}
        end
    end

    def validate_next(cur_entry, next_entry) do
        try do
        ceh = cur_entry.header_unpacked
        neh = next_entry.header_unpacked
        if ceh.slot != neh.prev_slot, do: throw(%{error: :invalid_slot})
        if ceh.height != (neh.height - 1), do: throw(%{error: :invalid_height})
        if cur_entry.hash != neh.prev_hash, do: throw(%{error: :invalid_hash})

        if Blake3.hash(ceh.dr) != neh.dr, do: throw(%{error: :invalid_dr})
        if !BlsEx.verify?(neh.signer, neh.vr, ceh.vr, BLS12AggSig.dst_vrf()), do: throw(%{error: :invalid_vr})

        txus = Enum.map(next_entry.txs, & TX.unpack(&1))
        chain_epoch = Consensus.chain_epoch()
        Enum.reduce(txus, %{}, fn(txu, state)->
            chainNonce = Map.get(state, {:chain_nonce, txu.tx.signer}, Consensus.chain_nonce(txu.tx.signer))
            nonceValid = !chainNonce or txu.tx.nonce > chainNonce
            if !nonceValid, do: throw(%{error: :invalid_tx_nonce})
            state = Map.put(state, {:chain_nonce, txu.tx.signer}, txu.tx.nonce)

            balance = Map.get(state, {:balance, txu.tx.signer}, Consensus.chain_balance(txu.tx.signer))
            balance = balance - BIC.Base.exec_cost(txu)
            balance = balance - BIC.Coin.to_cents(1)
            if balance < 0, do: throw(%{error: :not_enough_tx_exec_balance})
            state = Map.put(state, {:balance, txu.tx.signer}, balance)

            hasSol = Enum.find_value(txu.tx.actions, fn(a)-> a.function == "submit_sol" and hd(a.args) end)
            epochSolValid = if !hasSol do true else
                <<sol_epoch::32-little, _::binary>> = hasSol
                chain_epoch == sol_epoch
            end
            if !epochSolValid, do: throw(%{error: :invalid_tx_sol_epoch})

            state
        end)

        %{error: :ok}
        catch
            :throw,r -> r
            e,r ->
                IO.inspect {Entry, :validate_next, e, r}
                %{error: :unknown}
        end
    end

    def build_next(cur_entry, slot) do
        pk = Application.fetch_env!(:ama, :trainer_pk)
        sk = Application.fetch_env!(:ama, :trainer_sk)

        dr = Blake3.hash(cur_entry.header_unpacked.dr)
        vr = BlsEx.sign!(sk, cur_entry.header_unpacked.vr, BLS12AggSig.dst_vrf())

        %{
            header_unpacked: %{
                slot: slot,
                height: cur_entry.header_unpacked.height + 1,
                prev_slot: cur_entry.header_unpacked.slot,
                prev_hash: cur_entry.hash,
                dr: dr,
                vr: vr,
                signer: pk,
            }
        }
    end

    def epoch(entry) do
        div(entry.header_unpacked.height, 100_000)
    end

    def height(entry) do
        entry.header_unpacked.height
    end

    def contains_tx(entry, txfunction) do
        !!Enum.find(entry.txs, fn(txp)->
            txu = TX.unpack(txp)
            action = List.first(txu.tx.actions)
            action["function"] == txfunction
        end)
    end
end
