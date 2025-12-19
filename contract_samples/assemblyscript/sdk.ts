@inline
export function toBytes<T>(val: T): Uint8Array {
  if (isInteger<T>()) {
      const str = val.toString();
      return Uint8Array.wrap(String.UTF8.encode(str));
  }
  else if (idof<T>() == idof<string>()) {
    return Uint8Array.wrap(String.UTF8.encode(changetype<string>(val)));
  }
  else if (idof<T>() == idof<Uint8Array>()) {
    return changetype<Uint8Array>(val);
  }
  else {
    ERROR("toBytes only accepts String or Uint8Array");
    return new Uint8Array(0); // Unreachable but satisfies compiler
  }
}

export function bcat<T>(items: Array<T>): Uint8Array {
  const parts = new Array<Uint8Array>(items.length);
  let totalLen = 0;

  for (let i = 0; i < items.length; i++) {
    parts[i] = toBytes(items[i]);
    totalLen += parts[i].length;
  }

  const out = new Uint8Array(totalLen);
  let offset = 0;
  for (let i = 0; i < parts.length; i++) {
    out.set(parts[i], offset);
    offset += parts[i].length;
  }

  return out;
}

export function b<T>(val: T): Uint8Array {
  return toBytes(val)
}

class KeyValuePair {
  constructor(
    public key: Uint8Array | null,
    public value: Uint8Array | null
  ) {}
}

export function toHexString(bytes: Uint8Array): string {
  const hexChars = "0123456789ABCDEF";

  let tempU16 = new Array<u16>(bytes.length << 1);
  let j = 0;
  for (let i = 0; i < bytes.length; i++) {
    let b = bytes[i];
    tempU16[j++] = hexChars.charCodeAt(b >>> 4) as u16;
    tempU16[j++] = hexChars.charCodeAt(b & 0xF) as u16;
  }

  let tempI32 = new Array<i32>(tempU16.length);
  for (let k = 0; k < tempU16.length; k++) {
    tempI32[k] = tempU16[k]; // implicitly extends to i32
  }

  return String.fromCharCodes(tempI32);
}

const MAP = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
export function b58<T>(term: T): string {
  if (term instanceof Uint8Array) {
    return to_b58_1(term);
  } else {
    return to_b58_1(String.UTF8.encode(term));
  }
}

function to_b58_1(B: Uint8Array, A: string = MAP): string {
  let d = new Array<i32>();
  let s = "";

  for (let i = 0; i < B.length; i++) {
    let j = 0;
    let c: i32 = B[i];

    if (c == 0 && s.length == 0 && i != 0) s += "1";

    while (j < d.length || c != 0) {
      let n: i32 = j < d.length ? d[j] * 256 + c : c;
      c = n / 58 as i32;
      if (j < d.length) {
        d[j] = n % 58;
      } else {
        d.push(n % 58);
      }
      j++;
    }
  }

  for (let k = d.length - 1; k >= 0; k--) {
    s += A.charAt(d[k]);
  }

  return s;
}

export function b58_dec(term: string): Uint8Array | null {
  return from_b58_1(term);
}
function from_b58_1(S: string, A: string = MAP): Uint8Array | null {
  let d = new Array<i32>();
  let b = new Array<i32>();

  for (let i = 0; i < S.length; i++) {
    let j = 0;
    let c = A.indexOf(S.charAt(i));
    if (c < 0) return null;

    if (c == 0 && b.length == 0 && i != 0) b.push(0);

    while (j < d.length || c != 0) {
      let n = j < d.length ? d[j] * 58 + c : c;
      c = n >> 8;
      if (j < d.length) {
        d[j] = n & 0xff;
      } else {
        d.push(n & 0xff);
      }
      j++;
    }
  }

  for (let j = d.length - 1; j >= 0; j--) {
    b.push(d[j]);
  }

  let result = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) {
    result[i] = b[i] as u8;
  }

  return result;
}

export function memory_read_bytes(ptr: i32): Uint8Array {
  let length = load<i32>(ptr);
  let result = new Uint8Array(length);
  memory.copy(changetype<usize>(result.buffer), ptr+4, length);
  return result;
}

export function memory_read_string(ptr: i32): string {
  return String.UTF8.decodeUnsafe(ptr+4, load<i32>(ptr), false)
}

