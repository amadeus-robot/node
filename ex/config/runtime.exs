import Config

work_folder = (System.get_env("WORKFOLDER") || Path.expand("~/.cache/amadeusd/"))
config :ama, :work_folder, work_folder
IO.puts "config folder is #{work_folder}"

:ok = File.mkdir_p!(work_folder)

#load env
#Envvar.load(Path.join([work_folder, ".env"]))

#Bind Interaces
config :ama, :http_ip4, ((System.get_env("HTTP_IP4") || "0.0.0.0") |> :unicode.characters_to_list() |> :inet.parse_ipv4_address() |> (case do {:ok, addr}-> addr end))
config :ama, :http_port, (System.get_env("HTTP_PORT") || "1090") |> :erlang.binary_to_integer()

config :ama, :rpc_port, (System.get_env("RPC_PORT") || "4000") |> :erlang.binary_to_integer()
config :ama, :rpc_listen, System.get_env("RPC_LISTEN") || "127.0.0.1"
config :ama, :rpc_user, System.get_env("RPC_USER") || ""
config :ama, :rpc_password, System.get_env("RPC_PASSWORD") || ""


config :ama, :udp_ipv4_tuple, ((System.get_env("UDP_IPV4") || "0.0.0.0") |> :unicode.characters_to_list() |> :inet.parse_ipv4_address() |> (case do {:ok, addr}-> addr end))
config :ama, :udp_port, 36969

#Nodes
config :ama, :seednodes, ["104.218.45.23"]
config :ama, :othernodes, (try do (System.get_env("OTHERNODES") |> String.split(",")) || [] catch _,_ -> [] end)
config :ama, :trustfactor, (try do System.get_env("TRUSTFACTOR") |> :erlang.binary_to_float() catch _,_ -> 0.8 end)

if !Util.verify_time_sync() do
    IO.puts "🔴 🕒 time not synced or ntp client not found 🔴"
end

path = Path.join([work_folder, "sk"])
if !File.exists?(path) do
    IO.puts "No trainer sk (BLS12-381) in #{path} as base58"
    sk = :crypto.strong_rand_bytes(64)
    pk = BlsEx.get_public_key!(sk)
    IO.puts "generated random sk, your pk is #{Base58.encode(pk)}"
    :ok = File.write!(path, Base58.encode(sk))
end
sk = File.read!(path) |> String.trim() |> Base58.decode()
pk = BlsEx.get_public_key!(sk)

config :ama, :trainer_pk_b58, pk |> Base58.encode()
config :ama, :trainer_pk, pk
config :ama, :trainer_sk, sk
config :ama, :trainer_pop, BlsEx.sign!(sk, pk, BLS12AggSig.dst_pop())

#TODO: enable this later
#path = Path.join([work_folder, "trainer_challenge"])
#if !File.exists?(path) do
#    IO.puts "trainer did not solve basic challenge in #{path}"
#    IO.puts "solving challenge to join network.. this can take a while"
#    Enum.each(1..:erlang.system_info(:schedulers_online), fn(_)->
#        :erlang.spawn(fn()-> NodeGen.generate_challenge(pk, sk, work_folder) end)
#    end)
#    receive do _ -> :infinite_loop end
#else
#    <<challenge::12-binary, signature::96-binary>> = File.read!(path)
#    Application.put_env(:ama, :challenge, challenge)
#    Application.put_env(:ama, :challenge_signature, signature)    
#end
