defmodule NodeGen do
  use GenServer

  def start_link(ip_tuple, port) do
    GenServer.start_link(__MODULE__, [ip_tuple, port], name: __MODULE__)
  end

  def init([ip_tuple, _port]) do
    ip = Tuple.to_list(ip_tuple) |> Enum.join(".")
    NodePeers.seed(ip)

    state = %{
      ns: NodeState.init()
    }

    :erlang.send_after(1000, self(), :tick)
    :erlang.send_after(1000, self(), :tick_ping)
    {:ok, state}
  end

  def get_socket_gen() do
    idx = :rand.uniform(8) - 1
    :'NodeGenSocketGen#{idx}'
  end

  def get_reassembly_gen(pk, ts_nano) do
    idx = :erlang.phash2({pk, ts_nano}, 32)
    :'NodeGenReassemblyGen#{idx}'
  end

  def broadcast_ping() do
    :erlang.spawn(fn()->
      msg = NodeProto.ping()
      ips = NodePeers.all() |> Enum.map(& &1.ip)
      send(get_socket_gen(), {:send_to_some, ips, NodeProto.compress(msg)})
    end)
  end

  def broadcast(:txpool, who, [txs_packed]) do
    :erlang.spawn(fn()->
      msg = NodeProto.txpool(txs_packed)
      ips = NodePeers.by_who(who)
      send(get_socket_gen(), {:send_to_some, ips, NodeProto.compress(msg)})
    end)
  end

  def broadcast(:entry, who, [map]) do
    :erlang.spawn(fn()->
      msg = NodeProto.entry(map)
      ips = NodePeers.by_who(who)
      send(get_socket_gen(), {:send_to_some, ips, NodeProto.compress(msg)})
    end)
  end

  def broadcast(:attestation_bulk, who, [attestations_packed]) do
    :erlang.spawn(fn()->
      msg = NodeProto.attestation_bulk(attestations_packed)
      ips = NodePeers.by_who(who)
      send(get_socket_gen(), {:send_to_some, ips, NodeProto.compress(msg)})
    end)
  end

  def broadcast(:sol, who, [sol]) do
    :erlang.spawn(fn()->
      msg = NodeProto.sol(sol)
      ips = NodePeers.by_who(who)
      send(get_socket_gen(), {:send_to_some, ips, NodeProto.compress(msg)})
    end)
  end

  def broadcast(:special_business, who, [business]) do
    :erlang.spawn(fn()->
      msg = NodeProto.special_business(business)
      ips = NodePeers.by_who(who)
      send(get_socket_gen(), {:send_to_some, ips, NodeProto.compress(msg)})
    end)
  end

  def tick() do
    NodePeers.clear_stale()
  end

  def handle_info(msg, state) do
    case msg do

      :tick ->
        :erlang.send_after(1000, self(), :tick)
        tick()

      :tick_ping ->
        :erlang.send_after(500, self(), :tick_ping)
        broadcast_ping()

      {:handle_sync, op, innerstate, args} ->
        #TODO: ns dropped
        innerstate = Map.put(innerstate, :ns, state.ns)
        NodeState.handle(op, innerstate, args)

    end
    {:noreply, state}
  end
end
