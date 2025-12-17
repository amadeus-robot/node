#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;
use alloc::{vec::Vec, string::ToString};

fn vault_key(symbol: &str) -> Vec<u8> {
    [&b"vault:"[..], &account_caller(), &b":"[..], symbol.as_bytes()].concat()
}

#[no_mangle]
pub extern "C" fn init() {
    let billion = encoding::coin_raw(1_000_000_000, 9);
    call("Coin", "create_and_mint", &[
        &b"USDFAKE"[..], billion.as_slice(), &b"9"[..],
        &b"false"[..], &b"false"[..], &b"false"[..]
    ]);
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
    let symbol = read_string(symbol_ptr);
    let amount = read_bytes(amount_ptr);
    log("withdraw");
    let amount_int = encoding::bytes_to_u64(&amount);
    let key = vault_key(&symbol);
    let balance = encoding::bytes_to_u64(kv_get(key.as_slice()).as_deref().unwrap_or_default());
    amadeus_sdk::assert!(amount_int > 0, "amount lte 0");
    amadeus_sdk::assert!(balance >= amount_int, "insufficient funds");
    kv_increment(key.as_slice(), -(amount_int as i64));
    call("Coin", "transfer", &[account_caller().as_slice(), amount.as_slice(), symbol.as_bytes()]);
    ret((balance - amount_int).to_string());
}
