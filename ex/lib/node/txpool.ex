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

    def delete_packed(tx_packed) when is_binary(tx_packed) do delete_packed([tx_packed]) end
    def delete_packed([]) do :ok end
    def delete_packed(txs_packed) do
        Enum.each(txs_packed, fn(tx_packed)->
            txu = TX.unpack(tx_packed)
            :ets.delete(TXPool, {txu.tx.nonce, txu.hash})
        end)
    end

    def purge_stale() do
        :ets.tab2list(TXPool)
        |> Enum.each(fn {key, txu} ->
            if is_stale(txu) do
                :ets.delete(TXPool, key)
            end
        end)
    end

    def grab_next_valid(amt \\ 1) do
        try do
            chain_epoch = Consensus.chain_epoch()
            :ets.foldl(fn({key, txu}, {acc, state_old})->
                try do
                    state = state_old

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

                    acc = acc ++ [TX.pack(txu)]
                    if length(acc) == amt do
                        throw {:choose, acc}
                    end

                    {acc, state}
                catch
                    :throw,{:choose, txs_packed} -> throw {:choose, txs_packed}
                    :throw,_ -> {acc, state_old}
                end
            end, {[], %{}}, TXPool)
            []
        catch
            :throw,{:choose, txs_packed} -> txs_packed
        end
    end

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
        |> Enum.reduce(nil, fn({{nonce, _hash}, txu}, lowest_nonce) ->
            if txu.tx.signer == pk do
                cond do
                    lowest_nonce == nil -> nonce
                    nonce < lowest_nonce -> nonce
                    true -> lowest_nonce
                end
            else
                lowest_nonce
            end
        end)
    end

    def highest_nonce() do
        Application.fetch_env!(:ama, :trainer_pk)
        |> highest_nonce()
    end
    def highest_nonce(pk) do
        :ets.tab2list(TXPool)
        |> Enum.reduce({nil, 0}, fn({{nonce, _hash}, txu}, {highest_nonce, cnt})->
            cond do
                txu.tx.signer == pk and (highest_nonce == nil or nonce > highest_nonce) -> {nonce, cnt + 1}
                txu.tx.signer == pk -> {highest_nonce, cnt + 1}
                true -> {highest_nonce, cnt}
            end
        end)
    end
end
