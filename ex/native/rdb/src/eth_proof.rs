use reqwest::blocking::Client;
use serde_json::json;
use tiny_keccak::{Keccak, Hasher};
use hex;

pub fn keccak256(input: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    hasher.update(input);
    let mut output = [0u8; 32];
    hasher.finalize(&mut output);
    output
}

/// Compute slot for: mapping(address => mapping(address => uint256)) locked;
///
/// slot = keccak256(abi.encode(user, keccak256(abi.encode(token, mapping_slot))))
pub fn compute_double_mapping_slot(
    token: &str,
    user: &str,
    mapping_slot: u64
) -> Result<String, Box<dyn std::error::Error>> {
    // --- Decode token address ---
    let token_clean = token.trim_start_matches("0x");
    let token_bytes = hex::decode(token_clean)?;
    if token_bytes.len() != 20 {
        return Err("Token address must be 20 bytes".into());
    }
    // pad token to 32 bytes
    let mut token_padded = [0u8; 32];
    token_padded[12..32].copy_from_slice(&token_bytes);

    // --- Encode slot (uint256) ---
    let mut slot_bytes = [0u8; 32];
    slot_bytes[24..32].copy_from_slice(&mapping_slot.to_be_bytes());

    // inner = keccak256(token || slot)
    let mut inner_preimage = [0u8; 64];
    inner_preimage[..32].copy_from_slice(&token_padded);
    inner_preimage[32..64].copy_from_slice(&slot_bytes);
    let inner_hash = keccak256(&inner_preimage);

    // --- Decode user address ---
    let user_clean = user.trim_start_matches("0x");
    let user_bytes = hex::decode(user_clean)?;
    if user_bytes.len() != 20 {
        return Err("User address must be 20 bytes".into());
    }
    let mut user_padded = [0u8; 32];
    user_padded[12..32].copy_from_slice(&user_bytes);

    // final = keccak256(user_padded || inner_hash)
    let mut final_preimage = [0u8; 64];
    final_preimage[..32].copy_from_slice(&user_padded);
    final_preimage[32..64].copy_from_slice(&inner_hash);
    let slot_final = keccak256(&final_preimage);

    Ok(format!("0x{}", hex::encode(slot_final)))
}

pub fn get_eth_proof(
    api_key: &str,
    contract_addr: &str,
    token_addr: &str,
    user_addr: &str,
    mapping_slot: u64
) -> Result<String, Box<dyn std::error::Error>> {
    let url = format!("https://eth-mainnet.g.alchemy.com/v2/{}", api_key);

    // Compute double mapping slot
    let slot = compute_double_mapping_slot(token_addr, user_addr, mapping_slot)?;

    // Prepare RPC request
    let request = json!({
        "jsonrpc": "2.0",
        "method": "eth_getProof",
        "params": [
            contract_addr,
            [slot],
            "latest"
        ],
        "id": 1
    });

    // Send request
    let client = Client::new();
    let response = client.post(url).json(&request).send()?.text()?;

    Ok(response)
}

