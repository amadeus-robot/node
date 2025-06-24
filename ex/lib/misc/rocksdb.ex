defmodule RocksDB do
    def get(key, opts) do
        db = opts[:db]
        cf = opts[:cf]
        rtx = opts[:rtx]
        cond do
            !!rtx and !!cf -> :rocksdb.transaction_get(rtx, cf, key, [])
            !!rtx -> :rocksdb.transaction_get(rtx, key, [])
            !!db and !!cf -> :rocksdb.get(db, cf, key, [])
            !!db -> :rocksdb.get(db, key, [])
        end
        |> case do
            :not_found -> nil
            {:ok, value} ->
                cond do
                    opts[:term] -> :erlang.binary_to_term(value, [:safe])
                    opts[:to_integer] -> :erlang.binary_to_integer(value)
                    true -> value
                end
        end
    end

    def get_next(prefix, key, opts) do
        {:ok, it} = iterator(opts)

        seek_string = prefix <> key
        seek_res = :rocksdb.iterator_move(it, {:seek, seek_string})
        seek_res = case seek_res do
            {:ok, ^seek_string, _value} -> :rocksdb.iterator_move(it, :next)
            other -> other
        end

        offset = opts[:offset] || 0
        seek_res = if offset <= 0 do seek_res else
            Enum.reduce(1..offset, seek_res, fn(_, _)->
                :rocksdb.iterator_move(it, :next)
            end)
        end

        case seek_res do
            {:ok, <<^prefix::binary, next_key::binary>>, value} ->
                value = if opts[:term] do :erlang.binary_to_term(value, [:safe]) else value end
                {next_key, value}
            _ -> {nil, nil}
        end
    end

    def get_prev(prefix, key, opts) do
        {:ok, it} = iterator(opts)

        seek_string = prefix <> key
        seek_res = :rocksdb.iterator_move(it, {:seek_for_prev, "#{prefix}#{key}"})
        seek_res = case seek_res do
            {:ok, ^seek_string, _value} -> :rocksdb.iterator_move(it, :prev)
            other -> other
        end

        offset = opts[:offset] || 0
        seek_res = if offset <= 0 do seek_res else
            Enum.reduce(1..offset, seek_res, fn(_, _)->
                :rocksdb.iterator_move(it, :prev)
            end)
        end

        case seek_res do
            {:ok, <<^prefix::binary, prev_key::binary>>, value} ->
                value = if opts[:term] do :erlang.binary_to_term(value, [:safe]) else value end
                {prev_key, value}
            _ -> {nil, nil}
        end
    end

    def get_prev_or_first(prefix, key, opts) do
        {:ok, it} = iterator(opts)
        res = :rocksdb.iterator_move(it, {:seek_for_prev, "#{prefix}#{key}"})
        case res do
            {:ok, <<^prefix::binary, prev_key::binary>>, value} ->
                value = if opts[:term] do :erlang.binary_to_term(value, [:safe]) else value end
                {prev_key, value}
            _ -> {nil, nil}
        end
    end

    def put(key, value, opts) do
        db = opts[:db]
        cf = opts[:cf]
        rtx = opts[:rtx]
        value = if opts[:term] do :erlang.term_to_binary(value, [:deterministic]) else value end
        value = if opts[:to_integer] do :erlang.integer_to_binary(value) else value end
        cond do
            !!rtx and !!cf -> :rocksdb.transaction_put(rtx, cf, key, value)
            !!rtx -> :rocksdb.transaction_put(rtx, key, value)
            !!db and !!cf -> :rocksdb.put(db, cf, key, value, [])
            !!db -> :rocksdb.put(db, key, value, [])
        end
    end

    def delete(key, opts) do
        db = opts[:db]
        cf = opts[:cf]
        rtx = opts[:rtx]
        cond do
            !!rtx and !!cf -> :rocksdb.transaction_delete(rtx, cf, key)
            !!rtx -> :rocksdb.transaction_delete(rtx, key)
            !!db and !!cf -> :rocksdb.delete(db, cf, key, [])
            !!db -> :rocksdb.delete(db, key, [])
        end
    end

    def get_prefix(prefix, opts) do
        {:ok, it} = iterator(opts)
        res = :rocksdb.iterator_move(it, {:seek, prefix})
        get_prefix_1(prefix, it, res, opts, [])
    end
    defp get_prefix_1(prefix, it, res, opts, acc) do
        case res do
            {:ok, <<^prefix::binary, key::binary>>, value} ->
                value = if opts[:term] do :erlang.binary_to_term(value, [:safe]) else value end
                value = if opts[:to_integer] do :erlang.binary_to_integer(value) else value end
                res = :rocksdb.iterator_move(it, :next)
                get_prefix_1(prefix, it, res, opts, acc ++ [{key, value}])
            {:error, :invalid_iterator} -> acc
            _ -> acc
        end
    end

    defp iterator(opts) do
        db = opts[:db]
        cf = opts[:cf]
        rtx = opts[:rtx]
        cond do
            !!rtx and !!cf -> :rocksdb.transaction_iterator(rtx, cf, [])
            !!rtx -> :rocksdb.transaction_iterator(rtx, [])
            !!db and !!cf -> :rocksdb.iterator(db, cf, [])
            !!db -> :rocksdb.iterator(db, [])
        end
    end

    def dump(db_ref, cf) do
        {:ok, it} = :rocksdb.iterator(db_ref, cf, [])
        res = :rocksdb.iterator_move(it, :first)
        dump_1(it, res)
    end
    defp dump_1(it, res) do
        case res do
            {:ok, key, value} ->
                IO.inspect {key, value}
                res = :rocksdb.iterator_move(it, :next)
                dump_1(it, res)
            {:error, :invalid_iterator} -> nil
            _ -> nil
        end
    end

    def checkpoint(db_ref, path) do
        :rocksdb.checkpoint(db_ref, path)
    end

    def snapshot(output_path) do
        %{args: args} = :persistent_term.get({:flatkv_fd, Fabric})
        File.mkdir_p!(output_path)
        {"", 0} = System.shell("cp --reflink=always #{args.path}/#{Fabric} #{output_path}", [{:stderr_to_stdout, true}])
    end

    def restore_from_snapshot(path) do
    end

    def flush_all(db, cfs) do
        Enum.each(Map.values(cfs), fn(cf)->
            :ok = :rocksdb.flush(db, cf, [{:wait, true},{:allow_write_stall, true}])
        end)
    end

    def compact_all(db, cfs) do
        Enum.each(Map.values(cfs), fn(cf)->
            :ok = :rocksdb.compact_range(db, cf, :undefined, :undefined, [])
            #:ok = :rocksdb.compact_range(db, cf, <<"user:0000">>, <<"user:9999">>, [])
        end)
    end
end
