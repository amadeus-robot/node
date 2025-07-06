defmodule Ama do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    #IO.inspect Application.app_dir(:ama, "priv/index.html")
    Process.sleep(300)

    IEx.configure(inspect: [width: 120, limit: 96])

    supervisor = Supervisor.start_link([
      {DynamicSupervisor, strategy: :one_for_one, name: Ama.Supervisor, max_seconds: 1, max_restarts: 999_999_999_999}
    ], strategy: :one_for_one)

    IO.puts "config folder is #{Application.fetch_env!(:ama, :work_folder)}"
    IO.puts "version: #{Application.fetch_env!(:ama, :version)}"

    if Application.fetch_env!(:ama, :autoupdate) do
      IO.puts "🟢 auto-update enabled"
      AutoUpdateGen.upgrade(true)
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: AutoUpdateGen, start: {AutoUpdateGen, :start_link, []}})
    end

    IO.puts "Initing Fabric.."
    Fabric.init()
    #Fabric.insert_genesis()

    IO.puts "Initing TXPool.."
    TXPool.init()

    if !Application.fetch_env!(:ama, :offline) do
      rooted_tip_height = Fabric.rooted_tip_height()
      if rooted_tip_height == nil or rooted_tip_height < Application.fetch_env!(:ama, :snapshot_height) do
        Fabric.close()
        FabricSnapshot.download_latest()
        Fabric.init()
      end
    else
      if !Consensus.chain_tip() do
        %{db: db, cf: cf} = :persistent_term.get({:rocksdb, Fabric})
        RocksDB.put("bic:epoch:trainers:height:#{String.pad_leading("0", 12, "0")}",
          :erlang.term_to_binary([EntryGenesis.signer()]), %{db: db, cf: cf.contractstate})

        entry = EntryGenesis.get()
        Fabric.insert_entry(entry, :os.system_time(1000))
        Consensus.apply_entry(entry)
      end
    end

    #FabricSnapshot.backstep_temporal([Base58.decode("65ixJL6XkQAH2mrHn9nrHUaZfRZqUDpUqBqzMCdoPNku")])

    pk = Application.fetch_env!(:ama, :trainer_pk)
    IO.puts "systems functional. welcome #{Base58.encode(pk)}"

    :ets.new(NODEPeers, [:ordered_set, :named_table, :public,
      {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])
    :ets.new(SOLVerifyCache, [:ordered_set, :named_table, :public,
      {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])
    :ets.new(AttestationCache, [:ordered_set, :named_table, :public,
      {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])

    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: PG, start: {:pg, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: PGWSPanel, start: {:pg, :start_link, [PGWSPanel]}})

    if !Application.fetch_env!(:ama, :offline) do
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: ComputorGen, start: {ComputorGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: LoggerGen, start: {LoggerGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricGen, start: {FabricGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricSyncAttestGen, start: {FabricSyncAttestGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricSyncGen, start: {FabricSyncGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricCoordinatorGen, start: {FabricCoordinatorGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricEventGen, start: {FabricEventGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: SpecialMeetingAttestGen, start: {SpecialMeetingAttestGen, :start_link, []}})
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: SpecialMeetingGen, start: {SpecialMeetingGen, :start_link, []}})

      ip4 = Application.fetch_env!(:ama, :udp_ipv4_tuple)
      port = Application.fetch_env!(:ama, :udp_port)
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: NodeGen, start: {NodeGen, :start_link, [ip4, port]}, restart: :permanent})
      Enum.each(0..31, fn(idx)->
        atom = :'NodeGenReassemblyGen#{idx}'
        {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: atom, start: {NodeGenReassemblyGen, :start_link, [atom]}, restart: :permanent})
      end)
      Enum.each(0..7, fn(idx)->
        atom = :'NodeGenSocketGen#{idx}'
        {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: atom, start: {NodeGenSocketGen, :start_link, [ip4, port, atom]}, restart: :permanent})
      end)

      #web panel
      ipv4 = {a,b,c,d} = Application.fetch_env!(:ama, :http_ipv4)
      if ipv4 != {0,0,0,0} do
        ipv4_string = "#{a}.#{b}.#{c}.#{d}"
        port = Application.fetch_env!(:ama, :http_port)
        IO.puts "started http-api on #{ipv4_string}:#{port}"

        {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{
          id: Photon.GenTCPAcceptor, start: {Photon.GenTCPAcceptor, :start_link, [ipv4, port, Ama.MultiServer]}
        })
      end
    end

    supervisor
  end
end
