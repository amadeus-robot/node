use bls12_381::*;
use blst::BLST_ERROR;
use blst::min_pk::{PublicKey, SecretKey, Signature}; // from blst
use group::Curve;

use crate::*;

pub struct BlsRs {}

impl BlsRs {
    pub fn get_public_key(seed: &[u8]) -> Result<Vec<u8>, CryptoError> {
        let sk = Self::parse_secret_key(seed)?;
        let g1 = G1Projective::generator() * sk;
        let g1_bytes = g1.to_affine().to_compressed().to_vec();
        Ok(g1_bytes)
    }

    fn sign_from_scalar(scalar: Scalar, msg: &[u8], dst: &[u8]) -> Result<Signature, CryptoError> {
        let mut sk_be = scalar.to_bytes();
        sk_be.reverse();

        let sk = SecretKey::from_bytes(&sk_be).map_err(|_| CryptoError::InvalidSeed)?;
        Ok(sk.sign(msg, dst, &[]))
    }

    pub fn sign(seed: &[u8], message: &[u8], dst: &[u8]) -> Result<Vec<u8>, CryptoError> {
        println!("Seed: {:?}", seed);
        println!("Message: {:?}", message);
        println!("DST: {:?}", dst);
        let sk = Self::parse_secret_key(seed)?;
        println!("Scalar: {:?}", sk);
        let sig = Self::sign_from_scalar(sk, message, dst)?;
        println!("Signature: {:?}", sig);
        Ok(sig.to_bytes().to_vec())
    }

    pub fn verify_signature(
        pk_bytes: &[u8],
        sig_bytes: &[u8],
        msg: &[u8],
        dst: &[u8],
    ) -> Result<(), CryptoError> {
        let pk = PublicKey::deserialize(pk_bytes).map_err(|_| CryptoError::InvalidPoint)?;
        let sig = Signature::deserialize(sig_bytes).map_err(|_| CryptoError::InvalidSignature)?;

        let err = sig.verify(
            true, // hash_to_curve
            msg,
            dst,
            &[],
            &pk,
            true, // validate pk ∈ G1
        );

        if err == BLST_ERROR::BLST_SUCCESS {
            Ok(())
        } else {
            Err(CryptoError::VerificationFailed)
        }
    }

    pub fn aggregate_public_keys(public_keys: Vec<Vec<u8>>) -> Result<Vec<u8>, CryptoError> {
        if public_keys.is_empty() {
            return Err(CryptoError::ZeroSizedInput);
        }

        let parsed_pks: Vec<G1Projective> = public_keys
            .iter()
            .map(|pk| Self::parse_public_key(pk))
            .collect::<Result<_, _>>()?;

        let sum = parsed_pks
            .into_iter()
            .reduce(|acc, next| acc + next)
            .unwrap_or_default();
        Ok(sum.to_affine().to_compressed().to_vec())
    }

    pub fn aggregate_signatures(signatures: Vec<Vec<u8>>) -> Result<Vec<u8>, CryptoError> {
        if signatures.is_empty() {
            return Err(CryptoError::ZeroSizedInput);
        }

        let parsed_sigs: Vec<G2Projective> = signatures
            .iter()
            .map(|sig| Self::parse_signature(sig))
            .collect::<Result<_, _>>()?;

        let sum = parsed_sigs
            .into_iter()
            .reduce(|acc, next| acc + next)
            .unwrap_or_default();
        Ok(sum.to_affine().to_compressed().to_vec())
    }

    pub fn get_shared_secret(public_key: &[u8], seed: &[u8]) -> Result<Vec<u8>, CryptoError> {
        let sk = Self::parse_secret_key(seed)?;
        let pk_g1 = Self::parse_public_key(public_key)?;
        Ok((pk_g1 * sk).to_affine().to_compressed().to_vec())
    }

    pub fn validate_public_key(public_key: &[u8]) -> Result<(), CryptoError> {
        Self::parse_public_key(public_key).map(|_| ())
    }

    /* ---------- Internal Helpers ---------- */

    fn parse_public_key(bytes: &[u8]) -> Result<G1Projective, CryptoError> {
        if bytes.len() != 48 {
            return Err(CryptoError::InvalidPoint);
        }
        let mut res = [0u8; 48];
        res.copy_from_slice(bytes);

        match Option::<G1Affine>::from(G1Affine::from_compressed(&res)) {
            Some(affine) => {
                let projective = G1Projective::from(affine);
                if Self::g1_projective_is_valid(&projective) {
                    Ok(projective)
                } else {
                    Err(CryptoError::InvalidPoint)
                }
            }
            None => Err(CryptoError::InvalidPoint),
        }
    }

    fn parse_signature(bytes: &[u8]) -> Result<G2Projective, CryptoError> {
        if bytes.len() != 96 {
            return Err(CryptoError::InvalidPoint);
        }
        let mut res = [0u8; 96];
        res.copy_from_slice(bytes);

        match Option::from(G2Affine::from_compressed(&res)) {
            Some(affine) => {
                if Self::g2_affine_is_valid(&affine) {
                    Ok(G2Projective::from(affine))
                } else {
                    Err(CryptoError::InvalidPoint)
                }
            }
            None => Err(CryptoError::InvalidPoint),
        }
    }

    fn g1_projective_is_valid(projective: &G1Projective) -> bool {
        !bool::from(projective.is_identity())
            && bool::from(projective.is_on_curve())
            && bool::from(projective.to_affine().is_torsion_free())
    }

    fn g2_affine_is_valid(projective: &G2Affine) -> bool {
        !bool::from(projective.is_identity())
            && bool::from(projective.is_on_curve())
            && bool::from(projective.is_torsion_free())
    }

    fn parse_secret_key(seed: &[u8]) -> Result<Scalar, CryptoError> {
        if let Ok(bytes_64) = seed.try_into() as Result<[u8; 64], _> {
            return Ok(Scalar::from_bytes_wide(&bytes_64));
        }
        if let Ok(bytes_32) = seed.try_into() as Result<[u8; 32], _> {
            let ct_scalar = Scalar::from_bytes(&bytes_32);
            if ct_scalar.is_some().unwrap_u8() == 1 {
                return Ok(ct_scalar.unwrap());
            } else {
                return Err(CryptoError::InvalidSeed);
            }
        }
        Err(CryptoError::InvalidSeed)
    }
}
