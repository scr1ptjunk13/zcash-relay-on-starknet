/// Block Status Type
/// 
/// Stores metadata about registered blocks.

use crate::utils::digest_store::DigestStore;

/// Block Status

/// Contains metadata for a registered block including registration time,
/// previous block hash, proof-of-work value, and block timestamp.
#[derive(Drop, Serde, Debug, Default, PartialEq, starknet::Store)]
pub struct BlockStatus {
    pub registration_timestamp: u64,           // When registered on Starknet
    pub prev_block_digest: crate::utils::hash::Digest, // Link to parent block (as Digest)
    pub pow: u256,                             // Proof-of-work value (block's individual PoW)
    pub n_time: u32,                           // Block's timestamp from header (for MTP validation)
}
