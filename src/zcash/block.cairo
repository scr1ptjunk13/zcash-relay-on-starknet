//! Zcash Block Header
//!
//! The header is 140 bytes fixed + a 1344-byte Equihash(200,9) solution.

use crate::utils::hash::Digest;
use crate::utils::double_sha256::double_sha256_block_header;

/// NU5 spec
/// refer : https://zips.z.cash/protocol/protocol.pdf 
#[derive(Drop, Copy, Debug, PartialEq, Serde)]
pub struct ZcashBlockHeader {
    pub n_version: u32,                        // 4 bytes
    pub hash_prev_block: Digest,               // 32 bytes
    pub hash_merkle_root: Digest,              // 32 bytes
    pub hash_block_commitments: Digest,        // 32 bytes
    pub n_time: u32,                           // 4 bytes
    pub n_bits: u32,                           // 4 bytes
    pub n_nonce: u256,                         // 32 bytes
    pub n_solution: Span<u8>,                  // 1344-byte
}

#[generate_trait]
pub impl ZcashBlockHeaderImpl of ZcashBlockHeaderTrait {
    /// constructor
    fn new(
        n_version: u32,
        hash_prev_block: Digest,
        hash_merkle_root: Digest,
        hash_block_commitments: Digest,
        n_time: u32,
        n_bits: u32,
        n_nonce: u256,
        n_solution: Span<u8>
    ) -> ZcashBlockHeader {
        ZcashBlockHeader {
            n_version,
            hash_prev_block,
            hash_merkle_root,
            hash_block_commitments,
            n_time,
            n_bits,
            n_nonce,
            n_solution,
        }
    }
}

/// block hash calculation
#[generate_trait]
pub impl ZcashBlockHeaderHashImpl of ZcashBlockHeaderHashTrait {
    /// calculates block hash: double-SHA256(header || solution)
    /// note : hash fields are serialized as big-endian bytes, integers as little-endian.
    fn hash(self: @ZcashBlockHeader) -> Digest {
        double_sha256_block_header(
            *self.n_version, //le
            self.hash_prev_block, //be
            self.hash_merkle_root, //be
            self.hash_block_commitments, //be
            *self.n_time, //le
            *self.n_bits, //le
            *self.n_nonce,
            *self.n_solution,
        )
    }
}
