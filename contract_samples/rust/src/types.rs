use alloc::{vec::Vec, string::{String, ToString}};

#[derive(Debug, Clone)]
pub struct KeyValuePair {
    pub key: Option<Vec<u8>>,
    pub value: Option<Vec<u8>>,
}

impl KeyValuePair {
    pub fn new(key: Option<Vec<u8>>, value: Option<Vec<u8>>) -> Self {
        Self { key, value }
    }
}

pub trait ToBytes {
    fn to_bytes(&self) -> Vec<u8>;
}

impl ToBytes for Vec<u8> { fn to_bytes(&self) -> Vec<u8> { self.clone() } }
impl ToBytes for &[u8] { fn to_bytes(&self) -> Vec<u8> { self.to_vec() } }
impl ToBytes for &str { fn to_bytes(&self) -> Vec<u8> { self.as_bytes().to_vec() } }
impl ToBytes for String { fn to_bytes(&self) -> Vec<u8> { self.as_bytes().to_vec() } }
impl ToBytes for u64 { fn to_bytes(&self) -> Vec<u8> { self.to_string().as_bytes().to_vec() } }
impl ToBytes for i64 { fn to_bytes(&self) -> Vec<u8> { self.to_string().as_bytes().to_vec() } }
impl ToBytes for u32 { fn to_bytes(&self) -> Vec<u8> { self.to_string().as_bytes().to_vec() } }
impl ToBytes for i32 { fn to_bytes(&self) -> Vec<u8> { self.to_string().as_bytes().to_vec() } }
impl ToBytes for bool { fn to_bytes(&self) -> Vec<u8> { (if *self { &b"true"[..] } else { &b"false"[..] }).to_vec() } }
