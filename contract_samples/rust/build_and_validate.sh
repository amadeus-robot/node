#!/bin/bash

set -e

# Build each example
cargo build --example counter --target wasm32-unknown-unknown --release
cargo build --example deposit --target wasm32-unknown-unknown --release
cargo build --example coin --target wasm32-unknown-unknown --release
cargo build --example nft --target wasm32-unknown-unknown --release

# Validate each contract
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @target/wasm32-unknown-unknown/release/examples/counter.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @target/wasm32-unknown-unknown/release/examples/deposit.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @target/wasm32-unknown-unknown/release/examples/coin.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @target/wasm32-unknown-unknown/release/examples/nft.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
