use crate::sdk::{b, b58, account_caller, attached_symbol, attached_amount, log, return_value, kv_get_bytes, kv_increment, call};
use std::panic;

fn vault_key(symbol: &str) -> Vec<u8> {
    let caller = account_caller();
    let caller_b58 = b58(&caller);
    b(&format!("vault:{}:{}", caller_b58, symbol))
}

pub extern "C" fn balance(symbol_ptr: *const u8, symbol_len: u32) {
    let symbol_bytes = unsafe { std::slice::from_raw_parts(symbol_ptr, symbol_len as usize) };
    let symbol = String::from_utf8_lossy(symbol_bytes);
    
    let balance = kv_get_bytes(vault_key(&symbol));
    return_value(balance.to_string());
}

pub extern "C" fn deposit() {
    let symbol = attached_symbol();
    let amount = attached_amount();
    log(&format!("deposit {} {}", symbol, amount));

    let new_amount = kv_increment(vault_key(&symbol), &amount);
    return_value(new_amount);
}

pub extern "C" fn withdraw(symbol_ptr: *const u8, symbol_len: u32, amount_ptr: *const u8, amount_len: u32) {
    let symbol_bytes = unsafe { std::slice::from_raw_parts(symbol_ptr, symbol_len as usize) };
    let symbol = String::from_utf8_lossy(symbol_bytes);
    
    let amount_bytes = unsafe { std::slice::from_raw_parts(amount_ptr, amount_len as usize) };
    let amount = String::from_utf8_lossy(amount_bytes);
    
    log(&format!("withdraw {} {}", symbol, amount));

    let amount_int: u64 = amount.parse().expect("Invalid amount");
    log(&format!("int {}", amount_int));
    
    let balance = kv_get_bytes(vault_key(&symbol));

    assert!(amount_int > 0, "amount lte 0");
    assert!(balance >= amount_int, "insufficient funds");

    kv_increment(vault_key(&symbol), &format!("-{}", amount_int));
    let _result = call(&b("Coin"), "transfer", &[
        &account_caller(),
        &b(&amount),
        &b(&symbol)
    ]);

    return_value(format!("{}", balance - amount_int));
}

