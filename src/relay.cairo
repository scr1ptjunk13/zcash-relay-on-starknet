/// Zcash Relay - Zcash block verification on Starknet

#[starknet::contract]
pub mod ZcashRelay {
    use starknet::{ContractAddress, get_block_timestamp};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use crate::utils::hash::Digest;
    use crate::utils::digest_store::DigestStore;
    use crate::zcash::block::ZcashBlockHeader;
    use crate::zcash::status::BlockStatus;
    use crate::zcash::difficulty::bits_to_target;
    use crate::events::{BlockRegistered, CanonicalChainUpdated, ChainReorganization, VerificationStarted};
    use crate::errors::RelayError;
    use crate::utils::double_sha256::double_sha256_block_header;
    use core::num::traits::zero::Zero;
    use crate::zcash::verification;
    
    // Must match verification.cairo constants
    const LEAVES_PER_BATCH: u32 = 64;
    const NUM_LEAF_BATCHES: u32 = 8;
    use crate::zcash::equihash::{indices_from_minimal_bytes, EquihashNode, is_zero_prefix, collision_byte_length};
    use core::poseidon::poseidon_hash_span;
    use crate::utils::bit_shifts::pow2;
    use crate::utils::numeric::u256_to_u32x8;
    
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // All registered blocks (including forks) - maps block hash to status
        blocks: starknet::storage::Map<Digest, BlockStatus>,
        
        // Canonical chain (height → block hash)
        chain: starknet::storage::Map<u64, Digest>,
        
        // Reverse height lookup (block hash → height) for O(1) height queries
        block_heights: starknet::storage::Map<Digest, u64>,
        
        // Merkle roots for blocks (block hash → merkle root) for transaction verification
        merkle_roots: starknet::storage::Map<Digest, Digest>,
        
        // Highest finalized height (blocks at or below this height are finalized)
        last_finalized_height: u64,
        
        // Finality depth (blocks must be this old to be considered finalized)
        finality_depth: u64,
        
        // Current highest height in canonical chain
        current_height: u64,
        
        // Initialization flag
        initialized: bool,
        
        // Incremental verification storage
        // Maps verification_id → header commitment (felt252)
        verification_headers: starknet::storage::Map<felt252, felt252>,
        // Maps (verification_id, index) → index value for solution indices
        verification_indices: starknet::storage::Map<(felt252, u32), u32>,
        // Maps verification_id → initiator address
        verification_initiators: starknet::storage::Map<felt252, ContractAddress>,
        // Maps verification_id → deadline timestamp
        verification_deadlines: starknet::storage::Map<felt252, u64>,
        // Maps verification_id → bitmap of completed batches (u256)
        verification_batches: starknet::storage::Map<felt252, u256>,
        // Root hash storage (only 1 root per verification, using u64x4 format)
        verification_root_c0: starknet::storage::Map<felt252, u64>,   // Root hash chunk 0
        verification_root_c1: starknet::storage::Map<felt252, u64>,   // Root hash chunk 1
        verification_root_c2: starknet::storage::Map<felt252, u64>,   // Root hash chunk 2
        verification_root_c3: starknet::storage::Map<felt252, u64>,   // Root hash chunk 3
        verification_root_len: starknet::storage::Map<felt252, u32>,  // Root hash length
        // Maps verification_id → block hash being verified
        verification_block_hashes: starknet::storage::Map<felt252, Digest>,
        // Maps verification_id → difficulty target (for PoW validation)
        verification_targets: starknet::storage::Map<felt252, u256>,
        
        // Leaf hash storage (512 leaves, each stored as 4 u64 chunks)
        // Key: (verification_id, leaf_index) → u64 chunk
        verification_leaf_c0: starknet::storage::Map<(felt252, u32), u64>,
        verification_leaf_c1: starknet::storage::Map<(felt252, u32), u64>,
        verification_leaf_c2: starknet::storage::Map<(felt252, u32), u64>,
        verification_leaf_c3: starknet::storage::Map<(felt252, u32), u64>,
        verification_leaf_len: starknet::storage::Map<(felt252, u32), u32>,  // Hash length
        
        // Components
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        BlockRegistered: BlockRegistered,
        CanonicalChainUpdated: CanonicalChainUpdated,
        ChainReorganization: ChainReorganization,
        VerificationStarted: VerificationStarted,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    const ZCASH_FINALITY_DEPTH: u64 = 100;  // ~2.5 hours
    fn calculate_pow_from_difficulty(n_bits: u32) -> u256 {
        match bits_to_target(n_bits) {
            Result::Ok(target) => {
                if target == 0 { return 0; }
                let denominator = target + 1;
                if denominator == 0 { return 0; }
                let max_value: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
                let inverted_target = max_value - target;
                (inverted_target / denominator) + 1
            },
            Result::Err(_) => 0,
        }
    }

