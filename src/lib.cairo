/// Zcash Relay - Starknet Smart Contract
/// Trustless verification of Zcash block headers on Starknet

pub mod relay;
pub mod interfaces;
pub mod events;
pub mod errors;
pub mod zcash {
    pub mod block;
    pub mod status;
    pub mod difficulty;
    pub mod equihash;
    pub mod verification;
}
pub mod utils {
    pub mod bit_shifts;
    pub mod bit_utils;
    pub mod blake2b;
    pub mod digest_store;  // Store trait implementation for Digest
    pub mod double_sha256;
    pub mod hash;
    pub mod hex;
    pub mod numeric;
    pub mod sha256;
    pub mod word_array;
}

#[cfg(test)]
mod tests {
    mod utils;
    mod blockregistration;
}

