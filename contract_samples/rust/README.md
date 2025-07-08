# Amadeus Deposit Contract - Rust Migration

This directory contains the Rust migration of the original AssemblyScript deposit contract.

## Overview

The contract provides the following functionality:
- **Balance**: Check the balance of a specific token for the caller
- **Deposit**: Deposit tokens into the caller's vault
- **Withdraw**: Withdraw tokens from the caller's vault (with balance validation)
- **Burn**: Burn tokens by transferring them to a zero address

## Files

- `src/lib.rs` - Main library entry point
- `src/sdk.rs` - Rust SDK providing equivalent functionality to the AssemblyScript SDK
- `src/deposit.rs` - Main contract implementation
- `Cargo.toml` - Rust project configuration

## Key Changes from AssemblyScript

### Type System
- `i32` → `i32` (same in Rust)
- `u64` → `u64` (same in Rust)
- `Uint8Array` → `Vec<u8>`
- `string` → `String` or `&str`

### Memory Management
- AssemblyScript's automatic memory management → Rust's ownership system
- Manual memory management for FFI calls with proper safety checks

### Function Signatures
- AssemblyScript: `export function balance(symbol_ptr: i32): void`
- Rust: `pub extern "C" fn balance(symbol_ptr: *const u8, symbol_len: u32)`

### Error Handling
- AssemblyScript: `assert()` → Rust: `assert!()` macro
- Added proper error handling with `expect()` for parsing operations

## Building

To build the contract:

```bash
cd node/contract_samples/rust
cargo build --release --target wasm32-unknown-unknown
```

## Usage

The contract functions can be called with the following signatures:

### Balance
```rust
balance(symbol_ptr: *const u8, symbol_len: u32)
```

### Deposit
```rust
deposit()
```

### Withdraw
```rust
withdraw(symbol_ptr: *const u8, symbol_len: u32, amount_ptr: *const u8, amount_len: u32)
```

### Burn
```rust
burn(symbol_ptr: *const u8, symbol_len: u32, amount_ptr: *const u8, amount_len: u32)
```

## SDK Functions

The Rust SDK provides equivalent functionality to the AssemblyScript SDK:

- `b(s: &str) -> Vec<u8>` - Convert string to bytes
- `b58(data: &[u8]) -> String` - Base58 encoding
- `account_caller() -> Vec<u8>` - Get caller account
- `attached_symbol() -> String` - Get attached symbol
- `attached_amount() -> String` - Get attached amount
- `log(line: &str)` - Log a message
- `return_value(ret: &str)` - Return a value
- `kv_get_bytes(key: &[u8]) -> u64` - Get bytes from KV store
- `kv_increment(key: &[u8], val: &str) -> String` - Increment KV store value
- `call(contract: &[u8], func: &str, args: &[&[u8]]) -> String` - Call another contract

## Safety Features

- All unsafe operations are properly wrapped with safety checks
- Memory management follows Rust's ownership rules
- Proper error handling for parsing operations
- Null pointer checks for FFI calls 