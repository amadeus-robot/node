#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;
use alloc::{vec::Vec, string::{String, ToString}};

fn mem_read(ptr: i32) -> String {
    unsafe {
        let len = *(ptr as *const i32);
        let data = (ptr + 4) as *const u8;
        String::from_utf8(core::slice::from_raw_parts(data, len as usize).to_vec()).unwrap_or_default()
    }
}

fn vault_key(symbol: &str) -> Vec<u8> {
    let mut k = b"vault:".to_vec();
    k.extend_from_slice(&account_caller());
    k.push(b':');
    k.extend_from_slice(symbol.as_bytes());
    k
}

#[no_mangle]
pub extern "C" fn balance(symbol_ptr: i32) {
    let key = vault_key(&mem_read(symbol_ptr));
    ret(encoding::bytes_to_i64(kv_get(key.as_slice()).as_deref(), 0));
}

#[no_mangle]
pub extern "C" fn deposit() {
    let symbol = attached_symbol();
    let amount = attached_amount();
    log("deposit");
    ret(kv_increment(vault_key(&symbol).as_slice(), amount.as_str()));
}

#[no_mangle]
pub extern "C" fn withdraw(symbol_ptr: i32, amount_ptr: i32) {
    let symbol = mem_read(symbol_ptr);
    let amount = mem_read(amount_ptr);
    log("withdraw");
    let amount_int = encoding::bytes_to_u64(Some(amount.as_bytes()), 0);
    let key = vault_key(&symbol);
    let balance = encoding::bytes_to_u64(kv_get(key.as_slice()).as_deref(), 0);
    amadeus_sdk::assert!(amount_int > 0, "amount lte 0");
    amadeus_sdk::assert!(balance >= amount_int, "insufficient funds");
    kv_increment(key.as_slice(), -(amount_int as i64));
    call("Coin", "transfer", &[account_caller().as_slice(), amount.as_bytes(), symbol.as_bytes()]);
    ret((balance - amount_int).to_string());
}

#[no_mangle]
pub extern "C" fn burn(symbol_ptr: i32, amount_ptr: i32) {
    let symbol = mem_read(symbol_ptr);
    let amount = mem_read(amount_ptr);
    log("burn");
    ret(call("Coin", "transfer", &[[0u8; 48].as_slice(), amount.as_bytes(), symbol.as_bytes()]));
}
