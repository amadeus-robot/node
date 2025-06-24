defmodule FabricSnapshot do
    def prune() do
        end_hash = Fabric.pruned_hash()
        start_hash = Fabric.rooted_tip()

        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        opts = %{db: db, cf: cf}
        walk(end_hash, start_hash, opts)
        # sysconf.pruned_hash
    end

    def walk(end_hash, start_hash, opts) do
        entry = Fabric.entry_by_hash(start_hash)
        height = Entry.height(entry)
        IO.inspect {:walk, height}
        entries = Fabric.entries_by_height(height)
        entries = entries -- [entry]

        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.my_attestation_for_entry})
        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.muts_rev})
        map = Fabric.consensuses_by_entryhash(entry.hash)
        if map_size(map) != 1 do
            IO.inspect {height, map}
            1/0
        end

        Enum.each(entries, fn(entry)->
            IO.inspect {:delete, height, Base58.encode(entry.hash)}
            delete_entry_and_metadata(entry, opts)
        end)

        case entry do
            %{hash: ^end_hash} -> true
            %{header_unpacked: %{prev_hash: prev_hash, height: target_height}} ->
                walk(end_hash, prev_hash, opts)
        end
    end

   def delete_entry_and_metadata(entry, opts) do
        height = Entry.height(entry)
        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.default})
        RocksDB.delete("#{height}:#{entry.hash}", %{db: opts.db, cf: opts.cf.entry_by_height})
        RocksDB.delete("#{height}:#{entry.hash}", %{db: opts.db, cf: opts.cf.entry_by_slot})
        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.consensus_by_entryhash})
        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.my_attestation_for_entry})
        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.muts})
        RocksDB.delete(entry.hash, %{db: opts.db, cf: opts.cf.muts_rev})
    end

    def backstep_temporal(list) do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        opts = %{db: db, cf: cf}
        Enum.reverse(list)
        |> Enum.each(fn(hash)->
            entry = Fabric.entry_by_hash(hash)
            in_chain = Consensus.is_in_chain(hash)
            if in_chain do
                true = Consensus.chain_rewind(hash)
            end
            if entry do
                FabricSnapshot.delete_entry_and_metadata(entry, opts)
            end
        end)
    end

    def download_latest() do
        height = Application.fetch_env!(:ama, :snapshot_height)
        height_padded = String.pad_leading("#{height}", 12, "0")
        IO.puts "quick-syncing chain snapshot height #{height}.. this can take a while"
        url = "https://snapshots.amadeus.bot/#{height_padded}.zip"

        cwd_dir = Path.join(Application.fetch_env!(:ama, :work_folder), "updates_tmp/")
        :ok = File.mkdir_p!(cwd_dir)
        file = Path.join(cwd_dir, height_padded<>".zip")
        File.rm(file)
        {:ok, _} = :httpc.request(:get, {url |> to_charlist(), []}, [], [stream: file |> to_charlist()])
        IO.puts "quick-sync download complete. Extracting.."

        {:ok, _} = :zip.unzip(file |> to_charlist(), [{:cwd, Application.fetch_env!(:ama, :work_folder) |> to_charlist()}])
        :ok = File.rm!(file)
        IO.puts "quick-sync done"
    end

    def snapshot_tmp() do
        height = Fabric.rooted_tip_height()
        height_padded = String.pad_leading("#{height}", 12, "0")

        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        :ok = File.mkdir_p!("/tmp/#{height_padded}/db/")
        :rocksdb.checkpoint(db, '/tmp/#{height_padded}/db/fabric/')
        height
    end

    def upload_latest() do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        :ok = File.mkdir_p!("/tmp/000011351825/db/")
        :rocksdb.checkpoint(db, '/tmp/000011351825/db/fabric/')

        "https://snapshots.amadeus.bot/000011351825.zip"

        height_padded = String.pad_leading("10168922", 12, "0")
        "cd /tmp/000011540301/ && zip -9 -r 000015932681.zip db/ && cd /root"
        "aws s3 cp --checksum-algorithm=CRC32 --endpoint-url https://20bf2f5d11d26a322e389687896a6601.r2.cloudflarestorage.com #{height_padded}.zip s3://ama-snapshot"
        "aws s3 cp --checksum-algorithm=CRC32 --endpoint-url https://20bf2f5d11d26a322e389687896a6601.r2.cloudflarestorage.com 000015932681.zip s3://ama-snapshot"
    end
end
