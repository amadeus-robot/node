#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;
use alloc::string::ToString;

#[no_mangle]
pub extern "C" fn init() {
    call("Nft", "create_collection", &[&b"AGENTIC"[..], &b"false"[..]]);
}

#[no_mangle]
pub extern "C" fn view_nft(_collection_ptr: i32, token_ptr: i32) {
    let token = read_string(token_ptr);
    let url = match token.as_str() {
        "1" => "https://ipfs.io/ipfs/bafybeicn7i3soqdgr7dwnrwytgq4zxy7a5jpkizrvhm5mv6bgjd32wm3q4/welcome-to-IPFS.jpg",
        "2" => "https://ipfs.io/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/readme",
        "3" => "https://ipfs.io/ipfs/QmPZ9gcCEpqKTo6aq61g2nXGUhM4iCL3ewB6LDXZCtioEB",
        "4" => "https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o",
        "5" => "https://ipfs.io/ipfs/QmZULkCELmmk5XNfCgTnCyFgAVxBRBXyDHGGMVoLFLiXEN",
        "6" => "https://ipfs.io/ipfs/QmTn4KLRkKPDkB3KpJWGXZHPPh5dFnKqNcPjX4ZcbPvKwv",
        _ => "https://ipfs.io/ipfs/bafybeicn7i3soqdgr7dwnrwytgq4zxy7a5jpkizrvhm5mv6bgjd32wm3q4/welcome-to-IPFS.jpg",
    };
    ret(url);
}

#[no_mangle]
pub extern "C" fn claim() {
    let random = roll_dice();
    log("claiming");
    let caller = account_caller();
    let collection = b"AGENTIC";
    call("Nft", "mint", &[caller.as_slice(), &b"1"[..], collection.as_slice(), &b"1"[..]]);
    let token = random.to_string();
    call("Nft", "mint", &[caller.as_slice(), &b"1"[..], collection.as_slice(), token.as_bytes()]);
    ret(random);
}

fn roll_dice() -> i64 {
    let s = seed();
    ((s.iter().fold(0u64, |a, &b| a.wrapping_add(b as u64)) % 6) + 1) as i64
}
