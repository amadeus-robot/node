defmodule API.TX do
    def get(tx_id) do
        tx_id = if byte_size(tx_id) != 32, do: Base58.decode(tx_id), else: tx_id
        Consensus.chain_tx(tx_id)
    end

    def get_by_entry(entry_hash) do
        entry_hash = if byte_size(entry_hash) != 32, do: Base58.decode(entry_hash), else: entry_hash
        case Fabric.entry_by_hash(entry_hash) do
            nil -> nil
            %{txs: txs} -> Enum.map(txs, & format_tx_for_client(TX.unpack(&1)))
        end
    end

    def get_by_address(pk) do
    end

    def submit(tx_packed) do
        %{error: error} = TX.validate(tx_packed)
        if error == :ok do
            TXPool.insert(tx_packed)
            NodeGen.broadcast(:txpool, :trainers, [[tx_packed]])
            %{error: :ok}
        else
            %{error: error}
        end
    end

    def format_tx_for_client(tx) do
        tx = Map.drop(tx, [:tx_encoded])
        tx = Map.put(tx, :signature, Base58.encode(tx.signature))
        tx = Map.put(tx, :hash, Base58.encode(tx.hash))
        tx = put_in(tx, [:tx, :signer], Base58.encode(tx.tx.signer))
        actions = Enum.map(tx.tx.actions, fn(a)->
            args = Enum.map(a.args, fn(arg)->
                if !is_binary(arg) do arg else
                    Base58.encode(arg)
                end
            end)
            Map.put(a, :args, args)
        end)
        tx = put_in(tx, [:tx, :actions], actions)
    end
end