pub struct Attestation {
    pub entry_hash: Vec<u8>,
    pub mutations_hash: Vec<u8>,
    pub signer: Vec<u8>,
    pub signature: Vec<u8>,
}