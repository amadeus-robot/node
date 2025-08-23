#[derive(Debug)]
pub enum CryptoError {
    /// Cryptographic invalidity
    InvalidSignature,
    InvalidPoint,
    ZeroSizedInput,
    InvalidSeed,
    VerificationFailed,
}