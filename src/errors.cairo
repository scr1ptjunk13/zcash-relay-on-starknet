//! Relay Error Types
//!
//! Typed errors for external callers to handle failures gracefully.

#[derive(Drop, Debug, Serde)]
pub enum UtuRelayError {
    InvalidDifficultyTarget,
    InvalidMerkleProof,
    InvalidTimestamp,
    BlockNotFound,
    InvalidHeightRange,
    HeightProofRequired,
    BlockNotRegistered,
    InvalidBlockLinkage,
    BlockNotCanonical,
    InsufficientAge,
    InsufficientCumulativePoW,
    InvalidSolutionSize,
    InvalidVersion,
    TimestampTooOld,
}
