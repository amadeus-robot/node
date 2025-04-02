defmodule NodeGenSocketGen do
  use GenServer

  def start_link(ip_tuple, port, name \\ __MODULE__) do
    GenServer.start_link(__MODULE__, [ip_tuple, port, name], name: name)
  end

  def init([ip_tuple, port, name]) do
    lsocket = listen(port, [{:ifaddr, ip_tuple}])
    recbuf_mb = (get_sys_recvbuf(lsocket)/1024)/1024
    IO.puts "recbuf: #{recbuf_mb}MB"
    if recbuf_mb < 64 do
      IO.puts "🔴WARNING: recbuf way too low, please edit /etc/sysctl.conf"
      IO.puts "🔴WARNING: set values to ATLEAST and reboot or `sysctl --system`"
      IO.puts "net.core.rmem_max = 268435456"
      IO.puts "net.core.optmem_max = 524288"
      IO.puts "net.core.netdev_max_backlog = 300000"
    end

    ip = Tuple.to_list(ip_tuple) |> Enum.join(".")
    state = %{
      name: name,
      ip: ip, ip_tuple: ip_tuple, port: port, socket: lsocket
    }
    {:ok, state}
  end

  def listen(port, opts \\ []) do
    basic_opts = [
      {:active, 16},
      #{:active, true},
      {:reuseaddr, true},
      {:reuseport, true}, #working in OTP26.1+
      {:buffer, 65536}, #max-size read
      {:recbuf, 33554432}, #total accum
      {:sndbuf, 1048576}, #total accum
      :binary,
    ]
    {:ok, lsocket} = :gen_udp.open(port, basic_opts++opts)
    lsocket
  end

  def get_sys_recvbuf(socket) do
    {:ok, [{:raw, 1, 8, <<size::32-little>>}]} = :inet.getopts(socket, [{:raw, 1, 8, 4}])
    size
  end

  def handle_info(msg, state) do
    case msg do
      {:udp, _socket, ip, _inportno, data} ->
        #IO.puts IO.ANSI.red() <> inspect({:relay_from, ip, msg.op}) <> IO.ANSI.reset()

        :erlang.spawn(fn()->
          case NodeProto.unpack_message_v2(data) do
            %{error: :old, msg: msg} ->
              peer_ip = Tuple.to_list(ip) |> Enum.join(".")
              peer = %{ip: peer_ip, signer: msg.signer, version: msg.version}
              NodeState.handle(msg.op, %{peer: peer}, msg)

            %{error: :signature, shard_total: 1, pk: pk, version: version, signature: signature, payload: payload} ->
              if !BlsEx.verify?(pk, signature, Blake3.hash(pk<>payload), BLS12AggSig.dst_node()), do: throw(%{error: :invalid_signature})
              msg = payload
              |> NodeProto.deflate_decompress()
              |> :erlang.binary_to_term([:safe])
              peer_ip = Tuple.to_list(ip) |> Enum.join(".")
              peer = %{ip: peer_ip, signer: pk, version: version}
              NodeState.handle(msg.op, %{peer: peer}, msg)

            %{error: :signature, pk: pk, signature: signature, ts_nano: ts_nano, shard_index: shard_index, shard_total: shard_total, 
              version: version, original_size: original_size, payload: payload} 
            ->
              peer_ip = Tuple.to_list(ip) |> Enum.join(".")
              
              gen = NodeGen.get_reassembly_gen(pk, ts_nano)
              send(gen, {:add_shard, {pk, ts_nano, shard_total}, {peer_ip, version, nil, signature, shard_index, original_size}, payload})

            %{error: :encrypted, shard_total: 1, pk: pk, version: version, ts_nano: ts_nano, payload: payload} ->
              shared_secret = NodePeers.get_shared_secret(pk)

              <<iv::12-binary, tag::16-binary, ciphertext::binary>> = payload
              key = :crypto.hash(:sha256, [shared_secret, :binary.encode_unsigned(ts_nano), iv])
              plaintext = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, <<>>, tag, false)

              msg = plaintext
              |> NodeProto.deflate_decompress()
              |> :erlang.binary_to_term([:safe])

              peer_ip = Tuple.to_list(ip) |> Enum.join(".")
              peer = %{ip: peer_ip, signer: pk, version: version}
              NodeState.handle(msg.op, %{peer: peer}, msg)

            %{error: :encrypted, pk: pk, ts_nano: ts_nano, shard_index: shard_index, shard_total: shard_total, 
              version: version, original_size: original_size, payload: payload} ->
              shared_secret = NodePeers.get_shared_secret(pk)

              peer_ip = Tuple.to_list(ip) |> Enum.join(".")
              gen = NodeGen.get_reassembly_gen(pk, ts_nano)
              send(gen, {:add_shard, {pk, ts_nano, shard_total}, {peer_ip, version, shared_secret, nil, shard_index, original_size}, payload})

            _ -> nil
          end
        end)

      {:send_to_some, peer_ips, packed_msg} ->
        port = Application.fetch_env!(:ama, :udp_port)
        Enum.each(peer_ips, fn(ip)->
          peer = NodePeers.by_ip(ip)
          {:ok, ip} = :inet.parse_address(~c'#{ip}')
          cond do
            !peer or !peer[:version] or !peer[:pk] or peer.version <= "0.7.6" -> :ok = :gen_udp.send(state.socket, ip, port, packed_msg)
            peer.version > "0.7.6" ->
              #IO.inspect {:peer_modern, Base58.encode(peer.pk)}

              <<iv::12-binary, tag::16-binary, ciphertext::binary>> = packed_msg
              plaintext = NodeProto.decrypt(iv, tag, ciphertext)
              msg_envelope = plaintext
              |> NodeProto.deflate_decompress()
              |> :erlang.binary_to_term([:safe])

              msg = :erlang.binary_to_term(msg_envelope.msg_packed, [:safe])
              msg = Map.drop(msg, [:version, :signer])
              #IO.inspect msg

              msg_compressed = NodeProto.compress_message_v2(msg)
              msgs_packed = NodeProto.encrypt_message_v2(msg_compressed, peer[:shared_secret])
              Enum.each(msgs_packed, fn(msg_packed)->
                :ok = :gen_udp.send(state.socket, ip, port, msg_packed)
              end)

              #:gen_udp.send(state.socket, ip, port, packed_msg)
          end
        end)

      {:udp_passive, _socket} ->
        :ok = :inet.setopts(state.socket, [{:active, 16}])

    end
    {:noreply, state}
  end
end