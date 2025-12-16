# Amadeus Smart Contract SDK, Rust

Rust SDK for writing Smart Contracts on the Amadeus blockchain.
For more information on how to deploy and test smart contracts using `amadeusd`, 
visit [assemblyscript](../assemblyscript/README.md). This tutorial showcases 
how to use the rust [CLI]()
to interact with the blockchain.

## Prerequisites

Install Rust and target for building WebAssembly:
```bash
curl https://sh.rustup.rs -sSf | sh
rustup update
rustup target add wasm32-unknown-unknown
```

## Building

To build the wasm smart contracts, simply run the `./build_and_validate.sh`.
The artifacts will be placed in `target/wasm32-unknown-unknown/release/examples`.
Optionally you can optimize the resulting wasm contracts.

```bash
wasm-opt -Oz --enable-bulk-memory target/wasm32-unknown-unknown/release/examples/counter.wasm -o counter.wasm
wasm-opt -Oz --enable-bulk-memory target/wasm32-unknown-unknown/release/examples/deposit.wasm -o deposit.wasm
wasm-opt -Oz --enable-bulk-memory target/wasm32-unknown-unknown/release/examples/coin.wasm -o coin.wasm
wasm-opt -Oz --enable-bulk-memory target/wasm32-unknown-unknown/release/examples/nft.wasm -o nft.wasm
```
### Testing with CLI

You can find the CLI in the [rs_node](https://github.com/valentynfaychuk/rs_node/tree/main/client).
Make sure you have Rust installed and simply follow the instructions below.

```bash
cargo cli gen-sk wallet.sk
cargo cli get-pk --sk wallet.sk

# Claim testnet AMA to the pk at https://mcp.ama.one/testnet-faucet

# Test counter
cargo cli gen-sk counter.sk
export COUNTER_PK=$(cargo cli get-pk --sk counter.sk)
cargo cli tx --sk wallet.sk --url http://testnet.ama.one Coin transfer '[{"b58": "'$COUNTER_PK'"}, "2000000000", "AMA"]'
cargo cli deploy-tx --sk counter.sk counter.wasm --url http://testnet.ama.one
cargo cli tx --sk counter.sk --url http://testnet.ama.one $COUNTER_PK init '[]'
curl "http://testnet.ama.one/api/contract/view/$COUNTER_PK/get"
cargo cli tx --sk wallet.sk --url http://testnet.ama.one $COUNTER_PK increment '["5"]'
curl "http://testnet.ama.one/api/contract/view/$COUNTER_PK/get"

# Test deposit
cargo cli gen-sk deposit.sk
export DEPOSIT_PK=$(cargo cli get-pk --sk deposit.sk)
cargo cli tx --sk wallet.sk Coin transfer '[{"b58": "'$DEPOSIT_PK'"}, "2000000000", "AMA"]' --url http://testnet.ama.one
cargo cli deploy-tx --sk deposit.sk deposit.wasm --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $DEPOSIT_PK balance '["AMA"]' --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $DEPOSIT_PK deposit '[]' AMA 1500000000 --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $DEPOSIT_PK balance '["AMA"]' --url http://testnet.ama.one

# Test coin
cargo cli gen-sk coin.sk
export COIN_PK=$(cargo cli get-pk --sk coin.sk)
cargo cli tx --sk wallet.sk Coin transfer '[{"b58": "'$COIN_PK'"}, "2000000000", "AMA"]' --url http://testnet.ama.one
cargo cli deploy-tx --sk coin.sk coin.wasm --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $COIN_PK deposit '[]' AMA 1500000000 --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $COIN_PK withdraw '["AMA", "500000000"]' --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $COIN_PK withdraw '["AMA", "1000000000"]' --url http://testnet.ama.one

# Test nft
cargo cli gen-sk nft.sk
export NFT_PK=$(cargo cli get-pk --sk nft.sk)
cargo cli tx --sk wallet.sk Coin transfer '[{"b58": "'$NFT_PK'"}, "2000000000", "AMA"]' --url http://testnet.ama.one
cargo cli deploy-tx --sk nft.sk nft.wasm --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $NFT_PK init '[]' --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $NFT_PK claim '[]' --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $NFT_PK view_nft '["AGENTIC", "1"]' --url http://testnet.ama.one
cargo cli tx --sk wallet.sk $NFT_PK claim '[]' --url http://testnet.ama.one
```
