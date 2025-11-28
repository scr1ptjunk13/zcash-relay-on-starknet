use starknet::storage_access::{Store, StorageBaseAddress};
use crate::utils::hash::{Digest, U256IntoDigest, DigestIntoU256};

/// Implements Store trait for Digest to enable storage in contracts
/// Converts Digest to/from u256 for storage operations
pub impl DigestStore of starknet::Store<Digest> {
    fn read(address_domain: u32, base: StorageBaseAddress) -> starknet::SyscallResult<Digest> {
        match Store::<u256>::read(address_domain, base) {
            Result::Ok(value) => {
                Result::Ok(value.into())
            },
            Result::Err(err) => Result::Err(err),
        }
    }

    fn write(
        address_domain: u32, base: StorageBaseAddress, value: Digest
    ) -> starknet::SyscallResult<()> {
        let value_as_u256: u256 = value.into();
        Store::<u256>::write(address_domain, base, value_as_u256)
    }

    fn read_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8
    ) -> starknet::SyscallResult<Digest> {
        match Store::<u256>::read_at_offset(address_domain, base, offset) {
            Result::Ok(value) => {
                Result::Ok(value.into())
            },
            Result::Err(err) => Result::Err(err),
        }
    }

    fn write_at_offset(
        address_domain: u32, base: StorageBaseAddress, offset: u8, value: Digest
    ) -> starknet::SyscallResult<()> {
        let value_as_u256: u256 = value.into();
        Store::<u256>::write_at_offset(address_domain, base, offset, value_as_u256)
    }

    fn size() -> u8 {
        Store::<u256>::size()
    }
}