    fn validate_height_range(begin_height: u64, end_height: u64) -> bool {
        end_height >= begin_height
    }

    fn is_height_continuous(current_height: u64, new_begin_height: u64) -> bool {
        if current_height == 0 { return new_begin_height == 0 || new_begin_height == 1; }
        new_begin_height == current_height + 1
    }

    fn validate_block_linkage(self: @ContractState, prev_block_hash: Digest, current_block_hash: Digest) -> bool {
        if prev_block_hash == Zero::zero() { return true; }  // genesis
        if current_block_hash == Zero::zero() { return false; }
        
        let status = self.blocks.read(current_block_hash);
        if status.registration_timestamp == 0 { return false; }
        status.prev_block_digest == prev_block_hash
    }

    fn calculate_reorg_depth(old_height: u64, new_height: u64) -> u64 {
        if old_height > new_height { old_height - new_height } else { new_height - old_height }
    }

    fn calculate_time_since_registration(registration_timestamp: u64, current_timestamp: u64) -> u64 {
        if current_timestamp > registration_timestamp { current_timestamp - registration_timestamp } else { 0 }
    }

    fn is_block_old_enough(time_since_registration: u64, min_age: u64) -> bool {
        time_since_registration >= min_age
    }

    fn has_sufficient_pow(block_pow: u256, min_pow: u256) -> bool {
        block_pow >= min_pow
    }

    /// Stateless header validation: version >= 4, future time < 2h, solution = 1344 bytes, nBits != 0
    /// PoW & MTP validation happen later (need chain state)
    fn validate_block_header(header: crate::zcash::block::ZcashBlockHeader) -> Result<bool, RelayError> {
        if header.n_version < 4 { return Result::Err(RelayError::InvalidVersion); }
        
        let current_time: u32 = (get_block_timestamp() % 0x100000000_u64).try_into().unwrap_or(0);
        if header.n_time > current_time + 7200 { return Result::Err(RelayError::InvalidTimestamp); }
        
        if header.n_solution.len() != 1344 { return Result::Err(RelayError::InvalidSolutionSize); }
        if header.n_bits == 0 { return Result::Err(RelayError::InvalidDifficultyTarget); }
        
        Result::Ok(true)
    }

    fn is_block_new(self: @ContractState, block_hash: Digest) -> bool {
        self.blocks.read(block_hash).registration_timestamp == 0
    }

    /// Walk backwards from end_block to begin_height, verify each block exists & links correctly
    fn validate_chain_consistency(
        self: @ContractState,
        end_block_hash: Digest,
        end_height: u64,
        begin_height: u64
    ) -> Result<(), RelayError> {
        let mut current_hash = end_block_hash;
        let mut current_height = end_height;
        
        loop {
            let block_status = self.blocks.read(current_hash);
            if block_status.registration_timestamp == 0 {
                return Result::Err(RelayError::BlockNotRegistered);
            }
            
            if current_height == begin_height { break; }
            
            let parent_hash = block_status.prev_block_digest;
            let parent_status = self.blocks.read(parent_hash);
            if parent_status.registration_timestamp == 0 {
                return Result::Err(RelayError::BlockNotRegistered);
            }
            
            current_hash = parent_hash;
            current_height -= 1;
        };
        
        Result::Ok(())
    }

    #[abi(embed_v0)]
    impl ZcashRelayImpl of crate::interfaces::IZcashRelay<ContractState> {
        fn initialize(ref self: ContractState, owner: ContractAddress) {
            if self.initialized.read() {
                panic!("Already initialized");
            }
            self.initialized.write(true);
            self.ownable.initializer(owner);
            
            self.finality_depth.write(ZCASH_FINALITY_DEPTH);
        }

