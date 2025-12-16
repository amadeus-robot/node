use alloc::{vec::Vec, string::String};
use crate::types::{ToBytes, KeyValuePair};

extern "C" {
    fn import_kv_put(kp: i32, kl: i32, vp: i32, vl: i32) -> i32;
    fn import_kv_get(p: i32, l: i32) -> i32;
    fn import_kv_increment(kp: i32, kl: i32, vp: i32, vl: i32) -> i32;
    fn import_kv_delete(p: i32, l: i32) -> i32;
    fn import_kv_exists(p: i32, l: i32) -> i32;
    fn import_kv_get_prev(pp: i32, pl: i32, kp: i32, kl: i32) -> i32;
    fn import_kv_get_next(pp: i32, pl: i32, kp: i32, kl: i32) -> i32;
}

fn read_bytes(p: i32) -> Vec<u8> {
    unsafe {
        let len = *(p as *const i32);
        if len == -1 { return Vec::new(); }
        let data = (p + 4) as *const u8;
        core::slice::from_raw_parts(data, len as usize).to_vec()
    }
}

fn read_string(p: i32) -> String {
    String::from_utf8(read_bytes(p)).unwrap_or_default()
}

const BUF1: i32 = 9000;
const BUF2: i32 = 9500;

fn write_bufs(k: &[u8], v: &[u8]) -> (i32, i32, i32, i32) {
    unsafe {
        for (i, &b) in k.iter().enumerate() { *((BUF1 as *mut u8).add(i)) = b; }
        for (i, &b) in v.iter().enumerate() { *((BUF2 as *mut u8).add(i)) = b; }
        (BUF1, k.len() as i32, BUF2, v.len() as i32)
    }
}

pub fn kv_put<K: ToBytes, V: ToBytes>(k: K, v: V) {
    let kb = k.to_bytes();
    let vb = v.to_bytes();
    let (kp, kl, vp, vl) = write_bufs(&kb, &vb);
    unsafe { import_kv_put(kp, kl, vp, vl); }
}

pub fn kv_get<K: ToBytes>(k: K) -> Option<Vec<u8>> {
    let kb = k.to_bytes();
    unsafe {
        for (i, &b) in kb.iter().enumerate() { *((BUF1 as *mut u8).add(i)) = b; }
        let p = import_kv_get(BUF1, kb.len() as i32);
        if *(p as *const i32) == -1 { None } else { Some(read_bytes(p)) }
    }
}

pub fn kv_increment<K: ToBytes, V: ToBytes>(k: K, d: V) -> String {
    let kb = k.to_bytes();
    let vb = d.to_bytes();
    let (kp, kl, vp, vl) = write_bufs(&kb, &vb);
    unsafe { read_string(import_kv_increment(kp, kl, vp, vl)) }
}

pub fn kv_delete<K: ToBytes>(k: K) {
    let kb = k.to_bytes();
    unsafe {
        for (i, &b) in kb.iter().enumerate() { *((BUF1 as *mut u8).add(i)) = b; }
        import_kv_delete(BUF1, kb.len() as i32);
    }
}

pub fn kv_exists<K: ToBytes>(k: K) -> bool {
    let kb = k.to_bytes();
    unsafe {
        for (i, &b) in kb.iter().enumerate() { *((BUF1 as *mut u8).add(i)) = b; }
        import_kv_exists(BUF1, kb.len() as i32) == 1
    }
}

pub fn kv_get_prev<K: ToBytes, V: ToBytes>(p: K, k: V) -> KeyValuePair {
    let pb = p.to_bytes();
    let kb = k.to_bytes();
    let (pp, pl, kp, kl) = write_bufs(&pb, &kb);
    unsafe {
        let r = import_kv_get_prev(pp, pl, kp, kl);
        let len = *(r as *const i32);
        if len == -1 { KeyValuePair::new(None, None) }
        else { KeyValuePair::new(Some(read_bytes(r)), Some(read_bytes(r + 4 + len))) }
    }
}

pub fn kv_get_next<K: ToBytes, V: ToBytes>(p: K, k: V) -> KeyValuePair {
    let pb = p.to_bytes();
    let kb = k.to_bytes();
    let (pp, pl, kp, kl) = write_bufs(&pb, &kb);
    unsafe {
        let r = import_kv_get_next(pp, pl, kp, kl);
        let len = *(r as *const i32);
        if len == -1 { KeyValuePair::new(None, None) }
        else { KeyValuePair::new(Some(read_bytes(r)), Some(read_bytes(r + 4 + len))) }
    }
}
