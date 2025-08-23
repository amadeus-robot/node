use crate::*;
use once_cell::sync::Lazy;
use serde::Deserialize;
use std::{net::Ipv4Addr, path::PathBuf};

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "lowercase")] // maps "default", "trainer" from TOML
pub enum ComputorType {
    Trainer,
    Default,
    None,
}

#[derive(Debug, Deserialize, Clone)]
pub struct AmaConfig {
    pub version_3b: [u8; 3],
    pub entry_size: usize,
    pub tx_size: usize,
    pub attestation_size: usize,
    pub quorum: u8,
    pub work_folder: PathBuf,
    pub offline: bool,
    pub http_ipv4: Ipv4Addr,
    pub http_port: u16,
    pub udp_ipv4_tuple: Ipv4Addr,
    pub udp_port: u16,
    pub seednodes: Vec<String>,
    pub othernodes: Vec<String>,
    pub trustfactor: f64,

    pub trainer_pk: Vec<u8>,
    pub trainer_sk: Vec<u8>,
    // Optional flags
    pub archival_node: bool,
    pub autoupdate: bool,
    pub computor_type: ComputorType,
    pub snapshot_height: u64,
}

// pub AMACONFIG : AmaConfig= CONFIG.
pub static AMACONFIG: Lazy<AmaConfig> = Lazy::new(|| CONFIG.ama.clone());