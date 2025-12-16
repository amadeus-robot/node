#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;
use alloc::{string::{String, ToString}};

fn mem_read(ptr: i32) -> String {
    unsafe {
        let len = *(ptr as *const i32);
        let data = (ptr + 4) as *const u8;
        String::from_utf8(core::slice::from_raw_parts(data, len as usize).to_vec()).unwrap_or_default()
    }
}

#[no_mangle]
pub extern "C" fn init() {
    call("Nft", "create_collection", &["AGENTIC".as_bytes(), "false".as_bytes()]);
}

#[no_mangle]
pub extern "C" fn view_nft(collection_ptr: i32, token_ptr: i32) {
    ret("https://ipfs.io/ipfs/bafybeicn7i3soqdgr7dwnrwytgq4zxy7a5jpkizrvhm5mv6bgjd32wm3q4/welcome-to-IPFS.jpg");
}

#[no_mangle]
pub extern "C" fn claim() {
    let random = roll_dice();
    log("claiming");
    let caller = account_caller();
    call("Nft", "mint", &[caller.as_slice(), "1".as_bytes(), "AGENTIC".as_bytes(), "1".as_bytes()]);
    let token = random.to_string();
    call("Nft", "mint", &[caller.as_slice(), "1".as_bytes(), "AGENTIC".as_bytes(), token.as_bytes()]);
    ret(random);
}

fn roll_dice() -> i64 {
    let s = seed();
    ((s.iter().fold(0u64, |a, &b| a.wrapping_add(b as u64)) % 6) + 1) as i64
}