export function base58_decode(input: string): Uint8Array {
  const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
  let bytes = new Array<u8>();
  for (let i = 0; i < input.length; i++) {
    let carry = ALPHABET.indexOf(input.charAt(i));
    if (carry < 0) throw new Error("Invalid Base58 char");
    for (let j = 0; j < bytes.length; j++) {
      let x = (bytes[j] as u32) * 58 + carry;
      bytes[j] = <u8>(x & 0xff);
      carry = x >> 8;
    }
    while (carry) {
      bytes.push(<u8>(carry & 0xff));
      carry >>= 8;
    }
  }
  let zeros = 0;
  while (zeros < input.length && input.charAt(zeros) == ALPHABET[0]) zeros++;
  let out = new Uint8Array(zeros + bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[zeros + i] = bytes[bytes.length - 1 - i];
  }
  return out;
}

export function bToI64(data: Uint8Array | null, defaultVal: i64 = 0): i64 {
  if (!data) return defaultVal;
  const str = String.UTF8.decodeUnsafe(data.dataStart, data.byteLength);
  return I64.parseInt(str);
}

export function bToU64(data: Uint8Array | null, defaultVal: u64 = 0): u64 {
  if (!data) return defaultVal;
  const str = String.UTF8.decodeUnsafe(data.dataStart, data.byteLength);
  return U64.parseInt(str);
}

export function coin_raw(amount: u64, decimals: i32 = 9): Uint8Array {
  let multiplier: u64 = 1;
  for (let i = 0; i < decimals; i++) {
    multiplier *= 10;
  }
  const total = amount * multiplier;
  return Uint8Array.wrap(String.UTF8.encode(total.toString()));
}

export function exit(error: string): void {
  abort(error, "0", 0, 0);
}

// --- Seed (1100) ---
export function seed(): Uint8Array { return memory_read_bytes(1100); }

// --- Entry (2000) ---
export function entry_slot(): u64 { return load<u64>(2000); }
export function entry_height(): u64 { return load<u64>(2010); }
export function entry_epoch(): u64 { return load<u64>(2020); }
export function entry_signer(): Uint8Array { return memory_read_bytes(2100); }
export function entry_prev_hash(): Uint8Array { return memory_read_bytes(2200); }
export function entry_vr(): Uint8Array { return memory_read_bytes(2300); }
export function entry_dr(): Uint8Array { return memory_read_bytes(2400); }

// --- TX (3000) ---
export function tx_nonce(): u64 { return load<u64>(3000); }
export function tx_signer(): Uint8Array { return memory_read_bytes(3100); }

// --- Accounts (4000) ---
export function account_current(): Uint8Array { return memory_read_bytes(4000); }
export function account_caller(): Uint8Array { return memory_read_bytes(4100); }
export function account_origin(): Uint8Array { return memory_read_bytes(4200); }

// --- Assets (5000) ---
export function attached_symbol(): string { return memory_read_string(5000); }
export function attached_amount(): string { return memory_read_string(5100); }

@external("env", "import_log")
declare function import_log(ptr: i32, len: i32): void;
export function log<T>(line: T): void {
  if (!line) { return }
  const line_not_null = line;
  const bytes = toBytes<T>(line_not_null);
  import_log(changetype<i32>(bytes.dataStart), bytes.byteLength)
}

@external("env", "import_return")
declare function import_return(ptr: i32, len: i32): void;
export function ret<T>(retv: T): void {
  const retvBytes = toBytes<T>(retv);
  return import_return(changetype<i32>(retvBytes.dataStart), retvBytes.byteLength);
}

@external("env", "import_kv_put")
declare function import_kv_put(key_ptr: i32, key_len: i32, val_ptr: i32, val_len: i32): i32;
export function kv_put<K, V>(key: K, value: V): void {
  const keyBytes = toBytes<K>(key);
  const valueBytes = toBytes<V>(value);
  import_kv_put(changetype<i32>(keyBytes.dataStart), keyBytes.byteLength, changetype<i32>(valueBytes.dataStart), valueBytes.byteLength);
}

@external("env", "import_kv_increment")
declare function import_kv_increment(key_ptr: i32, key_len: i32, val_ptr: i32, val_len: i32): i32;
export function kv_increment<K, V>(key: K, value: V): string {
  const keyBytes = toBytes<K>(key);
  const valueBytes = toBytes<V>(value);
  let rptr = import_kv_increment(changetype<i32>(keyBytes.dataStart), keyBytes.byteLength, changetype<i32>(valueBytes.dataStart), valueBytes.byteLength);
  return memory_read_string(rptr);
}

@external("env", "import_kv_delete")
declare function import_kv_delete(key_ptr: i32, key_len: i32): i32;
export function kv_delete<K>(key: K): void {
  const keyBytes = toBytes<K>(key)
  import_kv_delete(changetype<i32>(keyBytes.dataStart), keyBytes.byteLength)
}

