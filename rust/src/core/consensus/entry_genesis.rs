use blake3::Hasher;
use blst::{
    BLS12_381_G1,
    min_pk::{SecretKey, Signature},
};
use std::sync::OnceLock;

use crate::*;

pub struct EntryGenesis {
    pub signer: Vec<u8>,
    pub pop: Vec<u8>,
    pub attestation: Attestation,
    pub genesis_entry: Entry,
}

static CONFIG: OnceLock<Config> = OnceLock::new();

pub struct Config {
    pub trainer_pk: Vec<u8>,
    pub trainer_sk: Vec<u8>,
}

impl EntryGenesis {
    pub fn signer() -> Vec<u8> {
        let signer = vec![
            140, 27, 75, 245, 48, 112, 140, 244, 78, 114, 11, 45, 8, 201, 199, 184, 71, 69, 96,
            112, 52, 204, 31, 56, 143, 115, 222, 87, 7, 185, 3, 168, 252, 90, 91, 114, 16, 244, 47,
            228, 198, 82, 12, 130, 10, 126, 118, 193,
        ];

        signer
    }

    pub fn pop() -> Vec<u8> {
        let pop = vec![
            175, 176, 86, 129, 118, 228, 182, 86, 225, 187, 236, 131, 170, 81, 121, 174, 164, 44,
            71, 123, 136, 151, 170, 187, 43, 43, 211, 181, 163, 103, 93, 122, 11, 207, 92, 1, 190,
            71, 46, 129, 210, 134, 62, 169, 152, 161, 189, 58, 18, 246, 6, 151, 128, 196, 116, 93,
            20, 204, 153, 217, 81, 205, 1, 133, 65, 204, 177, 138, 74, 8, 104, 109, 214, 59, 245,
            51, 47, 218, 15, 207, 190, 73, 40, 128, 108, 147, 250, 88, 241, 61, 129, 47, 189, 173,
            118, 76,
        ];

        pop
    }

    pub fn attestation() -> Attestation {
        let attestation = Attestation {
            signature: vec![
                151, 160, 206, 230, 190, 143, 68, 181, 248, 53, 105, 176, 56, 44, 82, 68, 252, 20,
                61, 83, 33, 137, 74, 216, 149, 11, 242, 157, 237, 53, 139, 120, 202, 52, 30, 65, 9,
                155, 243, 52, 53, 41, 236, 86, 235, 128, 52, 74, 12, 80, 187, 82, 174, 138, 121,
                69, 159, 251, 97, 201, 238, 119, 163, 203, 122, 207, 179, 5, 178, 32, 145, 32, 183,
                62, 184, 189, 136, 134, 80, 7, 193, 218, 133, 171, 154, 215, 219, 77, 33, 161, 152,
                129, 142, 35, 9, 183,
            ], // fill with actual bytes
            mutations_hash: vec![
                72, 67, 216, 106, 224, 102, 200, 77, 84, 86, 71, 38, 221, 89, 178, 87, 170, 13,
                141, 117, 29, 103, 251, 177, 92, 143, 88, 218, 21, 177, 139, 196,
            ],
            signer: Self::signer(),
            entry_hash: vec![
                250, 154, 199, 170, 114, 250, 155, 84, 2, 215, 37, 236, 138, 98, 19, 87, 19, 163,
                21, 138, 131, 205, 205, 189, 176, 217, 5, 112, 225, 13, 15, 217,
            ],
        };

        attestation
    }

