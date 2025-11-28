//! Contract Events
//! 
//! Events emitted by the relay for off-chain indexing and monitoring.

use crate::utils::hash::Digest;

/// when new block gets registered and verified
#[derive(Drop, starknet::Event)]
pub struct BlockRegistered {
    pub block_hash: Digest,
    pub timestamp: u64,
    pub pow: u256,
}

/// when canonical chain is extended or updated
#[derive(Drop, starknet::Event)]
pub struct CanonicalChainUpdated {
    pub new_height: u64,
    pub new_hash: Digest,
    pub total_pow: u256,
}

/// when chain reorganization detected (rare but important)
#[derive(Drop, starknet::Event)]
pub struct ChainReorganization {
    pub old_height: u64,
    pub new_height: u64,
    pub reorg_depth: u64,
    pub old_pow: u256,
    pub new_pow: u256,
}

/// when incremental verification started (for tracking multi-tx progress)
#[derive(Drop, starknet::Event)]
pub struct VerificationStarted {
    #[key]
    pub verification_id: felt252,
    pub block_hash: Digest,
    pub initiator: starknet::ContractAddress,
}
