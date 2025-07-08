use std::collections::HashMap;
use std::sync::Mutex;
use lazy_static::lazy_static;

// Shared test utilities
lazy_static! {
    pub static ref TEST_STORAGE: Mutex<HashMap<String, u64>> = Mutex::new(HashMap::new());
    pub static ref TEST_LOGS: Mutex<Vec<String>> = Mutex::new(Vec::new());
    pub static ref TEST_RETURN_VALUES: Mutex<Vec<String>> = Mutex::new(Vec::new());
    pub static ref TEST_CALL_RESULTS: Mutex<Vec<String>> = Mutex::new(Vec::new());
}

pub fn setup_test_environment() {
    TEST_STORAGE.lock().unwrap().clear();
    TEST_LOGS.lock().unwrap().clear();
    TEST_RETURN_VALUES.lock().unwrap().clear();
    TEST_CALL_RESULTS.lock().unwrap().clear();
}

pub fn get_test_logs() -> Vec<String> {
    TEST_LOGS.lock().unwrap().clone()
}

pub fn get_test_return_values() -> Vec<String> {
    TEST_RETURN_VALUES.lock().unwrap().clone()
}

pub fn get_test_storage() -> HashMap<String, u64> {
    TEST_STORAGE.lock().unwrap().clone()
}

pub fn set_test_storage_value(key: &str, value: u64) {
    TEST_STORAGE.lock().unwrap().insert(key.to_string(), value);
}

pub fn get_test_storage_value(key: &str) -> u64 {
    TEST_STORAGE.lock().unwrap().get(key).copied().unwrap_or(0)
}

// Mock implementations for testing
pub fn mock_b58(data: &[u8]) -> String {
    format!("mock_b58_{}", hex::encode(data))
}

pub fn mock_vault_key(symbol: &str, account: &[u8]) -> String {
    format!("vault:{}:{}", mock_b58(account), symbol)
}

pub fn mock_kv_increment(key: &str, value: &str) -> String {
    let current = get_test_storage_value(key);
    let increment: i64 = value.parse().unwrap_or(0);
    let new_value = if increment >= 0 {
        current + increment as u64
    } else {
        current.saturating_sub((-increment) as u64)
    };
    
    set_test_storage_value(key, new_value);
    new_value.to_string()
}

pub fn mock_kv_get_bytes(key: &str) -> u64 {
    get_test_storage_value(key)
}

pub fn mock_call(contract: &str, func: &str, args_count: usize) -> String {
    let result = format!("mock_call_{}_{}_{}", contract, func, args_count);
    TEST_CALL_RESULTS.lock().unwrap().push(result.clone());
    result
}

// Test data generators
pub fn generate_test_account() -> Vec<u8> {
    vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
}

pub fn generate_test_symbols() -> Vec<&'static str> {
    vec!["BTC", "ETH", "USDT", "ADA", "DOT", "LINK", "LTC", "BCH"]
}

pub fn generate_test_amounts() -> Vec<&'static str> {
    vec!["0", "1", "100", "1000", "10000", "100000", "1000000"]
}

// Assertion helpers
pub fn assert_balance_equals(symbol: &str, expected: u64, account: &[u8]) {
    let key = mock_vault_key(symbol, account);
    let actual = get_test_storage_value(&key);
    assert_eq!(actual, expected, "Balance for {} should be {}, got {}", symbol, expected, actual);
}

pub fn assert_log_contains(expected: &str) {
    let logs = get_test_logs();
    assert!(
        logs.iter().any(|log| log.contains(expected)),
        "Expected log to contain '{}', but logs were: {:?}",
        expected,
        logs
    );
}

pub fn assert_return_value_contains(expected: &str) {
    let return_values = get_test_return_values();
    assert!(
        return_values.iter().any(|val| val.contains(expected)),
        "Expected return value to contain '{}', but return values were: {:?}",
        expected,
        return_values
    );
}

// Performance testing utilities
pub fn benchmark_operation<F>(name: &str, iterations: usize, operation: F)
where
    F: Fn(),
{
    use std::time::Instant;
    
    let start = Instant::now();
    for _ in 0..iterations {
        operation();
    }
    let duration = start.elapsed();
    
    println!(
        "Benchmark {}: {} operations in {:?} ({:?} per operation)",
        name,
        iterations,
        duration,
        duration / iterations as u32
    );
}

// Stress testing utilities
pub fn stress_test_operations<F>(operation: F, max_concurrent: usize, total_operations: usize)
where
    F: Fn() + Send + Sync + 'static,
{
    use std::sync::Arc;
    use std::thread;
    
    let operation = Arc::new(operation);
    let mut handles = vec![];
    
    for _ in 0..max_concurrent {
        let op = Arc::clone(&operation);
        let handle = thread::spawn(move || {
            for _ in 0..(total_operations / max_concurrent) {
                op();
            }
        });
        handles.push(handle);
    }
    
    for handle in handles {
        handle.join().unwrap();
    }
} 