        // incremental equihash: start → 16x leaves → tree → finalize (gas limit workaround)
        fn start_block_verification(
            ref self: ContractState,
            header: ZcashBlockHeader
        ) -> felt252 {
            // Validate header format
            validate_block_header(header).expect('Invalid header');
            
            // Compute block hash
            let block_hash = double_sha256_block_header(
                header.n_version,
                @header.hash_prev_block,
                @header.hash_merkle_root,
                @header.hash_block_commitments,
                header.n_time,
                header.n_bits,
                header.n_nonce,
                header.n_solution
            );
            
            assert(is_block_new(@self, block_hash), 'Block already registered');
            
            // validate PoW before expensive equihash
            let target = match bits_to_target(header.n_bits) {
                Result::Ok(t) => t,
                Result::Err(_) => { panic!("Invalid difficulty encoding"); }
            };
            
            let block_hash_u256: u256 = block_hash.into();
            if block_hash_u256 > target { panic!("Invalid PoW: hash > target"); }

            let initiator = starknet::get_caller_address();
            let verification_id = verification::compute_verification_id_from_hash(block_hash);
            
            let solution_array = span_to_array(header.n_solution);
            let (ok, indices) = indices_from_minimal_bytes(200, 9, solution_array);
            assert(ok, 'Failed to decode solution');
            
            let header_bytes = verification::serialize_header_140(header);
            let mut header_data = array![];
            let mut i = 0;
            while i < header_bytes.len() {
                header_data.append((*header_bytes[i]).into());
                i += 1;
            };
            let header_commitment = poseidon_hash_span(header_data.span());
            self.verification_headers.write(verification_id, header_commitment);
            
            let mut j: u32 = 0;
            while j < 512 {
                self.verification_indices.write((verification_id, j), *indices[j.try_into().unwrap()]);
                j += 1;
            };
            
            self.verification_initiators.write(verification_id, initiator);
            self.verification_deadlines.write(verification_id, get_block_timestamp() + 3600);
            self.verification_batches.write(verification_id, 0);
            self.verification_block_hashes.write(verification_id, block_hash);
            self.verification_targets.write(verification_id, target);

            self.emit(VerificationStarted {
                verification_id,
                block_hash,
                initiator,
            });

            verification_id
        }

        fn verify_leaves_batch(
            ref self: ContractState,
            verification_id: felt252,
            batch_id: u32,
            header: ZcashBlockHeader
        ) {
            assert(batch_id < NUM_LEAF_BATCHES, 'Invalid batch_id');
            assert(starknet::get_caller_address() == self.verification_initiators.read(verification_id), 'Not initiator');
            assert(get_block_timestamp() < self.verification_deadlines.read(verification_id), 'Verification expired');
            
            let batches = self.verification_batches.read(verification_id);
            let batch_bit: u256 = 1_u256 * pow2(batch_id).into();
            assert((batches & batch_bit) == 0, 'Batch already verified');
            
            // Only read the indices we need for this batch (not all 512!)
            let start_idx = batch_id * LEAVES_PER_BATCH;
            let mut indices = array![];
            let mut i: u32 = 0;
            while i < LEAVES_PER_BATCH {
                indices.append(self.verification_indices.read((verification_id, start_idx + i)));
                i += 1;
            };
            
            // nonce must be included for correct blake2b
            let mut header_with_nonce = verification::serialize_header_140(header);
            
            // Append nonce (32 bytes in little-endian)
            let nonce_u32s = u256_to_u32x8(header.n_nonce);
            let [w0, w1, w2, w3, w4, w5, w6, w7] = nonce_u32s;
            let words = array![w7, w6, w5, w4, w3, w2, w1, w0];  // LE order
            let mut k: usize = 0;
            while k < 8 {
                let word: u32 = *words[k];
                header_with_nonce.append((word & 0xFF_u32).try_into().unwrap());
                header_with_nonce.append(((word / 0x100_u32) & 0xFF_u32).try_into().unwrap());
                header_with_nonce.append(((word / 0x10000_u32) & 0xFF_u32).try_into().unwrap());
                header_with_nonce.append(((word / 0x1000000_u32) & 0xFF_u32).try_into().unwrap());
                k += 1;
            };
            
            let nodes = verification::verify_leaf_batch(
                batch_id,
                header_with_nonce,
                indices.span()
            );
            
            assert(nodes.len() == LEAVES_PER_BATCH.try_into().unwrap(), 'Invalid leaf count');
            
            let start_leaf_idx = batch_id * LEAVES_PER_BATCH;
            let mut j: u32 = 0;
            while j < LEAVES_PER_BATCH {
                let leaf_idx = start_leaf_idx + j;
                let node = nodes[j.try_into().unwrap()];
                
                let (c0, c1, c2, c3, hash_len) = verification::hash_to_u64x4(node.hash);
                
                self.verification_leaf_c0.write((verification_id, leaf_idx), c0);
                self.verification_leaf_c1.write((verification_id, leaf_idx), c1);
                self.verification_leaf_c2.write((verification_id, leaf_idx), c2);
                self.verification_leaf_c3.write((verification_id, leaf_idx), c3);
                self.verification_leaf_len.write((verification_id, leaf_idx), hash_len);
                j += 1;
            };
            
            self.verification_batches.write(verification_id, batches | batch_bit);
        }

