defmodule API.Wallet do
    def my_balance(symbol \\ "AMA") do
        pk = Application.fetch_env!(:ama, :trainer_pk)
        balance(pk, symbol)
    end

    #def balance(pk, symbol \\ "AMA") do
    def balance(pk, symbol \\ "AMA") do
        pk = if byte_size(pk) != 48, do: Base58.decode(pk), else: pk
        coins = Consensus.chain_balance(pk, symbol)
        %{symbol: symbol, flat: coins, float: BIC.Coin.from_flat(coins)}
    end

    def balance_all(pk) do
        pk = if byte_size(pk) != 48, do: Base58.decode(pk), else: pk

        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        opts = %{db: db, cf: cf.contractstate, to_integer: true}
        RocksDB.get_prefix("bic:coin:balance:#{pk}:", opts)
        |> Enum.map(fn({symbol, coins})->
            %{symbol: symbol, flat: coins, float: BIC.Coin.from_flat(coins)}
        end)
    end

    def transfer(to, amount, symbol) do
        sk = Application.fetch_env!(:ama, :trainer_sk)
        transfer(sk, to, amount, symbol)
    end

    def transfer(from_sk, to, amount, symbol) do
        from_sk = if byte_size(from_sk) != 64, do: Base58.decode(from_sk), else: from_sk
        to = if byte_size(to) != 48, do: Base58.decode(to), else: to
        amount = if is_float(amount) do trunc(amount * 1_000_000_000) else amount end
        amount = if is_integer(amount) do :erlang.integer_to_binary(amount) else amount end
        tx_packed = TX.build(from_sk, "Coin", "transfer", [to, amount, symbol])
        TXPool.insert(tx_packed)
        NodeGen.broadcast(:txpool, :trainers, [[tx_packed]])
    end

    def generate_key() do
        sk = :crypto.strong_rand_bytes(64)
        pk = BlsEx.get_public_key!(sk)
        {Base58.encode(pk), Base58.encode(sk)}
    end
end
