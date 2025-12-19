### Local contract testing

Run the local testnet node `TESTNET=true WORKFOLDER=/tmp/testnet0 HTTP_IPV4=127.0.0.1 HTTP_PORT=80 ./amadeusd` with 10 random keys.  
  
0_counter  
```elixir
key0 = Application.fetch_env!(:ama, :keys) |> Enum.at(0)
path = "/home/user/project/node/contract_samples/assemblyscript/counter.wasm"
Testnet.deploy key0, path
Testnet.call key0.seed, key0.pk, "get", []
Testnet.call key0.seed, key0.pk, "increment", ["1"]
Testnet.call key0.seed, key0.pk, "increment", ["1"]
Testnet.call key0.seed, key0.pk, "increment", ["1"]

key9 = Application.fetch_env!(:ama, :keys) |> Enum.at(9)
Testnet.deploy key9, path
Testnet.call key0.seed, key0.pk, "increment_another_counter", [key9.pk]
```

1_deposit
```elixir
key1 = Application.fetch_env!(:ama, :keys) |> Enum.at(1)
path = "/home/user/project/node/contract_samples/assemblyscript/deposit.wasm"
Testnet.deploy key1, path
Testnet.call key1.seed, key1.pk, "deposit", [], "AMA", "100"
Testnet.call key1.seed, key1.pk, "withdraw", ["AMA", "10"]
Testnet.view key1.pk, "balance", ["AMA"], key2.pk
```

2_coin
```elixir
key2 = Application.fetch_env!(:ama, :keys) |> Enum.at(2)
path = "/home/user/project/node/contract_samples/assemblyscript/coin.wasm"
Testnet.deploy key2, path, "init"
API.Wallet.balance key2.pk, "USDFAKE"
```

3_nft
```elixir
key3 = Application.fetch_env!(:ama, :keys) |> Enum.at(3)
path = "/home/user/project/node/contract_samples/assemblyscript/nft.wasm"
Testnet.deploy key3, path, "init" 
Testnet.call key3.seed, key3.pk, "mint", []
Testnet.call key3.seed, key3.pk, "mint", []
Testnet.call key3.seed, key3.pk, "mint", []
Testnet.view key3.pk, "view_nft", ["AGENTIC", "1"]
```
