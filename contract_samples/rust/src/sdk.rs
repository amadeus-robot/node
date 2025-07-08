use std::ffi::{c_char, c_int};
use std::slice;
use std::str;

// External function declarations
#[link(wasm_import_module = "env")]
extern "C" {
    fn import_log(ptr: *const c_char, len: c_int);
    fn import_return_value(ptr: *const c_char, len: c_int);
    fn import_kv_increment(key_ptr: *const c_char, key_len: c_int, val_ptr: *const c_char, val_len: c_int) -> *mut c_char;
    fn import_kv_get(ptr: *const c_char, len: c_int) -> *mut c_char;
    fn import_call_0(module_ptr: *const c_char, module_len: c_int, function_ptr: *const c_char, function_len: c_int) -> *mut c_char;
    fn import_call_1(module_ptr: *const c_char, module_len: c_int, function_ptr: *const c_char, function_len: c_int,
                     args_1_ptr: *const c_char, args_1_len: c_int) -> *mut c_char;
    fn import_call_2(module_ptr: *const c_char, module_len: c_int, function_ptr: *const c_char, function_len: c_int,
                     args_1_ptr: *const c_char, args_1_len: c_int, args_2_ptr: *const c_char, args_2_len: c_int) -> *mut c_char;
    fn import_call_3(module_ptr: *const c_char, module_len: c_int, function_ptr: *const c_char, function_len: c_int,
                     args_1_ptr: *const c_char, args_1_len: c_int, args_2_ptr: *const c_char, args_2_len: c_int,
                     args_3_ptr: *const c_char, args_3_len: c_int) -> *mut c_char;
    fn import_call_4(module_ptr: *const c_char, module_len: c_int, function_ptr: *const c_char, function_len: c_int,
                     args_1_ptr: *const c_char, args_1_len: c_int, args_2_ptr: *const c_char, args_2_len: c_int,
                     args_3_ptr: *const c_char, args_3_len: c_int, args_4_ptr: *const c_char, args_4_len: c_int) -> *mut c_char;
    
    // Account and transaction related functions
    fn entry_signer_ptr() -> *mut c_char;
    fn entry_prev_hash_ptr() -> *mut c_char;
    fn entry_vr_ptr() -> *mut c_char;
    fn entry_dr_ptr() -> *mut c_char;
    fn tx_signer_ptr() -> *mut c_char;
    fn account_current_ptr() -> *mut c_char;
    fn account_caller_ptr() -> *mut c_char;
    fn account_origin_ptr() -> *mut c_char;
    fn attached_symbol_ptr() -> *mut c_char;
    fn attached_amount_ptr() -> *mut c_char;
    
    // Entry and transaction data
    fn entry_slot() -> i64;
    fn entry_prev_slot() -> i64;
    fn entry_height() -> i64;
    fn entry_epoch() -> i64;
    fn tx_nonce() -> i64;
}

// Memory management functions
fn memory_read_bytes(ptr: *mut c_char) -> Vec<u8> {
    if ptr.is_null() {
        return Vec::new();
    }
    
    unsafe {
        let length = *(ptr as *const i32);
        let data_ptr = ptr.add(4) as *const u8;
        let slice = slice::from_raw_parts(data_ptr, length as usize);
        slice.to_vec()
    }
}

fn memory_read_string(ptr: *mut c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    
    unsafe {
        let length = *(ptr as *const i32);
        let data_ptr = ptr.add(4) as *const u8;
        let slice = slice::from_raw_parts(data_ptr, length as usize);
        String::from_utf8_lossy(slice).to_string()
    }
}

// Utility functions
pub fn b(s: &str) -> Vec<u8> {
    s.as_bytes().to_vec()
}

pub fn concat(chunks: &[&[u8]]) -> Vec<u8> {
    let total_len: usize = chunks.iter().map(|chunk| chunk.len()).sum();
    let mut result = Vec::with_capacity(total_len);
    
    for chunk in chunks {
        result.extend_from_slice(chunk);
    }
    
    result
}

// Base58 encoding/decoding
const BASE58_ALPHABET: &str = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

pub fn b58<T: AsRef<[u8]>>(data: T) -> String {
    let bytes = data.as_ref();
    if bytes.is_empty() {
        return String::new();
    }
    
    let mut digits = Vec::new();
    let mut carry = 0u32;
    
    for &byte in bytes {
        carry = carry * 256 + byte as u32;
        
        for digit in &mut digits {
            carry += *digit as u32 * 256;
            *digit = (carry % 58) as u8;
            carry /= 58;
        }
        
        while carry > 0 {
            digits.push((carry % 58) as u8);
            carry /= 58;
        }
    }
    
    // Handle leading zeros
    let mut result = String::new();
    for &byte in bytes {
        if byte == 0 {
            result.push('1');
        } else {
            break;
        }
    }
    
    // Convert digits to base58
    for &digit in digits.iter().rev() {
        result.push(BASE58_ALPHABET.chars().nth(digit as usize).unwrap());
    }
    
    result
}