    pub fn get() -> Entry {
        let genesis_entry = Entry {
            header_unpacked: EntryHeader {
                slot: 0,
                height: 0,
                prev_slot: -1,
                prev_hash: vec![],
                signer: vec![
                    140, 27, 75, 245, 48, 112, 140, 244, 78, 114, 11, 45, 8, 201, 199, 184, 71, 69,
                    96, 112, 52, 204, 31, 56, 143, 115, 222, 87, 7, 185, 3, 168, 252, 90, 91, 114,
                    16, 244, 47, 228, 198, 82, 12, 130, 10, 126, 118, 193,
                ],
                dr: vec![
                    85, 13, 37, 23, 114, 150, 131, 140, 136, 174, 76, 72, 122, 45, 180, 165, 94,
                    229, 194, 27, 2, 87, 249, 159, 121, 177, 233, 167, 179, 0, 217, 219,
                ],
                vr: vec![
                    181, 221, 57, 62, 159, 101, 228, 75, 242, 59, 58, 92, 179, 234, 71, 120, 2,
                    232, 181, 156, 102, 142, 148, 152, 180, 116, 198, 158, 94, 152, 24, 27, 115,
                    224, 103, 169, 12, 237, 98, 44, 113, 237, 198, 210, 218, 83, 162, 181, 5, 65,
                    253, 232, 57, 140, 196, 121, 187, 108, 46, 68, 159, 45, 220, 62, 254, 201, 44,
                    135, 201, 126, 206, 74, 140, 239, 177, 95, 169, 40, 181, 104, 167, 84, 50, 207,
                    85, 35, 42, 10, 36, 196, 9, 13, 156, 79, 186, 117,
                ],
                txs_hash: vec![
                    175, 19, 73, 185, 245, 249, 161, 166, 160, 64, 77, 234, 54, 220, 201, 73, 155,
                    203, 37, 201, 173, 193, 18, 183, 204, 154, 147, 202, 228, 31, 50, 98,
                ],
            },
            hash: vec![
                250, 154, 199, 170, 114, 250, 155, 84, 2, 215, 37, 236, 138, 98, 19, 87, 19, 163,
                21, 138, 131, 205, 205, 189, 176, 217, 5, 112, 225, 13, 15, 217,
            ],
            mask: None,
            signature: vec![
                151, 160, 206, 230, 190, 143, 68, 181, 248, 53, 105, 176, 56, 44, 82, 68, 252, 20,
                61, 83, 33, 137, 74, 216, 149, 11, 242, 157, 237, 53, 139, 120, 202, 52, 30, 65, 9,
                155, 243, 52, 53, 41, 236, 86, 235, 128, 52, 74, 12, 80, 187, 82, 174, 138, 121,
                69, 159, 251, 97, 201, 238, 119, 163, 203, 122, 207, 179, 5, 178, 32, 145, 32, 183,
                62, 184, 189, 136, 134, 80, 7, 193, 218, 133, 171, 154, 215, 219, 77, 33, 161, 152,
                129, 142, 35, 9, 183,
            ],
            txs: vec![],
        };

        genesis_entry
    }

    pub fn generate() {
        let trainer_pk = &AMACONFIG.trainer_pk;
        let trainer_sk = &AMACONFIG.trainer_sk;

        pub const ENTROPY_SEED: &'static [u8; 117] = b"\
January 27, 2025

Tech stocks tank as a Chinese competitor threatens to upend the AI frenzy; Nvidia sinks nearly 17%
";

        let mut hasher = Hasher::new();
        hasher.update(ENTROPY_SEED);

        let dr = hasher.finalize().as_bytes().to_vec();

        let mut dr_concat = Vec::with_capacity(dr.len() * 3);
        dr_concat.extend_from_slice(&dr);
        dr_concat.extend_from_slice(&dr);
        dr_concat.extend_from_slice(&dr);

        let vr = BlsRs::sign(trainer_sk, &dr_concat, BLS12AggSig::DST_VRF).unwrap();

        let entry = Entry {
            header_unpacked: EntryHeader {
                slot: 0,
                height: 0,
                prev_slot: -1,
                prev_hash: vec![],
                dr: dr.clone(),
                vr: vr.clone(),
                signer: trainer_sk.clone(),
                txs_hash: vec![],
            },
            txs: vec![],
            hash: vec![],
            signature: vec![],
            mask: None,
        };
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::OnceLock;

    #[test]
    fn test_signer_with_log() {
        let signer = EntryGenesis::signer();
        println!("Signer: {:?}", signer);
        assert_eq!(signer.len(), 48);
    }

    #[test]
    fn test_pop_with_log() {
        let pop = EntryGenesis::pop();
        println!("PoP: {:?}", pop);
        assert_eq!(pop.len(), 96);
    }

    #[test]
    fn test_attestation_with_log() {
        let att = EntryGenesis::attestation();
        println!("Attestation signature: {:?}", att.signature);
        println!("Attestation signer: {:?}", att.signer);
        println!("Attestation entry_hash: {:?}", att.entry_hash);
        println!("Attestation mutations_hash: {:?}", att.mutations_hash);

        assert_eq!(att.signature.len(), 96);
        assert_eq!(att.signer, EntryGenesis::signer());
        assert_eq!(att.entry_hash.len(), 32);
    }

    #[test]
    fn test_get_genesis_entry_with_log() {
        let entry = EntryGenesis::get();
        println!("Genesis Entry Header: {:?}", entry.header_unpacked);
        println!("Genesis Entry txs: {:?}", entry.txs);
        println!("Genesis Entry signature: {:?}", entry.signature);

        assert_eq!(entry.header_unpacked.slot, 0);
        assert_eq!(entry.header_unpacked.height, 0);
        assert_eq!(entry.header_unpacked.prev_slot, -1);
    }

    #[test]
    fn test_generate_with_log() {
        println!("Calling EntryGenesis::generate()...");
        EntryGenesis::generate();
        println!("Generate finished (placeholder).");
    }
}
