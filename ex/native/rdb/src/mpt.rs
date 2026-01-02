use hex::{decode, encode};
use keccak_hasher::KeccakHasher;
use primitive_types::H256;
use rlp::{Rlp, RlpStream};
use trie_db::Hasher;

/// RLP encodes a number (similar to TypeScript's RLP.encode(number))
pub fn rlp_encode_number(n: u64) -> Vec<u8> {
    if n == 0 {
        // RLP encoding of 0 is 0x80
        vec![0x80]
    } else {
        let mut stream = RlpStream::new();
        stream.append(&n);
        stream.out().to_vec()
    }
}

/// Convert bytes to nibbles (hex characters)
fn bytes_to_nibbles(bytes: &[u8]) -> Vec<u8> {
    let mut nibbles = Vec::with_capacity(bytes.len() * 2);
    for byte in bytes {
        nibbles.push(byte >> 4);
        nibbles.push(byte & 0x0f);
    }
    nibbles
}

/// Decode hex-prefix encoding used in Ethereum MPT
/// Returns (nibbles, is_leaf)
fn decode_hex_prefix(encoded: &[u8]) -> (Vec<u8>, bool) {
    if encoded.is_empty() {
        return (vec![], false);
    }

    let first = encoded[0];
    let is_leaf = (first >> 4) >= 2;
    let is_odd = (first >> 4) % 2 == 1;

    let mut nibbles = Vec::new();
    if is_odd {
        nibbles.push(first & 0x0f);
    }

    for byte in &encoded[1..] {
        nibbles.push(byte >> 4);
        nibbles.push(byte & 0x0f);
    }

    (nibbles, is_leaf)
}

/// Verifies an Ethereum Merkle Patricia Trie proof
///
/// # Arguments
/// * `root` - The root hash of the trie (32 bytes)
/// * `key` - The RLP-encoded key to look up
/// * `proof` - Array of proof nodes (RLP-encoded)
///
/// # Returns
/// * `Ok(value)` - Proof is valid and value was found
/// * `Err(_)` - Proof is invalid
pub fn verify_proof(
    root: &[u8],
    key: &[u8],
    proof: &[Vec<u8>],
) -> Result<Vec<u8>, String> {
    if root.len() != 32 {
        return Err(format!("Root must be 32 bytes, got {}", root.len()));
    }

    let root_hash = H256::from_slice(root);

    if proof.is_empty() {
        return Err("Proof is empty".to_string());
    }

    // Convert key to nibbles
    let key_nibbles = bytes_to_nibbles(key);
    let mut key_index = 0;

    // Expected hash starts with root
    let mut expected_hash = root_hash.as_bytes().to_vec();

    for (i, node) in proof.iter().enumerate() {
        // Verify node hash matches expected
        let node_hash = KeccakHasher::hash(node);
        if node_hash.as_ref() != expected_hash.as_slice() {
            // For inline nodes (< 32 bytes), the node itself might be the "hash"
            if node.len() < 32 && node == &expected_hash {
                // Inline node, continue
            } else {
                return Err(format!(
                    "Hash mismatch at node {}: expected 0x{}, got 0x{}",
                    i,
                    encode(&expected_hash),
                    encode(node_hash.as_ref())
                ));
            }
        }

        let rlp = Rlp::new(node);
        let item_count = rlp.item_count().map_err(|e| format!("RLP decode error at node {}: {}", i, e))?;

        match item_count {
            2 => {
                // Extension or Leaf node
                let path: Vec<u8> = rlp.at(0)
                    .map_err(|e| format!("Failed to get path at node {}: {}", i, e))?
                    .as_val()
                    .map_err(|e| format!("Failed to decode path at node {}: {}", i, e))?;
                let (nibbles, is_leaf) = decode_hex_prefix(&path);

                // Verify path matches our key
                for nibble in &nibbles {
                    if key_index >= key_nibbles.len() {
                        return Err(format!("Key too short for path at node {}", i));
                    }
                    if *nibble != key_nibbles[key_index] {
                        return Err(format!(
                            "Path mismatch at node {}, nibble {}: expected {}, got {}",
                            i,
                            key_index,
                            key_nibbles[key_index],
                            nibble
                        ));
                    }
                    key_index += 1;
                }

                if is_leaf {
                    // Leaf node - we should be at the end of our key
                    if key_index != key_nibbles.len() {
                        return Err(format!(
                            "Key not fully consumed at leaf node: {} remaining nibbles",
                            key_nibbles.len() - key_index
                        ));
                    }
                    // Return the value
                    let value: Vec<u8> = rlp.at(1)
                        .map_err(|e| format!("Failed to get value at node {}: {}", i, e))?
                        .as_val()
                        .map_err(|e| format!("Failed to decode value at node {}: {}", i, e))?;
                    return Ok(value);
                } else {
                    // Extension node - follow the next hash
                    let next = rlp.at(1)
                        .map_err(|e| format!("Failed to get next at node {}: {}", i, e))?;
                    if next.is_data() && next.size() == 32 {
                        expected_hash = next.as_val()
                            .map_err(|e| format!("Failed to decode next hash at node {}: {}", i, e))?;
                    } else if next.is_list() {
                        // Inline node
                        expected_hash = next.as_raw().to_vec();
                    } else {
                        expected_hash = next.as_val()
                            .map_err(|e| format!("Failed to decode next at node {}: {}", i, e))?;
                    }
                }
            }
            17 => {
                // Branch node
                if key_index >= key_nibbles.len() {
                    // We've consumed all key nibbles, value is in position 16
                    let value_rlp = rlp.at(16)
                        .map_err(|e| format!("Failed to get value at branch node {}: {}", i, e))?;
                    if value_rlp.is_empty() {
                        return Err(format!("No value at branch node terminus at node {}", i));
                    }
                    let value: Vec<u8> = value_rlp.as_val()
                        .map_err(|e| format!("Failed to decode value at branch node {}: {}", i, e))?;
                    return Ok(value);
                }

                let nibble = key_nibbles[key_index] as usize;
                key_index += 1;

                let next = rlp.at(nibble)
                    .map_err(|e| format!("Failed to get branch at nibble {} in node {}: {}", nibble, i, e))?;
                if next.is_empty() {
                    return Err(format!("Empty branch at nibble {} in node {}", nibble, i));
                }

                if next.is_data() && next.size() == 32 {
                    expected_hash = next.as_val()
                        .map_err(|e| format!("Failed to decode branch hash at node {}: {}", i, e))?;
                } else if next.is_list() || (next.is_data() && next.size() < 32) {
                    // Inline node - the data itself is the next node
                    expected_hash = next.as_raw().to_vec();
                } else {
                    expected_hash = next.as_val()
                        .map_err(|e| format!("Failed to decode branch at node {}: {}", i, e))?;
                }
            }
            _ => {
                return Err(format!("Invalid node with {} items at position {}", item_count, i));
            }
        }
    }

    Err("Proof ended without finding value".to_string())
}