        fn verify_tree_all_levels(
            ref self: ContractState,
            verification_id: felt252,
            header: ZcashBlockHeader
        ) {
            assert(starknet::get_caller_address() == self.verification_initiators.read(verification_id), 'Not initiator');
            assert(get_block_timestamp() < self.verification_deadlines.read(verification_id), 'Verification expired');
            // 8 batches: bits 0-7 set = 0xFF
            assert(self.verification_batches.read(verification_id) == 0xFF, 'Not all batches complete');

            // reconstruct leaves from stored hashes
            let mut leaves: Array<EquihashNode> = array![];
            let mut idx: u32 = 0;
            while idx < 512 {
                let c0 = self.verification_leaf_c0.read((verification_id, idx));
                let c1 = self.verification_leaf_c1.read((verification_id, idx));
                let c2 = self.verification_leaf_c2.read((verification_id, idx));
                let c3 = self.verification_leaf_c3.read((verification_id, idx));
                let hash_len = self.verification_leaf_len.read((verification_id, idx));
                let hash = verification::u64x4_to_hash(c0, c1, c2, c3, hash_len);
                let solution_idx = self.verification_indices.read((verification_id, idx));
                let mut indices = array![];
                indices.append(solution_idx);
                leaves.append(EquihashNode { hash, indices });
                idx += 1;
            };

            let collision_bytes = collision_byte_length(200, 9);
            let root_node = verification::build_subtree_recursive(
                leaves.span(),
                0,
                leaves.len(),
                collision_bytes
            );

            let (root_c0, root_c1, root_c2, root_c3, root_hash_len) = verification::hash_to_u64x4(@root_node.hash);
            self.verification_root_c0.write(verification_id, root_c0);
            self.verification_root_c1.write(verification_id, root_c1);
            self.verification_root_c2.write(verification_id, root_c2);
            self.verification_root_c3.write(verification_id, root_c3);
            self.verification_root_len.write(verification_id, root_hash_len);
        }

        fn finalize_block_verification(
            ref self: ContractState,
            verification_id: felt252,
            header: ZcashBlockHeader
        ) -> Result<Digest, RelayError> {
            assert(starknet::get_caller_address() == self.verification_initiators.read(verification_id), 'Not initiator');
            
            let root_c0 = self.verification_root_c0.read(verification_id);
            let root_c1 = self.verification_root_c1.read(verification_id);
            let root_c2 = self.verification_root_c2.read(verification_id);
            let root_c3 = self.verification_root_c3.read(verification_id);
            let root_hash_len = self.verification_root_len.read(verification_id);
            let root_hash = verification::u64x4_to_hash(root_c0, root_c1, root_c2, root_c3, root_hash_len);
            let root_node = EquihashNode { hash: root_hash, indices: array![] };
            
            let collision_bytes = collision_byte_length(200, 9);
            assert(is_zero_prefix(root_node, collision_bytes), 'Invalid root prefix');

            let target = self.verification_targets.read(verification_id);
            let block_hash = self.verification_block_hashes.read(verification_id);
            let block_hash_u256: u256 = block_hash.into();

            // Re-verify PoW (defense in depth)
            if block_hash_u256 > target {
                return Result::Err(RelayError::InvalidDifficultyTarget);
            }

            let pow = calculate_pow_from_difficulty(header.n_bits);
            let block_status = BlockStatus {
                registration_timestamp: get_block_timestamp(),
                prev_block_digest: header.hash_prev_block,
                pow,
                n_time: header.n_time,
            };
            
            self.blocks.write(block_hash, block_status);
            self.merkle_roots.write(block_hash, header.hash_merkle_root);
            
            // Emit event
            self.emit(BlockRegistered {
                block_hash,
                pow,
                timestamp: get_block_timestamp(),
            });

            // Auto-update canonical chain if block extends tip
            let current_height = self.current_height.read();
            let current_tip = self.chain.read(current_height);
            
            let zero_hash = Digest { value: [0, 0, 0, 0, 0, 0, 0, 0] };
            let chain_is_empty = current_tip == zero_hash;
            let is_genesis = chain_is_empty && header.hash_prev_block == zero_hash;
            let extends_tip = !chain_is_empty && header.hash_prev_block == current_tip;
            
            if is_genesis || extends_tip {
                // Genesis goes to height 0, subsequent blocks increment
                let new_height = if is_genesis { 0_u64 } else { current_height + 1 };
                
                // Update canonical chain mapping
                self.chain.write(new_height, block_hash);
                self.block_heights.write(block_hash, new_height);
                self.current_height.write(new_height);
                
                // Update finalized height if deep enough
                let finality_depth = self.finality_depth.read();
                if new_height >= finality_depth {
                    self.last_finalized_height.write(new_height - finality_depth);
                }
                
                // Emit chain update event
                self.emit(CanonicalChainUpdated {
                    new_height,
                    new_hash: block_hash,
                    total_pow: pow.into(), // Single block PoW for now
                });
            }

            cleanup_verification(ref self, verification_id);
            
            Result::Ok(block_hash)
        }

