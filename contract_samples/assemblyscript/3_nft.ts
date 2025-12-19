import * as sdk from "./sdk";
import { b, bcat, b58 } from "./sdk";

export function init(): void {
  //Create a collection
  //Soulbound = false
  sdk.call("Nft", "create_collection", [b("AGENTIC"), b("false")])
}

export function view_nft(collection_ptr: i32, token_ptr: i32): void {
  let collection = sdk.memory_read_string(collection_ptr)
  let token = sdk.memory_read_string(token_ptr)
  const key = `${collection}:${token}`
  switch (key) {
    case "AGENTIC:2":
      sdk.ret("https://ipfs.io/ipfs/QmWBaeu6y1zEcKbsEqCuhuDHPL3W8pZouCPdafMCRCSUWk");
    case "AGENTIC:6":
      sdk.ret("https://ipfs.io/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi");
    default:
      sdk.ret("https://ipfs.io/ipfs/bafybeicn7i3soqdgr7dwnrwytgq4zxy7a5jpkizrvhm5mv6bgjd32wm3q4/welcome-to-IPFS.jpg");
  }
}

export function claim(): void {
  let random_nft = roll_dice();
  sdk.log(`claiming ${random_nft}`)
  sdk.call("Nft", "mint", [sdk.account_caller(), b("1"), b("AGENTIC"), b(1)])
  sdk.call("Nft", "mint", [sdk.account_caller(), b("1"), b("AGENTIC"), b(random_nft)])
  sdk.ret(random_nft);
}

//Current: VRF Stage 1 is used.
//Seed is signature of previous VRF by current validator.
//A malicious validator can do a withholding attack (not include a TX if the RNG is unfavorable)

//Coming Soon: VRF Stage 2 will be only attackable if 67% are malicious as it will use BLS Threshold /w DKG
export function roll_dice(): i64 {
  const val = Math.random(); // Returns 0.0 to 1.0
  return floor(val * 6) as i32 + 1; // Returns 1-6
}
