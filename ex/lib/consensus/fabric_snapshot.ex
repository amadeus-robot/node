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

    def download_latest() do
        height = Application.fetch_env!(:ama, :snapshot_height)
        height_padded = String.pad_leading("#{height}", 12, "0")
        IO.puts "quick-syncing chain snapshot height #{height}.. this can take a while"
        url = "https://snapshots.amadeus.bot/#{height_padded}.zip"
        {:ok, %{status_code: 200, body: body}} = :comsat_http.get(url, %{},
            %{timeout: 60_000*60, ssl_options: [{:server_name_indication, 'snapshots.amadeus.bot'}, {:verify, :verify_none}]})
        work_folder = Application.fetch_env!(:ama, :work_folder)
        {:ok, _} = :zip.unzip(body, [:verbose, {:cwd, '#{work_folder}'}])
        
        IO.puts "quick-sync done"
    end

    def upload_latest() do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        :ok = File.mkdir_p!("/tmp/000010300000/db/")
        :rocksdb.checkpoint(db, '/tmp/000010300000/db/fabric/')

        height_padded = String.pad_leading("10168922", 12, "0")
        "cd /tmp/000010300000/ && zip -9 -r 000010300000.zip db/ && cd /root"
        "aws s3 cp --checksum-algorithm=CRC32 --endpoint-url https://20bf2f5d11d26a322e389687896a6601.r2.cloudflarestorage.com #{height_padded}.zip s3://ama-snapshot"
        "aws s3 cp --checksum-algorithm=CRC32 --endpoint-url https://20bf2f5d11d26a322e389687896a6601.r2.cloudflarestorage.com 000010300000.zip s3://ama-snapshot"
    end
end