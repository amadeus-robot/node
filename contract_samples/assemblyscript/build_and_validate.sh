#curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
#npm install --global assemblyscript

asc 0_counter.ts --target release --importMemory --memoryBase 65536 --outFile counter.wasm
asc 1_deposit.ts --target release --importMemory --memoryBase 65536 --outFile deposit.wasm
asc 2_coin.ts --target release --importMemory --memoryBase 65536 --outFile coin.wasm
asc 3_nft.ts --target release --importMemory --memoryBase 65536 --outFile nft.wasm
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @counter.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @deposit.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @coin.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
curl -X POST -H "Content-Type: application/octet-stream" --data-binary @nft.wasm https://mainnet-rpc.ama.one/api/contract/validate
echo ""
