#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;
use alloc::{vec::Vec};

fn vault_key(symbol: &Vec<u8>) -> Vec<u8> {
    b!("vault:", account_caller(), ":", symbol)
}

#[no_mangle]
pub extern "C" fn init() {
    log("init called");

    let mint_a_billion = encoding::coin_raw(1_000_000_000, 9);
    call!("Coin", "create_and_mint", [
        "USDFAKE", mint_a_billion, 9, "false", "false", "false"
    ]);
}

#[no_mangle]
pub extern "C" fn deposit() {
    log("deposit called");

    let (has_attachment, (symbol, amount)) = get_attachment();
    amadeus_sdk::assert!(has_attachment, "deposit has no attachment");

    let amount_i128 = i128::from_bytes(amount);
    amadeus_sdk::assert!(amount_i128 > 100, "deposit amount less than 100");

    let total_vault_deposited = kv_increment(vault_key(&symbol), amount_i128);
    ret(total_vault_deposited);
}

#[no_mangle]
pub extern "C" fn withdraw(symbol_ptr: i32, amount_ptr: i32) {
    log("withdraw called");

    let withdraw_symbol = read_bytes(symbol_ptr);
    let withdraw_amount = read_bytes(amount_ptr);
    let withdraw_amount_int = encoding::bytes_to_i128(&withdraw_amount);
    amadeus_sdk::assert!(withdraw_amount_int > 0, "amount lte 0");

    let key = vault_key(&withdraw_symbol);
    let vault_balance: i128 = kv_get(&key).unwrap_or(0);
    amadeus_sdk::assert!(vault_balance >= withdraw_amount_int, "insufficient funds");

    kv_increment(key, -withdraw_amount_int);

    call!("Coin", "transfer", [account_caller(), withdraw_amount, withdraw_symbol]);

    ret(vault_balance - withdraw_amount_int);
}
