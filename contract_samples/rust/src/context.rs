use alloc::{vec::Vec, string::String};

fn read_bytes(ptr: i32) -> Vec<u8> {
    unsafe {
        let len = *(ptr as *const i32);
        let data = (ptr + 4) as *const u8;
        core::slice::from_raw_parts(data, len as usize).to_vec()
    }
}

fn read_string(ptr: i32) -> String {
    String::from_utf8(read_bytes(ptr)).unwrap_or_default()
}

fn read_u64(ptr: i32) -> u64 {
    unsafe { *(ptr as *const u64) }
}

pub fn seed() -> Vec<u8> { read_bytes(1100) }
pub fn entry_slot() -> u64 { read_u64(2000) }
pub fn entry_height() -> u64 { read_u64(2010) }
pub fn entry_epoch() -> u64 { read_u64(2020) }
pub fn entry_signer() -> Vec<u8> { read_bytes(2100) }
pub fn entry_prev_hash() -> Vec<u8> { read_bytes(2200) }
pub fn entry_vr() -> Vec<u8> { read_bytes(2300) }
pub fn entry_dr() -> Vec<u8> { read_bytes(2400) }
pub fn tx_nonce() -> u64 { read_u64(3000) }
pub fn tx_signer() -> Vec<u8> { read_bytes(3100) }
pub fn account_current() -> Vec<u8> { read_bytes(4000) }
pub fn account_caller() -> Vec<u8> { read_bytes(4100) }
pub fn account_origin() -> Vec<u8> { read_bytes(4200) }
pub fn attached_symbol() -> String { read_string(5000) }
pub fn attached_amount() -> String { read_string(5100) }
