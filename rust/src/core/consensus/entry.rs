use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EntryHeader {
    pub slot: u64,
    pub height: u64,
    pub prev_slot: i64,
    pub prev_hash: Vec<u8>,
    pub signer: Vec<u8>,
    pub dr: Vec<u8>,
    pub vr: Vec<u8>,
    pub txs_hash: Vec<u8>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub signature: Vec<u8>,
    pub hash: Vec<u8>,
    pub header_unpacked: EntryHeader,
    pub txs: Vec<Vec<u8>>,
    pub mask: Option<Vec<u8>>, // optional mask
}