        fn update_canonical_chain(
            ref self: ContractState,
            begin_height: u64,
            end_height: u64,
            end_block_hash: Digest,
            height_proof: Option<Digest>  // TODO: Use proper HeightProof type
        ) -> Result<(), RelayError> {
            if !validate_height_range(begin_height, end_height) {
                return Result::Err(RelayError::InvalidHeightRange);
            }
            
            let end_block_status = self.blocks.read(end_block_hash);
            if end_block_status.registration_timestamp == 0 {
                return Result::Err(RelayError::BlockNotRegistered);
            }
            
            if begin_height > 0 {
                let prev_block_hash = self.chain.read(begin_height - 1);
                if !validate_block_linkage(@self, prev_block_hash, end_block_hash) {
                    return Result::Err(RelayError::InvalidBlockLinkage);
                }
            }
            
            validate_chain_consistency(@self, end_block_hash, end_height, begin_height)?;
            // MTP validation for each block in segment
            let mut validate_hash = end_block_hash;
            let mut validate_height = end_height;
            loop {
                if validate_height < begin_height { break; }
                
                if validate_height >= 11 {
                    let mut timestamps = array![];
                    let mut curr = validate_hash;
                    let status = self.blocks.read(curr);
                    curr = status.prev_block_digest;
                    
                    let mut i: u32 = 0;
                    while i < 11_u32 {
                        let status = self.blocks.read(curr);
                        if status.registration_timestamp == 0 { break; }
                        timestamps.append(status.n_time);
                        curr = status.prev_block_digest;
                        i += 1;
                    };
                    
                    if timestamps.len() == 11 {
                        let mtp = calculate_median_time_past(timestamps.span());
                        let block_status = self.blocks.read(validate_hash);
                        if block_status.n_time <= mtp {
                            return Result::Err(RelayError::TimestampTooOld);
                        }
                    }
                }
                
                let status = self.blocks.read(validate_hash);
                validate_hash = status.prev_block_digest;
                validate_height -= 1;
            };
            
            // update canonical chain
            let mut current_hash = end_block_hash;
            let mut current_height = end_height;
            loop {
                self.chain.write(current_height, current_hash);
                self.block_heights.write(current_hash, current_height);
                if current_height == begin_height { break; }
                let block_status = self.blocks.read(current_hash);
                current_hash = block_status.prev_block_digest;
                current_height -= 1;
            };
            
            self.current_height.write(end_height);
            
            let finality_depth = self.finality_depth.read();
            if end_height >= finality_depth {
                self.last_finalized_height.write(end_height - finality_depth);
            }
            
            let cumulative_pow = self.calculate_cumulative_pow_internal(end_block_hash, 1000);
            self.emit(CanonicalChainUpdated {
                new_height: end_height,
                new_hash: end_block_hash,
                total_pow: cumulative_pow,
            });
            
            let reorg_depth = calculate_reorg_depth(current_height, end_height);
            if reorg_depth > 0 {
                let old_canonical_hash = self.chain.read(current_height);
                let old_chain_pow = self.calculate_cumulative_pow_internal(old_canonical_hash, 1000);
                self.emit(ChainReorganization {
                    old_height: current_height,
                    new_height: end_height,
                    reorg_depth,
                    old_pow: old_chain_pow,
                    new_pow: cumulative_pow,
                });
            }
            
            Result::Ok(())
        }

        fn get_status(self: @ContractState, block_hash: Digest) -> BlockStatus {
            self.blocks.read(block_hash)
        }