@external("env", "import_kv_exists")
declare function import_kv_exists(ptr: i32, len: i32): i32;
export function kv_exists<K>(key: K): bool {
  const keyBytes = toBytes<K>(key)
  const result = import_kv_exists(changetype<i32>(keyBytes.dataStart), keyBytes.byteLength)
  return result == 1
}

@external("env", "import_kv_get")
declare function import_kv_get(ptr: i32, len: i32): i32;
export function kv_get<K>(key: K): Uint8Array | null {
  const keyBytes = toBytes<K>(key);
  const termPtr = import_kv_get(changetype<i32>(keyBytes.dataStart), keyBytes.byteLength);
  const size = load<i32>(termPtr);

  if (size == -1) {
    return null;
  }
  return memory_read_bytes(termPtr);
}

@external("env", "import_kv_get_prev")
declare function import_kv_get_prev(prefix_ptr: i32, prefix_len: i32, key_ptr: i32, key_len: i32): i32;
export function kv_get_prev<K, V>(prefix: K, key: V): KeyValuePair {
  const prefixBytes = toBytes<K>(prefix);
  const keyBytes = toBytes<V>(key);

  const termPtr = import_kv_get_prev(changetype<i32>(prefixBytes.dataStart), prefixBytes.byteLength, changetype<i32>(keyBytes.dataStart), keyBytes.byteLength);
  const size = load<i32>(termPtr);

  if (size == -1) {
    return new KeyValuePair(null, null);
  }

  let prev_key = memory_read_bytes(termPtr);
  let value = memory_read_bytes(termPtr + 4 + size);
  return new KeyValuePair(prev_key, value);
}

@external("env", "import_kv_get_next")
declare function import_kv_get_next(prefix_ptr: i32, prefix_len: i32, key_ptr: i32, key_len: i32): i32;
export function kv_get_next<K, V>(prefix: K, key: V): KeyValuePair {
  const prefixBytes = toBytes<K>(prefix);
  const keyBytes = toBytes<V>(key);

  const termPtr = import_kv_get_next(changetype<i32>(prefixBytes.dataStart), prefixBytes.byteLength, changetype<i32>(keyBytes.dataStart), keyBytes.byteLength);
  const size = load<i32>(termPtr);

  if (size == -1) {
    return new KeyValuePair(null, null);
  }

  let prev_key = memory_read_bytes(termPtr);
  let value = memory_read_bytes(termPtr + 4 + size);
  return new KeyValuePair(prev_key, value);
}

// One import to rule them all
@external("env", "import_call")
declare function import_call(args_ptr: i32, extra_args_ptr: i32): i32;
export function call<C, F, T = Uint8Array>(contract: C, func: F, args: T[], extra_args: T[] | null = null): Uint8Array {
  const contractBytes = toBytes<C>(contract);
  const funcBytes = toBytes<F>(func);

  const pinnedArgs = new Array<Uint8Array>(2 + args.length);
  pinnedArgs[0] = contractBytes;
  pinnedArgs[1] = funcBytes;
  for (let j = 0; j < args.length; j++) { pinnedArgs[2 + j] = toBytes<T>(args[j]) }

  //    4 bytes for Count
  //    16 bytes for contract + func
  //    8 bytes * args
  const totalItems = 2 + args.length;
  const tablePtr = __alloc(4 + 16 + (8 * totalItems));
  store<i32>(tablePtr, totalItems);
  for (let i = 0; i < pinnedArgs.length; i++) {
    const arg = pinnedArgs[i];
    const offset = 4 + (i * 8);

    store<i32>(tablePtr + offset, changetype<i32>(arg.dataStart));
    store<i32>(tablePtr + offset + 4, arg.byteLength);
  }

  //Extra args
  let extraTablePtr = 0;
  if (extra_args) {
    const pinnedExtraArgs = new Array<Uint8Array>(extra_args.length);
    for (let i = 0; i < extra_args.length; i++) { pinnedExtraArgs[i] = toBytes<T>(extra_args[i]) }

    extraTablePtr = __alloc(4 + (8 * extra_args.length)) as i32;
    store<i32>(extraTablePtr, extra_args.length);

    for (let i = 0; i < extra_args.length; i++) {
      const earg = pinnedExtraArgs[i];
      const offset = 4 + (i * 8);

      store<i32>(extraTablePtr + offset, changetype<i32>(earg.dataStart));
      store<i32>(extraTablePtr + offset + 4, earg.byteLength);
    }
  }

  const errorPtr = import_call(tablePtr as i32, extraTablePtr as i32);

  // Cleanup (Optional, but good practice if you do this in a loop)
  __free(tablePtr);

  return memory_read_bytes(errorPtr);
}