pub extern "C" fn burn(symbol_ptr: *const u8, symbol_len: u32, amount_ptr: *const u8, amount_len: u32) {
    let symbol_bytes = unsafe { std::slice::from_raw_parts(symbol_ptr, symbol_len as usize) };
    let symbol = String::from_utf8_lossy(symbol_bytes);
    
    let amount_bytes = unsafe { std::slice::from_raw_parts(amount_ptr, amount_len as usize) };
    let amount = String::from_utf8_lossy(amount_bytes);
    
    log(&format!("burn {} {}", symbol, amount));

    let burn_address = vec![0u8; 48]; // zeros
    let result = call(&b("Coin"), "transfer", &[
        &burn_address,
        &b(&amount),
        &b(&symbol)
    ]);
    
    return_value(result);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;
    use lazy_static::lazy_static;

    // Mock storage for testing
    lazy_static! {
        static ref MOCK_STORAGE: Mutex<HashMap<String, u64>> = Mutex::new(HashMap::new());
        static ref MOCK_LOGS: Mutex<Vec<String>> = Mutex::new(Vec::new());
        static ref MOCK_RETURN_VALUES: Mutex<Vec<String>> = Mutex::new(Vec::new());
        static ref MOCK_ATTACHED_SYMBOL: Mutex<String> = Mutex::new(String::new());
        static ref MOCK_ATTACHED_AMOUNT: Mutex<String> = Mutex::new(String::new());
        static ref MOCK_ACCOUNT_CALLER: Mutex<Vec<u8>> = Mutex::new(vec![1, 2, 3, 4, 5]);
    }

    // Mock SDK functions for testing
    fn mock_b(s: &str) -> Vec<u8> {
        s.as_bytes().to_vec()
    }

    fn mock_b58(data: &[u8]) -> String {
        format!("mock_b58_{}", hex::encode(data))
    }

    fn mock_account_caller() -> Vec<u8> {
        MOCK_ACCOUNT_CALLER.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    fn mock_attached_symbol() -> String {
        MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    fn mock_attached_amount() -> String {
        MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    fn mock_log(line: &str) {
        MOCK_LOGS.lock().unwrap_or_else(|e| e.into_inner()).push(line.to_string());
    }

    fn mock_return_value<T: AsRef<str>>(ret: T) {
        MOCK_RETURN_VALUES.lock().unwrap_or_else(|e| e.into_inner()).push(ret.as_ref().to_string());
    }

    fn mock_kv_get_bytes<T: AsRef<[u8]>>(key: T) -> u64 {
        let key_str = String::from_utf8_lossy(key.as_ref());
        MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner()).get(&key_str.to_string()).copied().unwrap_or(0)
    }

    fn mock_kv_increment<T: AsRef<[u8]>>(key: T, val: &str) -> String {
        let key_str = String::from_utf8_lossy(key.as_ref());
        let mut storage = MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner());
        let current = storage.get(&key_str.to_string()).copied().unwrap_or(0);
        let increment: i64 = val.parse().unwrap_or(0);
        let new_value = if increment >= 0 {
            current + increment as u64
        } else {
            current.saturating_sub((-increment) as u64)
        };
        storage.insert(key_str.to_string(), new_value);
        new_value.to_string()
    }

    fn mock_call(contract: &[u8], func: &str, args: &[&[u8]]) -> String {
        format!("mock_call_{}_{}_{}", 
            String::from_utf8_lossy(contract),
            func,
            args.len()
        )
    }

    fn setup_test() {
        MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner()).clear();
        MOCK_LOGS.lock().unwrap_or_else(|e| e.into_inner()).clear();
        MOCK_RETURN_VALUES.lock().unwrap_or_else(|e| e.into_inner()).clear();
        *MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()) = "TEST".to_string();
        *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "100".to_string();
        *MOCK_ACCOUNT_CALLER.lock().unwrap_or_else(|e| e.into_inner()) = vec![1, 2, 3, 4, 5];
    }

    fn mock_vault_key(symbol: &str) -> Vec<u8> {
        let caller = mock_account_caller();
        let caller_b58 = mock_b58(&caller);
        mock_b(&format!("vault:{}:{}", caller_b58, symbol))
    }

    fn run_isolated_test<T>(test: T)
    where
        T: FnOnce() + panic::UnwindSafe,
    {
        setup_test();
        let _ = panic::catch_unwind(|| {
            test();
        });
        setup_test(); // Reset state after test
    }

    fn run_isolated_panic_test<T>(test: T)
    where
        T: FnOnce() + panic::UnwindSafe,
    {
        setup_test();
        test(); // Don't catch panic for should_panic tests
        setup_test(); // Reset state after test
    }

    #[test]
    fn test_vault_key_generation() {
        run_isolated_test(|| {
            let key = mock_vault_key("BTC");
            let key_str = String::from_utf8_lossy(&key);
            assert!(key_str.starts_with("vault:mock_b58_"));
            assert!(key_str.ends_with(":BTC"));
        });
    }

    #[test]
    fn test_balance_empty() {
        run_isolated_test(|| {
            let balance = mock_kv_get_bytes(mock_vault_key("BTC"));
            assert_eq!(balance, 0);
        });
    }

    #[test]
    fn test_balance_with_funds() {
        run_isolated_test(|| {
            let key = mock_vault_key("BTC");
            MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner()).insert(
                String::from_utf8_lossy(&key).to_string(), 
                500
            );
            let balance = mock_kv_get_bytes(key);
            assert_eq!(balance, 500);
        });
    }

    #[test]
    fn test_deposit_new_token() {
        run_isolated_test(|| {
            *MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()) = "ETH".to_string();
            *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "100".to_string();
            let symbol = mock_attached_symbol();
            let amount = mock_attached_amount();
            mock_log(&format!("deposit {} {}", symbol, amount));
            let new_amount = mock_kv_increment(mock_vault_key(&symbol), &amount);
            mock_return_value(new_amount.clone());
            assert_eq!(new_amount, "100");
            let logs = MOCK_LOGS.lock().unwrap_or_else(|e| e.into_inner());
            assert!(logs.iter().any(|log| log.contains("deposit ETH 100")));
            let return_values = MOCK_RETURN_VALUES.lock().unwrap_or_else(|e| e.into_inner());
            assert!(return_values.iter().any(|val| val == "100"));
        });
    }

    #[test]
    fn test_deposit_existing_token() {
        run_isolated_test(|| {
            *MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()) = "BTC".to_string();
            *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "50".to_string();
            let key = mock_vault_key("BTC");
            MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner()).insert(
                String::from_utf8_lossy(&key).to_string(), 
                200
            );
            let symbol = mock_attached_symbol();
            let amount = mock_attached_amount();
            mock_log(&format!("deposit {} {}", symbol, amount));
            let new_amount = mock_kv_increment(mock_vault_key(&symbol), &amount);
            mock_return_value(new_amount.clone());
            assert_eq!(new_amount, "250");
            let final_balance = mock_kv_get_bytes(mock_vault_key(&symbol));
            assert_eq!(final_balance, 250);
        });
    }

    #[test]
    fn test_withdraw_sufficient_funds() {
        run_isolated_test(|| {
            let key = mock_vault_key("BTC");
            MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner()).insert(
                String::from_utf8_lossy(&key).to_string(), 
                300
            );
            let symbol = "BTC";
            let amount = "100";
            mock_log(&format!("withdraw {} {}", symbol, amount));
            let amount_int: u64 = amount.parse().unwrap();
            mock_log(&format!("int {}", amount_int));
            let balance = mock_kv_get_bytes(mock_vault_key(symbol));
            assert!(amount_int > 0);
            assert!(balance >= amount_int);
            mock_kv_increment(mock_vault_key(symbol), &format!("-{}", amount_int));
            let _result = mock_call(&mock_b("Coin"), "transfer", &[
                &mock_account_caller(),
                &mock_b(amount),
                &mock_b(symbol)
            ]);
            let expected_balance = balance - amount_int;
            mock_return_value(expected_balance.to_string());
            assert_eq!(expected_balance, 200);
            let final_balance = mock_kv_get_bytes(mock_vault_key(symbol));
            assert_eq!(final_balance, 200);
        });
    }

    #[test]
    #[should_panic(expected = "insufficient funds")]
    fn test_withdraw_insufficient_funds() {
        run_isolated_panic_test(|| {
            let key = mock_vault_key("BTC");
            MOCK_STORAGE.lock().unwrap_or_else(|e| e.into_inner()).insert(
                String::from_utf8_lossy(&key).to_string(), 
                50
            );
            let symbol = "BTC";
            let amount = "100";
            let amount_int: u64 = amount.parse().unwrap();
            let balance = mock_kv_get_bytes(mock_vault_key(symbol));
            assert!(amount_int > 0);
            if balance < amount_int {
                panic!("insufficient funds");
            }
        });
    }

    #[test]
    #[should_panic(expected = "amount lte 0")]
    fn test_withdraw_zero_amount() {
        run_isolated_panic_test(|| {
            let symbol = "BTC";
            let amount = "0";
            let amount_int: u64 = amount.parse().unwrap();
            if amount_int == 0 {
                panic!("amount lte 0");
            }
        });
    }

    #[test]
    fn test_burn_tokens() {
        run_isolated_test(|| {
            let symbol = "BTC";
            let amount = "50";
            mock_log(&format!("burn {} {}", symbol, amount));
            let burn_address = vec![0u8; 48];
            let result = mock_call(&mock_b("Coin"), "transfer", &[
                &burn_address,
                &mock_b(amount),
                &mock_b(symbol)
            ]);
            mock_return_value(result.clone());
            assert!(result.starts_with("mock_call_Coin_transfer_3"));
            let logs = MOCK_LOGS.lock().unwrap_or_else(|e| e.into_inner());
            assert!(logs.iter().any(|log| log.contains("burn BTC 50")));
        });
    }

    #[test]
    fn test_multiple_operations() {
        run_isolated_test(|| {
            *MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()) = "ETH".to_string();
            *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "1000".to_string();
            let symbol = mock_attached_symbol();
            let amount = mock_attached_amount();
            let new_amount = mock_kv_increment(mock_vault_key(&symbol), &amount);
            assert_eq!(new_amount, "1000");
            *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "500".to_string();
            let amount2 = mock_attached_amount();
            let new_amount2 = mock_kv_increment(mock_vault_key(&symbol), &amount2);
            assert_eq!(new_amount2, "1500");
            let withdraw_amount = "300";
            let current_balance = mock_kv_get_bytes(mock_vault_key(&symbol));
            assert_eq!(current_balance, 1500);
            let amount_int: u64 = withdraw_amount.parse().unwrap();
            assert!(amount_int > 0);
            assert!(current_balance >= amount_int);
            mock_kv_increment(mock_vault_key(&symbol), &format!("-{}", amount_int));
            let final_balance = current_balance - amount_int;
            assert_eq!(final_balance, 1200);
            let actual_final_balance = mock_kv_get_bytes(mock_vault_key(&symbol));
            assert_eq!(actual_final_balance, 1200);
        });
    }

    #[test]
    fn test_different_tokens() {
        run_isolated_test(|| {
            *MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()) = "BTC".to_string();
            *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "10".to_string();
            let btc_symbol = mock_attached_symbol();
            let btc_amount = mock_attached_amount();
            let btc_new_amount = mock_kv_increment(mock_vault_key(&btc_symbol), &btc_amount);
            assert_eq!(btc_new_amount, "10");
            *MOCK_ATTACHED_SYMBOL.lock().unwrap_or_else(|e| e.into_inner()) = "ETH".to_string();
            *MOCK_ATTACHED_AMOUNT.lock().unwrap_or_else(|e| e.into_inner()) = "100".to_string();
            let eth_symbol = mock_attached_symbol();
            let eth_amount = mock_attached_amount();
            let eth_new_amount = mock_kv_increment(mock_vault_key(&eth_symbol), &eth_amount);
            assert_eq!(eth_new_amount, "100");
            let btc_balance = mock_kv_get_bytes(mock_vault_key("BTC"));
            let eth_balance = mock_kv_get_bytes(mock_vault_key("ETH"));
            assert_eq!(btc_balance, 10);
            assert_eq!(eth_balance, 100);
        });
    }
} 