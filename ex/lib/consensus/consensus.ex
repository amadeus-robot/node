defmodule Consensus do

    def unpack(consensus_packed) when is_binary(consensus_packed) do
        :erlang.binary_to_term(consensus_packed, [:safe])
        |> unpack()
    end
    def unpack(consensus_packed) when is_map(consensus_packed) do
        consensus_packed
        |> Map.take([:entry_hash, :mutations_hash, :mask, :aggsig])
    end


    def pack(consensus_packed) when is_binary(consensus_packed) do consensus_packed end
    def pack(consensus_packed) do
        consensus_packed
        |> Map.take([:entry_hash, :mutations_hash, :mask, :aggsig])
        |> :erlang.term_to_binary([:deterministic])
    end

    def validate_vs_chain(c) do
        try do
        to_sign = <<c.entry_hash::binary, c.mutations_hash::binary>>

        entry = Fabric.entry_by_hash(c.entry_hash)
        if !entry, do: throw(%{error: :invalid_entry})
        if entry.header_unpacked.height > Consensus.chain_height(), do: throw(%{error: :too_far_in_future})

        #TODO: race here if entry is not proced
        trainers = trainers_for_height(Entry.height(entry))
        score = BLS12AggSig.score(trainers, c.mask)

        trainers_signed = BLS12AggSig.unmask_trainers(trainers, c.mask)
        aggpk = BlsEx.aggregate_public_keys!(trainers_signed)
        if !BlsEx.verify?(aggpk, c.aggsig, to_sign, BLS12AggSig.dst_att()), do: throw(%{error: :invalid_signature})

        c = Map.put(c, :score, score)
        %{error: :ok, consensus: c}
        catch
            :throw,r -> r
            e,r -> IO.inspect {Consensus, :validate, e, r, __STACKTRACE__}; %{error: :unknown}
        end
    end

    def is_trainer() do
        Application.fetch_env!(:ama, :trainer_pk) in trainers_for_height(chain_height()+1)
    end

    def trainers_for_height(height, opts \\ %{}) do
        options = if opts[:rtx] do
            %{rtx: opts.rtx, cf: opts.cf.contractstate, term: true}
        else
            %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
            %{db: db, cf: cf.contractstate, term: true}
        end

        cond do
            height in 3195570..3195575 ->
                RocksDB.get("bic:epoch:trainers:height:000000319557", options)
            true ->
                {_, value} = RocksDB.get_prev_or_first("bic:epoch:trainers:height:", String.pad_leading("#{height}", 12, "0"), options)
                value
        end
    end

    def trainer_for_slot(height, slot) do
        trainers = trainers_for_height(height)
        index = rem(slot, length(trainers))
        Enum.at(trainers, index)
    end

    def trainer_for_slot_current() do
        trainer_for_slot(chain_height(), chain_height())
    end

    def trainer_for_slot_next() do
        trainer_for_slot(chain_height()+1, chain_height()+1)
    end

    def trainer_for_slot_next_me?() do
        pk = Application.fetch_env!(:ama, :trainer_pk)
        pk == trainer_for_slot_next()
    end

    def did_trainer_sign_consensus(trainer, entry_hash) do
        c = Fabric.consensuses_by_entryhash(entry_hash)
        if c do
            entry = Fabric.entry_by_hash(entry_hash)
            trainers = trainers_for_height(entry.header_unpacked.height)
            res = Enum.reject(c, fn {_mut_hash, %{mask: mask}}->
                signed = BLS12AggSig.unmask_trainers(trainers, mask)
                trainer in signed
            end)
            res == []
        end
    end

    #def next_trainer_slot_in_x_slots(pk, epoch, slot, acc \\ 0) do
    #    trainer = Consensus.trainer_for_slot(epoch, slot + acc)
    #    cond do
    #        acc >= 128 -> nil
    #        pk == trainer -> acc
    #        true -> next_trainer_slot_in_x_slots(pk, epoch, slot, acc + 1)
    #    end
    #end

    def chain_height() do
        entry = chain_tip_entry()
        entry.header_unpacked.height
    end

    def chain_epoch() do
        div(chain_height(), 100_000)
    end

    def chain_nonce(pk) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get("bic:base:nonce:#{pk}", %{db: db, cf: cf.contractstate, to_integer: true})
    end

    def chain_balance(pk, symbol \\ "AMA") do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get("bic:coin:balance:#{pk}:#{symbol}", %{db: db, cf: cf.contractstate, to_integer: true}) || 0
    end

    def chain_tip() do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get("temporal_tip", %{db: db, cf: cf.sysconf})
    end

    def chain_tip_entry() do
        %{db: db} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get(chain_tip(), %{db: db, term: true})
        |> Entry.unpack()
    end

    def chain_muts_rev(hash) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get(hash, %{db: db, cf: cf.muts_rev ,term: true})
    end

    def chain_rewind(target_hash) do
        in_chain = Consensus.is_in_chain(target_hash)
        cond do
            !in_chain -> false
            true ->
                %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
                {:ok, rtx} = :rocksdb.transaction(db, [])
                Process.put({RocksDB, :ctx}, %{rtx: rtx, cf: cf})

                tip_entry = Consensus.chain_tip_entry()
                entry = chain_rewind_1(tip_entry, target_hash)

                :ok = :rocksdb.transaction_put(rtx, cf.sysconf, "temporal_tip", entry.hash)
                :ok = :rocksdb.transaction_put(rtx, cf.sysconf, "temporal_height", :erlang.term_to_binary(entry.header_unpacked.height, [:deterministic]))

                rooted_hash = RocksDB.get("rooted_tip", %{rtx: rtx, cf: cf.sysconf})
                rooted_entry = RocksDB.get(rooted_hash, %{rtx: rtx, cf: cf.default})
                if !rooted_entry do
                    :ok = :rocksdb.transaction_put(rtx, cf.sysconf, "rooted_tip", entry.hash)
                end

                :ok = :rocksdb.transaction_commit(rtx)

                true
        end
    end
    defp chain_rewind_1(current_entry, target_hash) do
        m_rev = Consensus.chain_muts_rev(current_entry.hash)
        ConsensusKV.revert(m_rev)

        %{rtx: rtx, cf: cf} = Process.get({RocksDB, :ctx})
        :ok = :rocksdb.transaction_delete(rtx, cf.default, current_entry.hash)
        :ok = :rocksdb.transaction_delete(rtx, cf.my_seen_time_for_entry, current_entry.hash)
        :ok = :rocksdb.transaction_delete(rtx, cf.entry_by_height, "#{current_entry.header_unpacked.height}:#{current_entry.hash}")
        :ok = :rocksdb.transaction_delete(rtx, cf.entry_by_slot, "#{current_entry.header_unpacked.slot}:#{current_entry.hash}")
        :ok = :rocksdb.transaction_delete(rtx, cf.consensus_by_entryhash, current_entry.hash)
        :ok = :rocksdb.transaction_delete(rtx, cf.my_attestation_for_entry, current_entry.hash)
        Enum.each(current_entry.txs, fn(tx_packed)->
            txu = TX.unpack(tx_packed)
            :ok = :rocksdb.transaction_delete(rtx, cf.tx, txu.hash)
            nonce_padded = String.pad_leading("#{txu.tx.nonce}", 20, "0")
            :ok = :rocksdb.transaction_delete(rtx, cf.tx_account_nonce, "#{txu.tx.signer}:#{nonce_padded}")
            TX.known_receivers(txu)
            |> Enum.each(fn(receiver)->
                :ok = :rocksdb.transaction_delete(rtx, cf.tx_receiver_nonce, "#{receiver}:#{nonce_padded}")
            end)
        end)

        if current_entry.hash == target_hash do
            prev_entry = Fabric.entry_by_hash_w_mutsrev(current_entry.header_unpacked.prev_hash)
            if !prev_entry do
                IO.puts "rewind catastrophically failed"
                :erlang.halt()
            else
                prev_entry
            end
        else
            case Fabric.entry_by_hash_w_mutsrev(current_entry.header_unpacked.prev_hash) do
                nil ->
                    IO.puts "rewind catastrophically failed"
                    :erlang.halt()
                entry = %{hash: ^target_hash} -> entry
                current_entry -> chain_rewind_1(current_entry, target_hash)
            end
        end
    end

    def chain_tx(tx_hash) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        map = RocksDB.get(tx_hash, %{db: db, cf: cf.tx ,term: true})
        if map do
            entry_bytes = RocksDB.get(map.entry_hash, %{db: db})
            entry = Fabric.entry_by_hash(map.entry_hash)
            tx_bytes = binary_part(entry_bytes, map.index_start, map.index_size)
            TX.unpack(tx_bytes)
            |> Map.put(:result, map[:result])
            |> Map.put(:metadata, %{entry_hash: map.entry_hash, entry_slot: entry.header_unpacked.slot})
        end
    end

    def is_in_chain(target_hash) do
        case Fabric.entry_by_hash_w_mutsrev(target_hash) do
            nil -> false
            %{header_unpacked: %{height: target_height}} ->
                tip_entry = Consensus.chain_tip_entry()
                tip_hash  = tip_entry.hash
                tip_height = tip_entry.header_unpacked.height

                if tip_height < target_height do
                  false
                else
                  is_in_chain_1(tip_hash, target_hash, target_height)
                end
        end
    end
    defp is_in_chain_1(current_hash, target_hash, target_height) do
        case Fabric.entry_by_hash_w_mutsrev(current_hash) do
            nil -> false
            %{hash: ^target_hash} -> true
            %{header_unpacked: %{prev_hash: prev_hash, height: height}} ->
                cond do
                  height < target_height -> false
                  true -> is_in_chain_1(prev_hash, target_hash, target_height)
                end
        end
    end

    def best_by_weight(trainers, consensuses) do
        maxScore = length(trainers)
        Enum.reduce(consensuses, {nil,nil,nil}, fn({k,v}, {best,bestscore,bestval})->
            trainers_signed = BLS12AggSig.unmask_trainers(trainers, v.mask)
            score = Enum.reduce(trainers_signed, 0, fn(pk, acc)->
                acc + ConsensusWeight.count(pk)
            end)
            score = score/maxScore
            cond do
                !best -> {k, score, v}
                score > bestscore -> {k, score, v}
                true -> {best,bestscore,bestval}
            end
        end)
    end

    def make_mapenv(next_entry) do
        %{
            :readonly => false,
            :seed => nil,
            :seedf64 => 1.0,
            :entry_signer => next_entry.header_unpacked.signer,
            :entry_prev_hash => next_entry.header_unpacked.prev_hash,
            :entry_slot => next_entry.header_unpacked.slot,
            :entry_prev_slot => next_entry.header_unpacked.prev_slot,
            :entry_height => next_entry.header_unpacked.height,
            :entry_epoch => div(next_entry.header_unpacked.height, 100_000),
            :entry_vr => next_entry.header_unpacked.vr,
            :entry_dr => next_entry.header_unpacked.dr,
            :tx_signer => nil, #env.txu.tx.signer,
            :tx_nonce => nil, #env.txu.tx.nonce,
            :tx_hash => nil, #env.txu.hash,
            :account_origin => nil, #env.txu.tx.signer,
            :account_caller => nil, #env.txu.tx.signer,
            :account_current => nil, #action.contract,
            :call_counter => 0,
            :call_exec_points => 10_000_000,
        }
    end

    def apply_entry(next_entry) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        {:ok, rtx} = :rocksdb.transaction(db, [])
        height = RocksDB.get("temporal_height", %{rtx: rtx, cf: cf.sysconf, term: true})
        if !height or (height + 1) == Entry.height(next_entry) do
            apply_entry_1(next_entry, cf, rtx)
        else
            %{error: :invalid_height}
        end
    end
    def apply_entry_1(next_entry, cf, rtx) do
        Process.put({RocksDB, :ctx}, %{rtx: rtx, cf: cf})

        mapenv = make_mapenv(next_entry)

        txus = Enum.map(next_entry.txs, & TX.unpack(&1))
        {m_pre, m_rev_pre} = BIC.Base.call_txs_pre_parallel(mapenv, txus)

        {m, m_rev, l} = Enum.reduce(txus, {m_pre, m_rev_pre, []}, fn(txu, {m, m_rev, l})->
            #ts_m = :os.system_time(1000)
            mapenv = Map.merge(mapenv, %{tx_signer: txu.tx.signer, tx_nonce: txu.tx.nonce, tx_hash: txu.hash,
                account_origin: txu.tx.signer, account_caller: txu.tx.signer})
            {m3, m_rev3, result} = BIC.Base.call_tx_actions(mapenv, txu)
            #IO.inspect {:call_tx, :os.system_time(1000) - ts_m}
            if result == %{error: :ok} do
                m = m ++ m3
                m_rev = m_rev ++ m_rev3
                {m, m_rev, l ++ [%{error: :ok}]}
            else
                ConsensusKV.revert(m_rev3)
                {m, m_rev, l ++ [result]}
            end
        end)
        {m_exit, m_exit_rev} = BIC.Base.call_exit(mapenv)

        m = m ++ m_exit
        m_rev = m_rev ++ m_exit_rev

        #TODO: store logs
        #IO.inspect {l ++ m, ConsensusKV.hash_mutations(l ++ m)}, limit: 11111111
        mutations_hash = ConsensusKV.hash_mutations(l ++ m)

        attestation = Attestation.sign(next_entry.hash, mutations_hash)
        attestation_packed = Attestation.pack(attestation)
        :ok = :rocksdb.transaction_put(rtx, cf.my_attestation_for_entry, next_entry.hash, attestation_packed)

        pk = Application.fetch_env!(:ama, :trainer_pk)
        trainers = trainers_for_height(Entry.height(next_entry), %{rtx: rtx, cf: cf})
        is_trainer = pk in trainers

        seen_time = :os.system_time(1000)
        :ok = :rocksdb.transaction_put(rtx, cf.my_seen_time_for_entry, next_entry.hash, :erlang.term_to_binary(seen_time, [:deterministic]))

        :ok = :rocksdb.transaction_put(rtx, cf.sysconf, "temporal_tip", next_entry.hash)
        :ok = :rocksdb.transaction_put(rtx, cf.sysconf, "temporal_height", :erlang.term_to_binary(next_entry.header_unpacked.height, [:deterministic]))
        #:ok = :rocksdb.transaction_put(rtx, cf.my_mutations_hash_for_entry, next_entry.hash, mutations_hash)
        :ok = :rocksdb.transaction_put(rtx, cf.muts_rev, next_entry.hash, :erlang.term_to_binary(m_rev, [:deterministic]))

        {:ok, entry_packed} = :rocksdb.transaction_get(rtx, cf.default, next_entry.hash, [])
        Enum.each(Enum.zip(next_entry.txs, l), fn({tx_packed, result})->
            txu = TX.unpack(tx_packed)
            case :binary.match(entry_packed, tx_packed) do
              {index_start, index_size} ->
                value = %{entry_hash: next_entry.hash, result: result, index_start: index_start, index_size: index_size}
                value = :erlang.term_to_binary(value, [:deterministic])
                :ok = :rocksdb.transaction_put(rtx, cf.tx, txu.hash, value)

                nonce_padded = String.pad_leading("#{txu.tx.nonce}", 20, "0")
                :ok = :rocksdb.transaction_put(rtx, cf.tx_account_nonce, "#{txu.tx.signer}:#{nonce_padded}", txu.hash)
                TX.known_receivers(txu)
                |> Enum.each(fn(receiver)->
                    :ok = :rocksdb.transaction_put(rtx, cf.tx_receiver_nonce, "#{receiver}:#{nonce_padded}", txu.hash)
                end)
            end
        end)

        if Application.fetch_env!(:ama, :archival_node) do
            :ok = :rocksdb.transaction_put(rtx, cf.muts, next_entry.hash, :erlang.term_to_binary(m, [:deterministic]))
        end

        :ok = :rocksdb.transaction_commit(rtx)

        ap = if is_trainer do
            #TODO: not ideal in super tight latency constrains but its 1 line and it works
            send(FabricCoordinatorGen, {:add_attestation, attestation})
            attestation_packed
        end

        %{error: :ok, attestation_packed: ap, mutations_hash: mutations_hash, logs: l, muts: m}
    end

    def produce_entry(slot) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})

        cur_entry = chain_tip_entry()
        next_entry = Entry.build_next(cur_entry, slot)

        #TODO: todo add >1 tx
        #ts_m = :os.system_time(1000)
        #txs = TXPool.grab_next_valids(next_entry)
        txs = TXPool.grab_next_valid(10)
        #IO.inspect {:tx, :os.system_time(1000) - ts_m}

        next_entry = Map.put(next_entry, :txs, txs)
        next_entry = Entry.sign(next_entry)

        next_entry
    end
end
