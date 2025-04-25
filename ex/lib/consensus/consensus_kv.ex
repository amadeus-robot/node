defmodule ConsensusKV do
    #TODO: explore verkle tree
    #TODO: explore radix trie

    def kv_put(key, value \\ "") do
        db = Process.get({RocksDB, :ctx})
        {old_value, exists} = case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> {"", false}
            {:ok, value} -> {value, true}
        end
        
        Process.put(:mutations, Process.get(:mutations, []) ++ [%{op: :put, key: key, value: value}])
        if exists do
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :put, key: key, value: old_value}])
        else
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :delete, key: key}])
        end

        :ok = :rocksdb.transaction_put(db.rtx, db.cf.contractstate, key, value)
    end

    ## TOO COMPLEX a func for a strong typed 100% always correct lang sorry
    #def kv_merge(key, value \\ "") do
    #    db = Process.get({RocksDB, :ctx})
    #    {old_value, exists} = case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
    #        :not_found -> {%{}, false}
    #        {:ok, value} -> {:erlang.binary_to_term(value), true}
    #    end
    #    new_value = merge_nested(old_value, value)
        
    #    Process.put(:mutations, Process.get(:mutations, []) ++ [%{op: :put, key: key, value: new_value}])
    #    if exists do
    #        Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :put, key: key, value: old_value}])
    #    else
    #        Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :delete, key: key}])
    #    end

    #    :ok = :rocksdb.transaction_put(db.rtx, db.cf.contractstate, key, :erlang.term_to_binary(new_value, [:deterministic]))
    #end

    def kv_increment(key, value) do
        db = Process.get({RocksDB, :ctx})
        {old_value, exists} = case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> {"0", false}
            {:ok, value} -> {value, true}
        end
        new_value = :erlang.binary_to_integer(old_value)+:erlang.binary_to_integer(value)
        new_value = :erlang.integer_to_binary(new_value)

        Process.put(:mutations, Process.get(:mutations, []) ++ [%{op: :put, key: key, value: new_value}])
        if exists do
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :put, key: key, value: old_value}])
        else
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :delete, key: key}])
        end

        :ok = :rocksdb.transaction_put(db.rtx, db.cf.contractstate, key, new_value)
        new_value
    end

    def kv_delete(key) do
        db = Process.get({RocksDB, :ctx})
        case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> :ok
            {:ok, value} ->
                Process.put(:mutations, Process.get(:mutations, []) ++ [%{op: :delete, key: key}])
                Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :put, key: key, value: value}])
        end
        :ok = :rocksdb.transaction_delete(db.rtx, db.cf.contractstate, key)
    end

    def kv_get(key) do
        db = Process.get({RocksDB, :ctx})
        case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> nil
            {:ok, value} -> value
        end
    end

    def kv_get_prev(prefix, key) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        res = :rocksdb.iterator_move(it, {:seek_for_prev, prefix <> key})
        case res do
            {:ok, <<^prefix::binary, prev_key::binary>>, value} -> {prev_key, value}
            _ -> {nil, nil}
        end
    end

    def kv_get_next(prefix, key) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        seek_string = prefix <> key
        seek_res = :rocksdb.iterator_move(it, {:seek, seek_string})
        seek_res = case seek_res do
            {:ok, ^seek_string, _value} -> :rocksdb.iterator_move(it, :next)
            other -> other
        end
        |> case do
            {:ok, <<^prefix::binary, next_key::binary>>, value} -> {next_key, value}
            _ -> {nil, nil}
         end
     end

    def kv_exists(key) do
        db = Process.get({RocksDB, :ctx})
        case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> false
            {:ok, value} -> true
        end
    end

    def kv_get_prefix(prefix) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        res = :rocksdb.iterator_move(it, {:seek, prefix})
        kv_get_prefix_1(prefix, it, res, [])
    end
    defp kv_get_prefix_1(prefix, it, res, acc) do
        case res do
            {:ok, <<^prefix::binary, key::binary>>, value} ->
                res = :rocksdb.iterator_move(it, :next)
                kv_get_prefix_1(prefix, it, res, acc ++ [{key, value}])
            {:error, :invalid_iterator} -> acc
            _ -> acc
        end
    end

    def kv_clear(prefix) do
        db = Process.get({RocksDB, :ctx})
        kvs = kv_get_prefix(prefix)
        Enum.each(kvs, fn({k,v})->
            k = prefix <> k
            Process.put(:mutations, Process.get(:mutations, []) ++ [%{op: :delete, key: k}])
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :put, key: k, value: v}])
            :ok = :rocksdb.transaction_delete(db.rtx, db.cf.contractstate, k)
        end)
        :erlang.integer_to_binary(length(kvs))
    end

    def hash_mutations(m) do
        :erlang.term_to_binary(m, [:deterministic])
        |> Blake3.hash()
    end

    def revert(m_rev) do
        db = Process.get({RocksDB, :ctx})
        Enum.reverse(m_rev)
        |> Enum.each(fn(mut)->
            case mut.op do
                :put -> 
                    :ok = :rocksdb.transaction_put(db.rtx, db.cf.contractstate, mut.key, mut.value)
                :delete -> 
                    :ok = :rocksdb.transaction_delete(db.rtx, db.cf.contractstate, mut.key)
            end
        end)
    end

    def merge_nested(left, right) do
        Map.merge(left, right, &merge_nested_resolve/3)
    end
    defp merge_nested_resolve(_, left, right) do
        case {is_map(left), is_map(right)} do
            {true, true} -> merge_nested(left, right)
            _ -> right
        end
    end
end