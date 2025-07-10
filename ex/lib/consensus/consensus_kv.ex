defmodule ConsensusKV do
    #TODO: explore verkle tree
    #TODO: explore radix trie

    def kv_put(key, value \\ "", opts \\ %{}) do
        db = Process.get({RocksDB, :ctx})
        {old_value, exists} = case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> {"", false}
            {:ok, value} -> {value, true}
        end

        value = if opts[:term] do :erlang.term_to_binary(value, [:deterministic]) else value end
        value = if opts[:to_integer] do :erlang.integer_to_binary(value) else value end

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
        value = if is_integer(value) do :erlang.integer_to_binary(value) else value end

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

    def kv_get(key, opts \\ %{}) do
        db = Process.get({RocksDB, :ctx})
        case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> nil
            {:ok, value} ->
                cond do
                    opts[:term] -> :erlang.binary_to_term(value, [:safe])
                    opts[:to_integer] -> :erlang.binary_to_integer(value)
                    true -> value
                end
        end
    end

    def kv_get_next(prefix, key, opts \\ %{}) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        seek_string = prefix <> key
        seek_res = :rocksdb.iterator_move(it, {:seek, seek_string})
        case seek_res do
            {:ok, ^seek_string, _value} -> :rocksdb.iterator_move(it, :next)
            other -> other
        end
        |> case do
            {:ok, <<^prefix::binary, next_key::binary>>, value} ->
                value = cond do
                    opts[:term] -> :erlang.binary_to_term(value, [:safe])
                    opts[:to_integer] -> :erlang.binary_to_integer(value)
                    true -> value
                end
                {next_key, value}
            _ -> {nil, nil}
         end
    end

    def kv_get_prev(prefix, key, opts \\ %{}) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        seek_string = prefix <> key
        seek_res = :rocksdb.iterator_move(it, {:seek_for_prev, seek_string})
        case seek_res do
            {:ok, ^seek_string, _value} -> :rocksdb.iterator_move(it, :prev)
            other -> other
        end
        |> case do
            {:ok, <<^prefix::binary, prev_key::binary>>, value} ->
                value = cond do
                    opts[:term] -> :erlang.binary_to_term(value, [:safe])
                    opts[:to_integer] -> :erlang.binary_to_integer(value)
                    true -> value
                end
                {prev_key, value}
            _ -> {nil, nil}
        end
    end

    def kv_exists(key) do
        db = Process.get({RocksDB, :ctx})
        case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
            :not_found -> false
            {:ok, _value} -> true
        end
    end

    def kv_get_prefix(prefix, opts \\ %{}) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        res = :rocksdb.iterator_move(it, {:seek, prefix})
        kv_get_prefix_1(prefix, it, res, [], opts)
    end
    defp kv_get_prefix_1(prefix, it, res, acc, opts) do
        case res do
            {:ok, <<^prefix::binary, key::binary>>, value} ->
                value = cond do
                    opts[:term] -> :erlang.binary_to_term(value, [:safe])
                    opts[:to_integer] -> :erlang.binary_to_integer(value)
                    true -> value
                end
                res = :rocksdb.iterator_move(it, :next)
                kv_get_prefix_1(prefix, it, res, acc ++ [{key, value}], opts)
            {:error, :invalid_iterator} -> acc
            _ -> acc
        end
    end

    def kv_clear(prefix) do
        db = Process.get({RocksDB, :ctx})
        {:ok, it} = :rocksdb.transaction_iterator(db.rtx, db.cf.contractstate, [])
        res = :rocksdb.iterator_move(it, {:seek, prefix})

        {muts, muts_rev} = kv_clear_1(db, prefix, it, res, [], [])

        Process.put(:mutations, Process.get(:mutations, []) ++ muts)
        Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ muts_rev)
        :erlang.integer_to_binary(length(muts))
    end
    def kv_clear_1(db, prefix, it, res, muts, muts_rev) do
        case res do
            {:ok, <<^prefix::binary, key::binary>>, value} ->
                res = :rocksdb.iterator_move(it, :next)

                key = prefix <> key
                :ok = :rocksdb.transaction_delete(db.rtx, db.cf.contractstate, key)
                muts = muts ++ [%{op: :delete, key: key}]
                muts_rev = muts_rev ++ [%{op: :put, key: key, value: value}]
                kv_clear_1(db, prefix, it, res, muts, muts_rev)
            {:error, :invalid_iterator} -> {muts, muts_rev}
            _ -> {muts, muts_rev}
        end
    end

    def kv_set_bit(key, bit_idx) do
      db = Process.get({RocksDB, :ctx})
      {old_value, exists} = case :rocksdb.transaction_get(db.rtx, db.cf.contractstate, key, []) do
          :not_found -> {<<0::size(SolBloom.page_size())>>, false}
          {:ok, value} -> {value, true}
      end

      << left::size(bit_idx), old_bit::size(1), right::bitstring >> = old_value
      if old_bit == 1 do
        false
      else
        Process.put(:mutations, Process.get(:mutations, []) ++ [%{op: :set_bit, key: key, value: bit_idx, bloomsize: SolBloom.page_size()}])
        if exists do
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :clear_bit, key: key, value: bit_idx}])
        else
            Process.put(:mutations_reverse, Process.get(:mutations_reverse, []) ++ [%{op: :delete, key: key}])
        end
        new_value = << left::size(bit_idx), 1::size(1), right::bitstring >>
        :ok = :rocksdb.transaction_put(db.rtx, db.cf.contractstate, key, new_value)
        true
      end
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
                :clear_bit ->
                    {:ok, old_value} = :rocksdb.transaction_get(db.rtx, db.cf.contractstate, mut.key, [])
                    << left::size(mut.value), _old_bit::size(1), right::bitstring >> = old_value
                    new_value = << left::size(mut.value), 0::size(1), right::bitstring >>
                    :ok = :rocksdb.transaction_put(db.rtx, db.cf.contractstate, mut.key, new_value)
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