        fn get_block(self: @ContractState, height: u64) -> Digest {
            self.chain.read(height)
        }

        fn assert_safe(
            self: @ContractState,
            block_height: u64,
            block_hash: Digest,
            min_cpow: u256,
            min_age: u64,
        ) -> Result<(), RelayError> {
            let block_status = self.get_status(block_hash);
            if block_status.registration_timestamp == 0 {
                return Result::Err(RelayError::BlockNotRegistered);
            }
            
            let canonical_hash = self.get_block(block_height);
            if canonical_hash != block_hash {
                return Result::Err(RelayError::BlockNotCanonical);
            }
            
            let current_timestamp = get_block_timestamp();
            let time_since_registration = calculate_time_since_registration(
                block_status.registration_timestamp,
                current_timestamp
            );
            if !is_block_old_enough(time_since_registration, min_age) {
                return Result::Err(RelayError::InsufficientAge);
            }
            
            let cumulative_pow = self.calculate_cumulative_pow_internal(block_hash, 1000);
            if !has_sufficient_pow(cumulative_pow, min_cpow) {
                return Result::Err(RelayError::InsufficientCumulativePoW);
            }
            
            Result::Ok(())
        }

        fn get_cumulative_pow(self: @ContractState, block_hash: Digest, max_depth: u32) -> u256 {
            let block_status = self.blocks.read(block_hash);
            if block_status.registration_timestamp == 0 {
                return 0;
            }
            self.calculate_cumulative_pow_internal(block_hash, max_depth)
        }

        fn get_block_ancestry(self: @ContractState, start_block_hash: Digest, max_depth: u32) -> u32 {
            self.get_block_ancestry_internal(start_block_hash, max_depth)
        }

        fn compare_chains(self: @ContractState, pow_chain_a: u256, pow_chain_b: u256) -> bool {
            pow_chain_a > pow_chain_b
        }

        fn find_fork_point(self: @ContractState, block_hash_a: Digest, block_hash_b: Digest, max_depth: u32) -> Digest {
            self.find_fork_point_internal(block_hash_a, block_hash_b, max_depth)
        }

        fn get_chain_height(self: @ContractState) -> u64 {
            self.current_height.read()
        }

        fn get_cumulative_pow_at_height(self: @ContractState, height: u64, max_depth: u32) -> u256 {
            let block_hash = self.chain.read(height);
            if block_hash == Zero::zero() { return 0; }
            
            let block_status = self.blocks.read(block_hash);
            if block_status.registration_timestamp == 0 { return 0; }
            
            self.calculate_cumulative_pow_internal(block_hash, max_depth)
        }

        fn is_block_canonical(self: @ContractState, block_hash: Digest, height: u64) -> bool {
            self.chain.read(height) == block_hash
        }

        /// Verify transaction inclusion via merkle proof
        fn verify_transaction_in_block(
            self: @ContractState,
            block_hash: Digest,
            tx_id: Digest,
            merkle_branch: Span<Digest>,
            merkle_index: u32
        ) -> Result<bool, RelayError> {
            match self.blocks.read(block_hash) {
                BlockStatus { registration_timestamp: 0, .. } => Result::Err(RelayError::BlockNotFound),
                _ => {
                    let merkle_root = self.get_merkle_root_for_block(block_hash)?;
                    let mut current_hash = tx_id;
                    let mut index = merkle_index;
                    
                    let mut branch_index = 0;
                    loop {
                        if branch_index >= merkle_branch.len() { break; }
                        
                        let sibling = *merkle_branch[branch_index];
                        current_hash = if index % 2 == 0 {
                            crate::utils::double_sha256::double_sha256_parent(@current_hash, @sibling)
                        } else {
                            crate::utils::double_sha256::double_sha256_parent(@sibling, @current_hash)
                        };
                        
                        index = index / 2;
                        branch_index += 1;
                    };
                    
                    if current_hash == merkle_root {
                        Result::Ok(true)
                    } else {
                        Result::Err(RelayError::InvalidMerkleProof)
                    }
                }
            }
        }

        fn is_block_finalized(self: @ContractState, block_hash: Digest) -> bool {
            let block_height = self.block_heights.read(block_hash);
            if block_height == 0 { return false; }
            block_height <= self.last_finalized_height.read()
        }

        fn get_finality_depth(self: @ContractState) -> u64 {
            self.finality_depth.read()
        }

        fn get_block_height(self: @ContractState, block_hash: Digest) -> u64 {
            self.block_heights.read(block_hash)
        }

