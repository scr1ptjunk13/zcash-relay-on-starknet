use crate::interfaces::{IUtuRelayZcashDispatcher, IUtuRelayZcashDispatcherTrait};
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use crate::utils::hash::Digest;
use crate::zcash::status::BlockStatus;

/// Serialization trait implementations for testing
pub impl BlockStatusIntoSpan of Into<BlockStatus, Span<felt252>> {
    fn into(self: BlockStatus) -> Span<felt252> {
        let mut serialized_struct: Array<felt252> = array![];
        self.serialize(ref serialized_struct);
        serialized_struct.span()
    }
}

pub impl DigestIntoSpan of Into<Digest, Span<felt252>> {
    fn into(self: Digest) -> Span<felt252> {
        let mut serialized_struct: Array<felt252> = array![];
        self.serialize(ref serialized_struct);
        serialized_struct.span()
    }
}

/// Deploy UtuRelay contract and return dispatcher
pub fn deploy_utu() -> IUtuRelayZcashDispatcher {
    let contract = declare("UtuRelay").unwrap().contract_class();
    
    // Deploy with empty constructor
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    let dispatcher = IUtuRelayZcashDispatcher { contract_address };
    
    // Initialize the contract with owner (use the contract's own address as owner for testing)
    dispatcher.initialize(contract_address);
    
    dispatcher
}

/// Create a Digest from 8 u32 values
pub fn create_digest(v0: u32, v1: u32, v2: u32, v3: u32, v4: u32, v5: u32, v6: u32, v7: u32) -> Digest {
    Digest { value: [v0, v1, v2, v3, v4, v5, v6, v7] }
}

/// Create a zero Digest (all zeros)
pub fn zero_digest() -> Digest {
    create_digest(0, 0, 0, 0, 0, 0, 0, 0)
}
