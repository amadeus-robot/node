#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;

#[no_mangle]
pub extern "C" fn init() {
    call!("Nft", "create_collection", ["AGENTIC", "false"]);
}

#[no_mangle]
pub extern "C" fn view_nft(collection_ptr: i32, token_ptr: i32) {
    let collection = read_string(collection_ptr);
    let token = read_bytes(token_ptr);
    let url = match (collection.as_str(), token.as_slice()) {
        ("AGENTIC", b"1") => "https://ipfs.io/ipfs/bafybeicn7i3soqdgr7dwnrwytgq4zxy7a5jpkizrvhm5mv6bgjd32wm3q4/welcome-to-IPFS.jpg",
        ("AGENTIC", b"2") => "https://ipfs.io/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme",
        ("AGENTIC", b"3") => "https://ipfs.io/ipfs/QmPZ9gcCEpqKTo6aq61g2nXGUhM4iCL3ewB6LDXZCtioEB",
        ("AGENTIC", b"4") => "https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o",
        ("AGENTIC", b"5") => "https://ipfs.io/ipfs/QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN",
        ("AGENTIC", b"6") => "https://ipfs.io/ipfs/QmTn4KLRkKPDkB3KpJWGXZHPPh5dFnKqNcPjX4ZcbPvKwv",
        _ => "https://ipfs.io/ipfs/bafybeicn7i3soqdgr7dwnrwytgq4zxy7a5jpkizrvhm5mv6bgjd32wm3q4/welcome-to-IPFS.jpg",
    };
    ret(url);
}

#[no_mangle]
pub extern "C" fn claim() {
    log("claiming");
    call!("Nft", "mint", [account_caller(), 1, "AGENTIC", "2"]);
    call!("Nft", "mint", [account_caller(), 1, "AGENTIC", "2"]);
    let random_token = roll_dice();
    call!("Nft", "mint", [account_caller(), 1, "AGENTIC", random_token]);
    ret(random_token);
}

static mut PRNG_STATE: u64 = 0;
static mut PRNG_INIT: bool = false;

fn roll_dice() -> i64 {
    unsafe {
        if !PRNG_INIT {
            let s = seed();

            // (Using FNV-1a hash algorithm for decent distribution)
            let mut h: u64 = 0xcbf29ce484222325;
            for &byte in s.iter() {
                h = h ^ (byte as u64);
                h = h.wrapping_mul(0x100000001b3);
            }

            PRNG_STATE = h;
            PRNG_INIT = true;
        }

        // 2. "Increment" the seed (Step the LCG)
        // Constants from Musl Libc / Knuth
        // state = state * 6364136223846793005 + 1442695040888963407
        PRNG_STATE = PRNG_STATE
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);

        let result = (PRNG_STATE >> 32) as i64;
        (result.abs() % 6) + 1
    }
}
