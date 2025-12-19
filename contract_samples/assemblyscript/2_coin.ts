import * as sdk from "./sdk";
import { b, bcat, b58 } from "./sdk";

export function init(): void {
  //Mint 1b USDFAKE to this account with 9 decimals
  //Mintable = false, pausable = false, soulbound = false
  sdk.call("Coin", "create_and_mint", [b("USDFAKE"), sdk.coin_raw(1_000_000_000), b("9"), b("false"), b("false"), b("false")])
}

export function deposit(): void {
  let symbol = sdk.attached_symbol()
  let amount = sdk.attached_amount()
  sdk.log(`deposit ${symbol} ${amount}`)

  let new_amount = sdk.kv_increment(userVaultKey(symbol), amount);
  sdk.ret(new_amount);
}

export function withdraw(symbol_ptr: i32, amount_ptr: i32): void {
  let symbol = sdk.memory_read_string(symbol_ptr);
  let amount = sdk.memory_read_string(amount_ptr);
  sdk.log(`withdraw ${symbol} ${amount}`)

  let amount_int = parseInt(amount, 10) as u64
  let user_balance = sdk.bToU64(sdk.kv_get(userVaultKey(symbol)))

  assert(amount_int > 0, "amount lte 0")
  assert(user_balance >= amount_int, "insufficent funds")

  sdk.kv_increment(userVaultKey(symbol), -amount_int);
  sdk.call("Coin", "transfer", [sdk.account_caller(), b(amount), b(symbol)])

  sdk.ret(`${user_balance - amount_int}`);
}

function userVaultKey(symbol: string): Uint8Array {
  return bcat([b("vault:"), sdk.account_caller(), b(`:${symbol}`)])
}
