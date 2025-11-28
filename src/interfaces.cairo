//! Relay Contract Interface
//!
//! Public API for external contracts (bridges, dApps) to verify Zcash blocks on Starknet.

use starknet::ContractAddress;
use crate::utils::hash::Digest;
use crate::zcash::{block::ZcashBlockHeader, status::BlockStatus};
use crate::utils::hash::Digest as HeightProof;  // TODO: Define proper HeightProof type
use crate::errors::RelayError;

#[starknet::interface]
pub trait IZcashRelay<TContractState> {
    fn initialize(ref self: TContractState, owner: ContractAddress);

    // INCREMENTAL BLOCK VERIFICATION
    // tried single-tx equihash verification first, hit gas limits hard >;/
    // split into 19 transactions: leaf batches + tree build + finalize
    fn start_block_verification(ref self: TContractState, header: ZcashBlockHeader) -> felt252;
    fn verify_leaves_batch(
        ref self: TContractState,
        verification_id: felt252,
        batch_id: u32,
        header: ZcashBlockHeader
    );
    fn verify_tree_all_levels(
        ref self: TContractState,
        verification_id: felt252,
        header: ZcashBlockHeader
    );
    fn finalize_block_verification(
        ref self: TContractState,
        verification_id: felt252,
        header: ZcashBlockHeader
    ) -> Result<Digest, RelayError>;


    // CHAIN MANAGEMENT
    fn update_canonical_chain(
        ref self: TContractState,
        begin_height: u64,
        end_height: u64,
        end_block_hash: Digest,
        height_proof: Option<HeightProof>
    ) -> Result<(), RelayError>;


    // READ FUNCTIONS
    fn get_status(self: @TContractState, block_hash: Digest) -> BlockStatus;
    fn get_block(self: @TContractState, height: u64) -> Digest;
    fn get_chain_height(self: @TContractState) -> u64;
    fn get_block_height(self: @TContractState, block_hash: Digest) -> u64;
    fn is_block_canonical(self: @TContractState, block_hash: Digest, height: u64) -> bool;
    fn is_block_finalized(self: @TContractState, block_hash: Digest) -> bool;
    fn get_finality_depth(self: @TContractState) -> u64;


    // SAFETY CHECKS
    fn assert_safe(
        self: @TContractState,
        block_height: u64,
        block_hash: Digest,
        min_cpow: u256,
        min_age: u64,
    ) -> Result<(), RelayError>;
    fn verify_transaction_in_block(
        self: @TContractState,
        block_hash: Digest,
        tx_id: Digest,
        merkle_branch: Span<Digest>,
        merkle_index: u32
    ) -> Result<bool, RelayError>;


    // CHAIN ANALYSIS
    fn get_cumulative_pow(self: @TContractState, block_hash: Digest, max_depth: u32) -> u256;
    fn get_cumulative_pow_at_height(self: @TContractState, height: u64, max_depth: u32) -> u256;
    fn get_block_ancestry(self: @TContractState, start_block_hash: Digest, max_depth: u32) -> u32;
    fn compare_chains(self: @TContractState, pow_chain_a: u256, pow_chain_b: u256) -> bool;
    fn find_fork_point(self: @TContractState, block_hash_a: Digest, block_hash_b: Digest, max_depth: u32) -> Digest;


    // ADMIN
    fn upgrade(ref self: TContractState, new_class_hash: starknet::ClassHash);
}
