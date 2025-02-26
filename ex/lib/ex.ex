defmodule Ama do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    #IO.inspect Application.app_dir(:ama, "priv/index.html") 
    Process.sleep(300)

    IEx.configure(inspect: [width: 120])

    supervisor = Supervisor.start_link([
      {DynamicSupervisor, strategy: :one_for_one, name: Ama.Supervisor, max_seconds: 1, max_restarts: 999_999_999_999}
    ], strategy: :one_for_one)

    IO.puts "version: #{Application.fetch_env!(:ama, :version)}"

    IO.puts "Initing Fabric.."
    Fabric.init()
    Fabric.insert_genesis()

    IO.puts "Initing TXPool.."
    TXPool.init()

    pk = Application.fetch_env!(:ama, :trainer_pk)
    IO.puts "systems functional. welcome #{Base58.encode(pk)}"

    :ets.new(NODEPeers, [:ordered_set, :named_table, :public,
      {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])
    :ets.new(SOLVerifyCache, [:ordered_set, :named_table, :public,
      {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])

    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: PG, start: {:pg, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: PGWSPanel, start: {:pg, :start_link, [PGWSPanel]}})
    
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: ComputorGen, start: {ComputorGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: LoggerGen, start: {LoggerGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricGen, start: {FabricGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricSyncGen, start: {FabricSyncGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricCoordinatorGen, start: {FabricCoordinatorGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricEventGen, start: {FabricEventGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: SpecialMeetingAttestGen, start: {SpecialMeetingAttestGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: SpecialMeetingGen, start: {SpecialMeetingGen, :start_link, []}})
    if Application.fetch_env!(:ama, :autoupdate) do
      IO.puts "🟢 auto-update enabled"
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: AutoUpdateGen, start: {AutoUpdateGen, :start_link, []}})
    end
    
    ip4 = Application.fetch_env!(:ama, :udp_ipv4_tuple)
    port = Application.fetch_env!(:ama, :udp_port)
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: NodeGen, start: {NodeGen, :start_link, [ip4, port]}, restart: :permanent})
    Enum.each(0..7, fn(idx)->
      atom = :'NodeGenSocketGen#{idx}'
      {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: atom, start: {NodeGenSocketGen, :start_link, [ip4, port, atom]}, restart: :permanent})
    end)


    #web panel
    #ip4 = Application.fetch_env!(:ama, :http_ip4)
    #port = Application.fetch_env!(:ama, :http_port)
    #{a,b,c,d} = ip4
    #ip4_string = "#{a}.#{b}.#{c}.#{d}"
    #IO.puts "started http-api on #{ip4_string}:#{port}"

    #{:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{
    #  id: Photon.GenTCPAcceptor, start: {Photon.GenTCPAcceptor, :start_link, [ip4, port, Ama.MultiServer]}
    #})

    supervisor
  end
end