defmodule Ama do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    supervisor = Supervisor.start_link([
      {DynamicSupervisor, strategy: :one_for_one, name: Ama.Supervisor, max_seconds: 1, max_restarts: 999_999_999_999}
    ], strategy: :one_for_one)

    Fabric.init()
    Fabric.insert_genesis()

    IO.puts "Initing TXPool.."
    TXPool.init()

    :ets.new(NODEPeers, [:ordered_set, :named_table, :public,
      {:write_concurrency, true}, {:read_concurrency, true}, {:decentralized_counters, false}])

    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: PG, start: {:pg, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: PGWSPanel, start: {:pg, :start_link, [PGWSPanel]}})

    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: ComputorGen, start: {ComputorGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: LoggerGen, start: {LoggerGen, :start_link, []}})
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: FabricGen, start: {FabricGen, :start_link, []}})

    ip4 = Application.fetch_env!(:ama, :udp_ipv4_tuple)
    port = Application.fetch_env!(:ama, :udp_port)
    # Addition Of rpc Variables
    rpc_port = Application.fetch_env!(:ama, :rpc_port)
    rpc_listen = Application.fetch_env!(:ama, :rpc_listen)
    ip_tuple = rpc_listen
           |> String.trim()
           |> to_charlist()
           |> :inet.parse_address()
           |> case do
                {:ok, tuple} -> tuple
                {:error, _} -> raise "Invalid IP address format for rpc_listen: #{rpc_listen}"
              end


    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{id: NodeGen, start: {NodeGen, :start_link, [ip4, port]}, restart: :permanent})

    # Starting the Rpc Server
    {:ok, _} = DynamicSupervisor.start_child(Ama.Supervisor, %{
      id: Ama.RpcServer,
      start: {Plug.Cowboy, :http, [
        Ama.RpcServer, 
        [], 
        [
          port: rpc_port,
          ip: ip_tuple
        ]
      ]},
      restart: :permanent
    })

    IO.puts "Started RPC server on port #{rpc_port} and ip #{rpc_listen}"

    supervisor
  end
end

