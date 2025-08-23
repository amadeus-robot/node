pub struct BLS12AggSig;

impl BLS12AggSig {
    pub const DST: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_";
    pub const DST_POP: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_";
    pub const DST_ATT: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_ATTESTATION_";
    pub const DST_ENTRY: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_ENTRY_";
    pub const DST_VRF: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_VRF_";
    pub const DST_TX: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_TX_";
    pub const DST_MOTION: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_MOTION_";
    pub const DST_NODE: &'static [u8] = b"AMADEUS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NODE_";
}