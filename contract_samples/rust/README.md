# Amadeus Smart Contract SDK, Rust

Rust SDK for writing Smart Contracts on the Amadeus blockchain.
For more information on how to deploy and test smart contracts using `amadeusd`, 
visit [assemblyscript](../assemblyscript/README.md). This tutorial showcases 
how to use the rust [CLI]()
to interact with the blockchain.

## Prerequisites

Install Rust and add a wasm target.

```bash
curl https://sh.rustup.rs -sSf | sh
rustup update
rustup target add wasm32-unknown-unknown
```

Install `amadeus-cli`.

```bash
cargo install amadeus-cli
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

### Testing

Make sure you have `amadeus-cli` installed.
Follow the code snippet below to run each example on the testnet.

```bash
ama gen-sk wallet.sk
ama get-pk --sk wallet.sk

# NOTE: Claim testnet AMA to the pk at https://mcp.ama.one/testnet-faucet

ama gen-sk counter.sk
export COUNTER_PK=$(ama get-pk --sk counter.sk)
ama tx --sk wallet.sk --url https://testnet-rpc.ama.one Coin transfer '[{"b58": "'$COUNTER_PK'"}, "2000000000", "AMA"]'
ama deploy-tx --sk counter.sk counter.wasm --url https://testnet-rpc.ama.one
ama tx --sk counter.sk --url https://testnet-rpc.ama.one $COUNTER_PK init '[]'
curl "https://testnet-rpc.ama.one/api/contract/view/$COUNTER_PK/get"
ama tx --sk wallet.sk --url https://testnet-rpc.ama.one $COUNTER_PK increment '["5"]'
curl "https://testnet-rpc.ama.one/api/contract/view/$COUNTER_PK/get"

ama gen-sk deposit.sk
export DEPOSIT_PK=$(ama get-pk --sk deposit.sk)
ama tx --sk wallet.sk Coin transfer '[{"b58": "'$DEPOSIT_PK'"}, "2000000000", "AMA"]' --url https://testnet-rpc.ama.one
ama deploy-tx --sk deposit.sk deposit.wasm --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $DEPOSIT_PK balance '["AMA"]' --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $DEPOSIT_PK deposit '[]' AMA 1500000000 --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $DEPOSIT_PK balance '["AMA"]' --url https://testnet-rpc.ama.one

ama gen-sk coin.sk
export COIN_PK=$(ama get-pk --sk coin.sk)
ama tx --sk wallet.sk Coin transfer '[{"b58": "'$COIN_PK'"}, "2000000000", "AMA"]' --url https://testnet-rpc.ama.one
ama deploy-tx --sk coin.sk coin.wasm --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $COIN_PK deposit '[]' AMA 1500000000 --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $COIN_PK withdraw '["AMA", "500000000"]' --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $COIN_PK withdraw '["AMA", "1000000000"]' --url https://testnet-rpc.ama.one

# WARNING: "AGENTIC" collection already exists, so replace the name below
# and also in the examples/nft.rs file (don't forget to rebuild nft.wasm)
ama gen-sk nft.sk
export NFT_PK=$(ama get-pk --sk nft.sk)
ama tx --sk wallet.sk Coin transfer '[{"b58": "'$NFT_PK'"}, "2000000000", "AMA"]' --url https://testnet-rpc.ama.one
ama deploy-tx --sk nft.sk nft.wasm --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $NFT_PK init '[]' --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $NFT_PK claim '[]' --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $NFT_PK view_nft '["AGENTIC", "1"]' --url https://testnet-rpc.ama.one
ama tx --sk wallet.sk $NFT_PK claim '[]' --url https://testnet-rpc.ama.one
```
