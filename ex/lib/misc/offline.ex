defmodule Offline do
  def add_balance(amount \\ nil, pk \\ nil) do
    pk = if pk do pk else Application.fetch_env!(:ama, :trainer_pk) end
    amount = if amount do amount else "1000000000000" end

    %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
    RocksDB.put("bic:coin:balance:#{pk}:AMA", "#{amount}", %{db: db, cf: cf.contractstate})
  end

  def deploy(wasmpath, pk \\ nil) do
    pk = if pk do pk else Application.fetch_env!(:ama, :trainer_pk) end

    wasmbytes = File.read!(wasmpath)

    %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
    RocksDB.put("bic:contract:account:#{pk}:bytecode", wasmbytes, %{db: db, cf: cf.contractstate})
  end

  def call(sk, pk, function, args, attach_symbol \\ nil, attach_amount \\ nil) do
    packed_tx = TX.build(sk, pk, function, args, nil, attach_symbol, attach_amount)
    TXPool.insert(packed_tx)
    entry = Consensus.produce_entry(Consensus.chain_height()+1)
    Fabric.insert_entry(entry, :os.system_time(1000))
    Consensus.apply_entry(entry)
  end

  def produce_entry(clean_txpool \\ true) do
    entry = Consensus.produce_entry(Consensus.chain_height()+1)
    Fabric.insert_entry(entry, :os.system_time(1000))
    result = Consensus.apply_entry(entry)
    clean_txpool && TXPool.purge_stale()
    result
  end

  def state(pk \\ nil) do

  end
end
