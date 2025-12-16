use alloc::{vec::Vec, string::{String, ToString}};

const B58: &[u8] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

pub fn b58_encode(input: &[u8]) -> String {
    let mut d = Vec::new();
    let mut r = String::new();
    for &byte in input {
        let mut carry = byte as u32;
        let mut j = 0;
        if carry == 0 && r.is_empty() && byte != input[0] { r.push('1'); }
        while j < d.len() || carry != 0 {
            let n = if j < d.len() { d[j] as u32 * 256 + carry } else { carry };
            carry = n / 58;
            if j < d.len() { d[j] = (n % 58) as u8; } else { d.push((n % 58) as u8); }
            j += 1;
        }
    }
    for i in (0..d.len()).rev() { r.push(B58[d[i] as usize] as char); }
    r
}

pub fn b58_decode(input: &str) -> Option<Vec<u8>> {
    let mut d = Vec::new();
    let mut b = Vec::new();
    for c in input.chars() {
        let pos = B58.iter().position(|&x| x == c as u8)?;
        let mut carry = pos;
        let mut j = 0;
        if carry == 0 && b.is_empty() && c != input.chars().next()? { b.push(0); }
        while j < d.len() || carry != 0 {
            let n = if j < d.len() { d[j] * 58 + carry } else { carry };
            carry = n >> 8;
            if j < d.len() { d[j] = n & 0xff; } else { d.push(n & 0xff); }
            j += 1;
        }
    }
    for i in (0..d.len()).rev() { b.push(d[i] as u8); }
    Some(b)
}

pub fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8] = b"0123456789ABCDEF";
    let mut r = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        r.push(HEX[(b >> 4) as usize] as char);
        r.push(HEX[(b & 0xF) as usize] as char);
    }
    r
}

pub fn bcat(items: &[&[u8]]) -> Vec<u8> {
    let mut r = Vec::with_capacity(items.iter().map(|i| i.len()).sum());
    for i in items { r.extend_from_slice(i); }
    r
}

pub fn bytes_to_i64(data: Option<&[u8]>, default: i64) -> i64 {
    data.and_then(|b| core::str::from_utf8(b).ok())
        .and_then(|s| parse_i64(s))
        .unwrap_or(default)
}

pub fn bytes_to_u64(data: Option<&[u8]>, default: u64) -> u64 {
    data.and_then(|b| core::str::from_utf8(b).ok())
        .and_then(|s| parse_u64(s))
        .unwrap_or(default)
}

fn parse_i64(s: &str) -> Option<i64> {
    let (neg, s) = if s.starts_with('-') { (true, &s[1..]) } else { (false, s) };
    let mut r = 0i64;
    for c in s.chars() {
        if !c.is_ascii_digit() { return None; }
        r = r * 10 + (c as i64 - '0' as i64);
    }
    Some(if neg { -r } else { r })
}

fn parse_u64(s: &str) -> Option<u64> {
    let mut r = 0u64;
    for c in s.chars() {
        if !c.is_ascii_digit() { return None; }
        r = r * 10 + (c as u64 - '0' as u64);
    }
    Some(r)
}

pub fn coin_raw(amount: u64, decimals: u32) -> Vec<u8> {
    let mut m = 1u64;
    for _ in 0..decimals { m *= 10; }
    (amount * m).to_string().as_bytes().to_vec()
}