        fn upgrade(ref self: ContractState, new_class_hash: starknet::ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    // internal helpers
    trait ZcashRelayHelpersTrait {
        fn calculate_cumulative_pow_internal(self: @ContractState, start_block_hash: Digest, max_depth: u32) -> u256;
        fn find_fork_point_internal(self: @ContractState, block_hash_a: Digest, block_hash_b: Digest, max_depth: u32) -> Digest;
        fn get_block_ancestry_internal(self: @ContractState, start_block_hash: Digest, max_depth: u32) -> u32;
        fn get_merkle_root_for_block(self: @ContractState, block_hash: Digest) -> Result<Digest, RelayError>;
        fn get_previous_timestamps(self: @ContractState, height: u64, count: u32) -> Array<u32>;
    }

    /// Selection sort for MTP calculation (11 timestamps)
    fn bubble_sort_u32(arr: Array<u32>) -> Array<u32> {
        let mut result = array![];
        let mut temp_arr = arr;
        
        loop {
            if temp_arr.len() == 0 {
                break;
            }
            
            // Find min
            let mut min_idx = 0;
            let mut min_val = *temp_arr[0];
            let mut j = 1;
            while j < temp_arr.len() {
                if *temp_arr[j] < min_val {
                    min_val = *temp_arr[j];
                    min_idx = j;
                }
                j += 1;
            };
            
            result.append(min_val);
            
            // Remove min (by rebuilding array without it)
            let mut new_temp = array![];
            let mut k = 0;
            while k < temp_arr.len() {
                if k != min_idx {
                    new_temp.append(*temp_arr[k]);
                }
                k += 1;
            };
            temp_arr = new_temp;
        };
        
        result
    }

    fn calculate_median_time_past(timestamps: Span<u32>) -> u32 {
        if timestamps.len() == 0 { return 0; }
        let count = timestamps.len();
        let mut arr = array![];
        let mut i = 0;
        while i < count {
            arr.append(*timestamps[i]);
            i += 1;
        };
        
        let sorted = bubble_sort_u32(arr);
        
        // Return median
        // For 11 blocks, this is index 5
        // For N blocks, this is index N/2
        *sorted[count / 2]
    }

    impl ZcashRelayHelpers of ZcashRelayHelpersTrait {
        /// Gets previous N block timestamps from canonical chain
        fn get_previous_timestamps(
            self: @ContractState,
            height: u64,
            count: u32
        ) -> Array<u32> {
            let mut timestamps = array![];
            let mut i: u64 = 0;
            
            // We need previous blocks, so start from height-1
            if height == 0 {
                return timestamps;
            }
            let mut current_h = height - 1;
            
            while i < count.into() {
                // Get block at current_h
                let block_hash = self.chain.read(current_h);
                
                // If we hit genesis (or invalid), block_hash might be zero/invalid check
                // but chain.read() returns zero for unset keys.
                // However, genesis is at height 0, so we should be fine until then.
                
                if block_hash != Zero::zero() {
                    let block_status = self.blocks.read(block_hash);
                    timestamps.append(block_status.n_time);
                } else {
                    // If we can't find a block (gap in chain?), stop
                    break;
                }
                
                if current_h == 0 {
                    break;
                }
                current_h -= 1;
                i += 1;
            };
            
            timestamps
        }

        /// Calculates cumulative proof-of-work from a starting block back to genesis
        /// 
        /// Walks back through the chain from a given block, accumulating PoW values
        /// until reaching genesis (prev_block_digest == 0) or max_depth.
        fn calculate_cumulative_pow_internal(
            self: @ContractState,
            start_block_hash: Digest,
            max_depth: u32
        ) -> u256 {
            let mut cumulative_pow: u256 = 0;
            let mut current_block_hash = start_block_hash;
            let mut depth = 0;
            
            // Walk back through the chain
            loop {
                // Stop if we've reached genesis (zero hash)
                if current_block_hash == Zero::zero() {
                    break;
                }
                
                // Stop if we've reached max depth
                if depth >= max_depth {
                    break;
                }
                
                // Read the current block's status from storage
                let block_status: BlockStatus = self.blocks.read(current_block_hash);
                
                // Add its PoW to cumulative
                cumulative_pow = cumulative_pow + block_status.pow;
                
                // Move to the previous block
                current_block_hash = block_status.prev_block_digest;
                depth += 1;
            };
            
            cumulative_pow
        }

        /// Finds the fork point (common ancestor) between two chains
        /// 
        /// Walks back from both blocks simultaneously until finding a common ancestor.
        /// Returns the hash of the common ancestor block.
        fn find_fork_point_internal(
            self: @ContractState,
            block_hash_a: Digest,
            block_hash_b: Digest,
            max_depth: u32
        ) -> Digest {
            // If blocks are the same, they're the fork point
            if block_hash_a == block_hash_b {
                return block_hash_a;
            }
            
            let mut current_a = block_hash_a;
            let mut current_b = block_hash_b;
            let mut depth = 0;
            
            // Walk back both chains until finding common ancestor
            loop {
                // Stop if we've exceeded max depth
                if depth >= max_depth {
                    break;
                }
                
                // If both are at genesis, no common ancestor found
                if current_a == Zero::zero() && current_b == Zero::zero() {
                    return Zero::zero();
                }
                
                // If they're equal, we found the fork point
                if current_a == current_b {
                    return current_a;
                }
                
                // Move both back one block
                // If either is genesis, keep it at genesis
                if current_a != Zero::zero() {
                    let status_a: BlockStatus = self.blocks.read(current_a);
                    current_a = status_a.prev_block_digest;
                }
                
                if current_b != Zero::zero() {
                    let status_b: BlockStatus = self.blocks.read(current_b);
                    current_b = status_b.prev_block_digest;
                }
                
                depth += 1;
            };
            
            // No fork point found within max_depth
            Zero::zero()
        }

        /// Gets the ancestry chain from a starting block back to genesis
        /// 
        /// Walks back from a block hash, collecting all ancestor blocks
        /// until reaching genesis (zero hash) or max_depth.
        /// Returns the count of blocks traversed (ancestry depth).
        fn get_block_ancestry_internal(
            self: @ContractState,
            start_block_hash: Digest,
            max_depth: u32
        ) -> u32 {
            let mut current_block_hash = start_block_hash;
            let mut depth = 0;
            
            // Walk back through the chain
            loop {
                // Stop if we've reached genesis (zero hash)
                if current_block_hash == Zero::zero() {
                    break;
                }
                
                // Stop if we've reached max depth
                if depth >= max_depth {
                    break;
                }
                
                // Read the current block's status from storage
                let block_status: BlockStatus = self.blocks.read(current_block_hash);
                
                // Move to the previous block
                current_block_hash = block_status.prev_block_digest;
                depth += 1;
            };
            
            depth
        }

        /// Gets the merkle root for a block
        /// 
        /// Retrieves the stored merkle root for a given block hash.
        /// Used for transaction inclusion proof verification.
        fn get_merkle_root_for_block(
            self: @ContractState,
            block_hash: Digest
        ) -> Result<Digest, RelayError> {
            let merkle_root = self.merkle_roots.read(block_hash);
            
            // Check if merkle root was found (zero means not stored)
            if merkle_root == Zero::zero() {
                return Result::Err(RelayError::BlockNotRegistered);
            }
            
            Result::Ok(merkle_root)
        }
    }

    // HELPER FUNCTIONS FOR INCREMENTAL VERIFICATION
    
    /// Convert span to array
    fn span_to_array(span: Span<u8>) -> Array<u8> {
        let mut arr = array![];
        let mut i = 0;
        while i < span.len() {
            arr.append(*span[i]);
            i += 1;
        };
        arr
    }

    /// Cleanup verification data (triggers gas refunds)
    fn cleanup_verification(
        ref self: ContractState,
        verification_id: felt252
    ) {
        // Clear verification metadata (triggers gas refund)
        self.verification_headers.write(verification_id, 0);
        self.verification_initiators.write(verification_id, 0_felt252.try_into().unwrap());
        self.verification_deadlines.write(verification_id, 0);
        self.verification_batches.write(verification_id, 0);
        self.verification_targets.write(verification_id, 0);
        self.verification_block_hashes.write(verification_id, Digest { value: [0, 0, 0, 0, 0, 0, 0, 0] });
        
        // Clear root hash storage
        self.verification_root_c0.write(verification_id, 0);
        self.verification_root_c1.write(verification_id, 0);
        self.verification_root_c2.write(verification_id, 0);
        self.verification_root_c3.write(verification_id, 0);
        self.verification_root_len.write(verification_id, 0);
        
        // Note: We don't clear all 512 leaf hashes and indices to save gas
        // Clearing 512 * 6 = 3072 storage slots would cost more than it saves
        // They will be overwritten on next verification with same ID anyway
    }
}