pub fn b58_dec(s: &str) -> Option<Vec<u8>> {
    if s.is_empty() {
        return Some(Vec::new());
    }
    
    let mut bytes = Vec::new();
    let mut carry = 0u32;
    
    for ch in s.chars() {
        let digit = BASE58_ALPHABET.find(ch)? as u32;
        carry = carry * 58 + digit;
        
        for byte in &mut bytes {
            carry += *byte as u32 * 58;
            *byte = (carry & 0xff) as u8;
            carry >>= 8;
        }
        
        while carry > 0 {
            bytes.push((carry & 0xff) as u8);
            carry >>= 8;
        }
    }
    
    // Handle leading ones
    let mut result = Vec::new();
    for ch in s.chars() {
        if ch == '1' {
            result.push(0);
        } else {
            break;
        }
    }
    
    result.extend(bytes.iter().rev());
    Some(result)
}

// Account and transaction functions
pub fn entry_signer() -> Vec<u8> {
    unsafe { memory_read_bytes(entry_signer_ptr()) }
}

pub fn entry_prev_hash() -> Vec<u8> {
    unsafe { memory_read_bytes(entry_prev_hash_ptr()) }
}

pub fn entry_vr() -> Vec<u8> {
    unsafe { memory_read_bytes(entry_vr_ptr()) }
}

pub fn entry_dr() -> Vec<u8> {
    unsafe { memory_read_bytes(entry_dr_ptr()) }
}

pub fn tx_signer() -> Vec<u8> {
    unsafe { memory_read_bytes(tx_signer_ptr()) }
}

pub fn account_current() -> Vec<u8> {
    unsafe { memory_read_bytes(account_current_ptr()) }
}

pub fn account_caller() -> Vec<u8> {
    unsafe { memory_read_bytes(account_caller_ptr()) }
}

pub fn account_origin() -> Vec<u8> {
    unsafe { memory_read_bytes(account_origin_ptr()) }
}

pub fn attached_symbol() -> String {
    unsafe { memory_read_string(attached_symbol_ptr()) }
}

pub fn attached_amount() -> String {
    unsafe { memory_read_string(attached_amount_ptr()) }
}

// These functions are already available as external functions
// Use them directly: unsafe { entry_slot() }, etc.

// Logging and return value functions
pub fn log(line: &str) {
    unsafe {
        import_log(line.as_ptr() as *const c_char, line.len() as c_int);
    }
}

pub fn return_value<T: AsRef<str>>(ret: T) {
    let s = ret.as_ref();
    unsafe {
        import_return_value(s.as_ptr() as *const c_char, s.len() as c_int);
    }
}

// KV store functions
pub fn kv_increment<T: AsRef<[u8]>>(key: T, val: &str) -> String {
    let key_bytes = key.as_ref();
    unsafe {
        let result_ptr = import_kv_increment(
            key_bytes.as_ptr() as *const c_char,
            key_bytes.len() as c_int,
            val.as_ptr() as *const c_char,
            val.len() as c_int
        );
        memory_read_string(result_ptr)
    }
}

pub fn kv_get<T: AsRef<str>>(key: T) -> String {
    let key_str = key.as_ref();
    unsafe {
        let result_ptr = import_kv_get(
            key_str.as_ptr() as *const c_char,
            key_str.len() as c_int
        );
        memory_read_string(result_ptr)
    }
}

pub fn kv_get_bytes<T: AsRef<[u8]>>(key: T) -> u64 {
    let key_bytes = key.as_ref();
    unsafe {
        let result_ptr = import_kv_get(
            key_bytes.as_ptr() as *const c_char,
            key_bytes.len() as c_int
        );
        let result_str = memory_read_string(result_ptr);
        result_str.parse::<u64>().unwrap_or(0)
    }
}

// Contract call functions
pub fn call(contract: &[u8], func: &str, args: &[&[u8]]) -> String {
    unsafe {
        let result_ptr = match args.len() {
            0 => import_call_0(
                contract.as_ptr() as *const c_char,
                contract.len() as c_int,
                func.as_ptr() as *const c_char,
                func.len() as c_int
            ),
            1 => import_call_1(
                contract.as_ptr() as *const c_char,
                contract.len() as c_int,
                func.as_ptr() as *const c_char,
                func.len() as c_int,
                args[0].as_ptr() as *const c_char,
                args[0].len() as c_int
            ),
            2 => import_call_2(
                contract.as_ptr() as *const c_char,
                contract.len() as c_int,
                func.as_ptr() as *const c_char,
                func.len() as c_int,
                args[0].as_ptr() as *const c_char,
                args[0].len() as c_int,
                args[1].as_ptr() as *const c_char,
                args[1].len() as c_int
            ),
            3 => import_call_3(
                contract.as_ptr() as *const c_char,
                contract.len() as c_int,
                func.as_ptr() as *const c_char,
                func.len() as c_int,
                args[0].as_ptr() as *const c_char,
                args[0].len() as c_int,
                args[1].as_ptr() as *const c_char,
                args[1].len() as c_int,
                args[2].as_ptr() as *const c_char,
                args[2].len() as c_int
            ),
            4 => import_call_4(
                contract.as_ptr() as *const c_char,
                contract.len() as c_int,
                func.as_ptr() as *const c_char,
                func.len() as c_int,
                args[0].as_ptr() as *const c_char,
                args[0].len() as c_int,
                args[1].as_ptr() as *const c_char,
                args[1].len() as c_int,
                args[2].as_ptr() as *const c_char,
                args[2].len() as c_int,
                args[3].as_ptr() as *const c_char,
                args[3].len() as c_int
            ),
            _ => panic!("Too many arguments for call function"),
        };
        memory_read_string(result_ptr)
    }
} 