#![no_std]
#![no_main]
extern crate alloc;
use amadeus_sdk::*;

#[no_mangle]
pub extern "C" fn init() {
    log("Init called during deployment of contract");
    kv_put("inited", "true");
}

#[no_mangle]
pub extern "C" fn get() {
    ret(kv_get("the_counter").unwrap_or(0));
}

#[no_mangle]
pub extern "C" fn increment(amount_ptr: i32) {
    let amount = read_bytes(amount_ptr);
    let new_counter = kv_increment("the_counter", amount);
    ret(new_counter);
}

#[no_mangle]
pub extern "C" fn increment_another_counter(contract_ptr: i32) {
    let contract = read_bytes(contract_ptr);
    let incr_by = 3i64;
    log("increment_another_counter");
    ret(call!(contract.as_slice(), "increment", [incr_by]));
}
