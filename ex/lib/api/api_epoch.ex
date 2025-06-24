defmodule API.Epoch do
    def set_emission_address(pk) do
        pk = if byte_size(pk) != 48, do: Base58.decode(pk), else: pk
        sk = Application.fetch_env!(:ama, :trainer_sk)
        tx_packed = TX.build(sk, "Epoch", "set_emission_address", [pk])
        TXPool.insert(tx_packed)
        NodeGen.broadcast(:txpool, :trainers, [[tx_packed]])
    end

    def get_emission_address() do
        pk = Application.fetch_env!(:ama, :trainer_pk)
        get_emission_address(pk)
    end

    def get_emission_address(pk) do
        pk = if byte_size(pk) != 48, do: Base58.decode(pk), else: pk
        API.Contract.get("bic:epoch:emission_address:#{pk}")
        |> Base58.encode()
    end

    def score() do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get_prefix("bic:epoch:solutions_count:", %{db: db, cf: cf.contractstate, to_integer: true})
        |> Enum.map(fn {k, v} -> [Base58.encode(k), v] end)
        |> Enum.sort_by(& Enum.at(&1, 1), :desc)
    end

    def score(pk) do
        pk = if byte_size(pk) != 48, do: Base58.decode(pk), else: pk

        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get("bic:epoch:solutions_count:#{pk}", %{db: db, cf: cf.contractstate, to_integer: true}) || 0
    end
end
