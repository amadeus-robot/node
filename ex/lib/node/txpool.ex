defmodule TXPool do
    def init() do
        :ets.new(TXPool, [:ordered_set, :named_table, :public,
            {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])
    end

    def insert(tx_packed) when is_binary(tx_packed) do insert([tx_packed]) end
    def insert([]) do :ok end
    def insert(txs_packed) do
        txus = Enum.map(txs_packed, fn(tx_packed)->
            txu = TX.unpack(tx_packed)
            {{txu.tx.nonce, txu.hash}, txu}
        end)
        :ets.insert(TXPool, txus)
    end

    def purge_stale() do
        :ets.tab2list(TXPool)
        |> Enum.each(fn {key, txu} ->
            if is_stale(txu) do
                :ets.delete(TXPool, key)
            end
        end)
    end

    def grab_next_valid() do
        try do
            :ets.foldl(fn({key, txu}, _nil)->
                if TX.chain_valid(txu) do
                    throw {:choose, TX.pack(txu)}
                end
            end, nil, TXPool)
            []
        catch
            :throw,{:choose, tx_packed} -> [tx_packed]
        end
    end

        #:ets.tab2list(TXPool)
        #|> Enum.map(& elem(&1,1))
        #|> Enum.filter(fn(txu) ->
        #    chainValid = TX.chain_valid(txu)
        #    chainValid
        #end)
        #|> Enum.sort_by(& &1.tx.nonce)
        #|> Enum.uniq_by(& &1.tx.signer)
        #|> Enum.map(& TX.pack(&1))
        #|> case do
        #    [] -> []
        #    txs -> 
        #        Enum.shuffle(txs)
        #        |> Enum.take(1)
        #end

    def is_stale(txu) do
        chainNonce = Consensus.chain_nonce(txu.tx.signer)
        nonceValid = !chainNonce or txu.tx.nonce > chainNonce

        hasSol = Enum.find_value(txu.tx.actions, fn(a)-> a.function == "submit_sol" and hd(a.args) end)
        epochSolValid = if !hasSol do true else
            <<sol_epoch::32-little, _::binary>> = hasSol
            Consensus.chain_epoch() == sol_epoch
        end

        cond do
            !epochSolValid -> true
            !nonceValid -> true
            true -> false
        end
    end

    def random(amount \\ 2) do
        :ets.tab2list(TXPool)
        |> case do
            [] -> nil
            txs -> 
                Enum.take(txs, amount)
                |> Enum.map(fn{_, txu}-> TX.pack(txu) end)
        end
    end

    def lowest_nonce(pk) do
        :ets.tab2list(TXPool)
        |> Enum.reduce(nil, fn({nonce, txu}, lowest_nonce)->
            if txu.tx.signer == pk and (!nonce or nonce < lowest_nonce) do
                nonce
            else
                lowest_nonce
            end
        end)
    end

    def test() do
        sk = Application.fetch_env!(:ama, :trainer_sk)
        pk = :crypto.strong_rand_bytes(48)
        packed_tx = TX.build(sk, 110_000, "Coin", "transfer", [pk, 1])
        TXPool.insert(packed_tx)
    end
end