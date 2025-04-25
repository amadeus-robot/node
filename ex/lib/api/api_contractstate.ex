defmodule API.ContractState do
    def get(key, parse_term \\ false) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get(key, %{db: db, cf: cf.contractstate, term: parse_term})
    end

    def get_prefix(prefix, parse_term \\ false) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.get_prefix(prefix, %{db: db, cf: cf.contractstate, term: parse_term})
    end
end