// Bit manipulation utilities for Equihash validation
// Provides functions for extracting, manipulating, and checking bits
// Used for parsing Equihash solutions and verifying collision trees

/// Extract arbitrary bits from a byte array in BIG-ENDIAN bit order
/// 
/// This is the correct format for Zcash Equihash packed indices.
/// Bytes are read MSB-first (most significant byte first).
/// 
/// # Arguments
/// * `data` - Byte array to extract from
/// * `bit_offset` - Starting bit position (0-indexed)
/// * `num_bits` - Number of bits to extract (1-32)
/// 
/// # Returns
/// * u32 containing the extracted bits
/// 
/// # Example
/// Extract bits 0-20 (21 bits) from genesis block solution:
/// Hex bytes: 00 0a 88 9f ...
/// Should give: 0x000151 = 337 (decimal)
pub fn extract_bits(data: Span<u8>, bit_offset: u32, num_bits: u32) -> u32 {
    if num_bits == 0 || num_bits > 32 {
        return 0;
    }
    
    let byte_offset = bit_offset / 8;
    let bit_shift = bit_offset % 8;
    
    // Read 4 bytes in BIG-ENDIAN order (MSB first) - enough for up to 32 bits
    let bytes_needed = 4;
    
    // Build value in big-endian order: (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    let mut value: u32 = 0;
    let mut i = 0;
    while i < bytes_needed {
        if byte_offset + i < data.len() {
            let byte_val: u32 = (*data[byte_offset + i]).into();
            value = (value * 256) | byte_val;  // Shift left 8 bits and OR (big-endian)
        } else {
            value = value * 256;  // Pad with zeros if past end
        }
        i += 1;
    };
    
    // Calculate shift from right and mask
    // For big-endian, we have 32 bits total, need to skip bit_shift from left,
    // then extract num_bits
    let shift_from_right = (bytes_needed * 8) - bit_shift - num_bits;
    let mask = if num_bits == 32 { 0xFFFFFFFF } else { pow2_u32(num_bits) - 1 };
    
    (value / pow2_u32(shift_from_right)) & mask
}

/// Extract a single 21-bit index from packed Equihash solution
/// 
/// # Arguments
/// * `data` - Packed solution bytes (1,344 bytes for Zcash Equihash)
/// * `index_num` - Index number (0-511 for k=9)
/// 
/// # Returns
/// * u32 containing the 21-bit index value
/// 
/// # Example
/// For Zcash Equihash (n=200, k=9):
/// - Each index is 21 bits
/// - 512 indices total
/// - index_num ranges from 0 to 511
pub fn extract_index(data: Span<u8>, index_num: u32) -> u32 {
    let bit_offset = index_num * 21;
    extract_bits(data, bit_offset, 21)
}

/// Helper: Calculate 2^n for u32
fn pow2_u32(n: u32) -> u32 {
    if n == 0 { return 1; }
    if n >= 32 { return 0; }
    let mut result: u32 = 1;
    let mut i = 0;
    while i < n {
        result = result * 2;
        i += 1;
    };
    result
}

/// Helper: Calculate 2^n for u256
fn pow2_u256(n: u32) -> u256 {
    if n == 0 { return 1; }
    if n >= 256 { return 0; }
    let mut result: u256 = 1;
    let mut i = 0;
    while i < n {
        result = result * 2;
        i += 1;
    };
    result
}

/// Check if the first num_bits of a value are zero
/// 
/// # Arguments
/// * `value` - Value to check
/// * `num_bits` - Number of bits to check from LSB
/// 
/// # Returns
/// * true if first num_bits are zero, false otherwise
/// 
/// # Example
/// check_bits_zero(0x00000000, 20) → true
/// check_bits_zero(0x00100000, 20) → false (bit 20 is set)
pub fn check_bits_zero(value: u256, num_bits: u32) -> bool {
    if num_bits == 0 {
        return true;
    }
    if num_bits >= 256 {
        return value == 0;
    }
    
    let mask = get_bit_mask(num_bits);
    (value & mask) == 0
}

/// Generate a bit mask with num_bits set to 1
/// 
/// # Arguments
/// * `num_bits` - Number of bits to set (0-256)
/// 
/// # Returns
/// * u256 with first num_bits set to 1
/// 
/// # Example
/// get_bit_mask(20) = 0xFFFFF (20 bits of 1s)
/// get_bit_mask(0) = 0
/// get_bit_mask(256) = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
pub fn get_bit_mask(num_bits: u32) -> u256 {
    if num_bits == 0 {
        return 0;
    }
    if num_bits >= 256 {
        return 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    }
    
    pow2_u256(num_bits) - 1
}

/// Extract bits from u256 value
/// 
/// # Arguments
/// * `value` - u256 value to extract from
/// * `bit_offset` - Starting bit position
/// * `num_bits` - Number of bits to extract
/// 
/// # Returns
/// * u256 with extracted bits (right-aligned)
pub fn extract_bits_u256(value: u256, bit_offset: u32, num_bits: u32) -> u256 {
    if num_bits == 0 || num_bits > 256 {
        return 0;
    }
    
    let shifted = value / pow2_u256(bit_offset);
    let mask = get_bit_mask(num_bits);
    shifted & mask
}

/// Rotate u256 right by n bits
/// 
/// # Arguments
/// * `value` - Value to rotate
/// * `n` - Number of bits to rotate right
/// 
/// # Returns
/// * Rotated value
pub fn rotate_right_u256(value: u256, n: u32) -> u256 {
    let n = n % 256;
    if n == 0 {
        return value;
    }
    (value / pow2_u256(n)) | (value * pow2_u256(256 - n))
}

/// Rotate u256 left by n bits
/// 
/// # Arguments
/// * `value` - Value to rotate
/// * `n` - Number of bits to rotate left
/// 
/// # Returns
/// * Rotated value
pub fn rotate_left_u256(value: u256, n: u32) -> u256 {
    let n = n % 256;
    if n == 0 {
        return value;
    }
    (value * pow2_u256(n)) | (value / pow2_u256(256 - n))
}

/// Count number of set bits (population count)
/// 
/// # Arguments
/// * `value` - Value to count bits in
/// 
/// # Returns
/// * Number of 1 bits in value
pub fn popcount_u256(value: u256) -> u32 {
    let mut count: u32 = 0;
    let mut v = value;
    let mut i: u32 = 0;
    while i < 256_u32 {
        if v & 1 == 1 {
            count += 1;
        }
        v = v / 2;
        i += 1;
    };
    count
}

/// Convert u32 to little-endian bytes
/// 
/// # Arguments
/// * `value` - u32 value to convert
/// 
/// # Returns
/// * Array of 4 bytes in little-endian order
pub fn encode_u32_le(value: u32) -> Array<u8> {
    let mut bytes = array![];
    let mut v = value;
    let mut i: u32 = 0;
    while i < 4_u32 {
        bytes.append((v & 0xFF).try_into().unwrap());
        v = v / 256;
        i += 1;
    };
    bytes
}

/// Convert u64 to little-endian bytes
/// 
/// # Arguments
/// * `value` - u64 value to convert
/// 
/// # Returns
/// * Array of 8 bytes in little-endian order
pub fn encode_u64_le(value: u64) -> Array<u8> {
    let mut bytes = array![];
    let mut v = value;
    let mut i: u32 = 0;
    while i < 8_u32 {
        bytes.append((v & 0xFF).try_into().unwrap());
        v = v / 256;
        i += 1;
    };
    bytes
}

/// Convert little-endian bytes to u32
/// 
/// # Arguments
/// * `bytes` - Array of bytes in little-endian order
/// 
/// # Returns
/// * u32 value
pub fn decode_u32_le(bytes: @Array<u8>) -> u32 {
    let mut value: u32 = 0;
    let mut i = 0;
    while i < 4 && i < bytes.len() {
        let byte_val: u32 = (*bytes[i]).into();
        let shift_amount = i * 8;
        let shifted_byte = if shift_amount == 0 { byte_val } else { byte_val * pow2_u32(shift_amount) };
        value = value | shifted_byte;
        i += 1;
    };
    value
}

/// Convert little-endian bytes to u64
/// 
/// # Arguments
/// * `bytes` - Array of bytes in little-endian order
/// 
/// # Returns
/// * u64 value
pub fn decode_u64_le(bytes: @Array<u8>) -> u64 {
    let mut value: u64 = 0;
    let mut i: u32 = 0;
    while i < 8_u32 && i < bytes.len().try_into().unwrap() {
        let byte_val: u64 = (*bytes[i.try_into().unwrap()]).into();
        let shift_amount = i * 8;
        let shifted_byte = if shift_amount == 0 { byte_val } else { byte_val * pow2_u64(shift_amount) };
        value = value | shifted_byte;
        i += 1;
    };
    value
}

/// Helper: Calculate 2^n for u64
fn pow2_u64(n: u32) -> u64 {
    if n == 0 { return 1; }
    if n >= 64 { return 0; }
    let mut result: u64 = 1;
    let mut i: u32 = 0;
    while i < n {
        result = result * 2;
        i += 1;
    };
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_bits_first_byte() {
        let data = array![0xFF, 0x00, 0x00].span();
        let result = extract_bits(data, 0, 8);
        assert(result == 0xFF, 'assertion_failed');
    }

    #[test]
    fn test_extract_bits_spanning() {
        // Extract bits 160-180 (21 bits) spanning 3 bytes
        let mut data = array![];
        let mut i: u32 = 0;
        while i < 20 {
            data.append(0x00);
            i += 1;
        };
        // Set some bits in bytes 20, 21, 22
        data.append(0xFF);
        data.append(0xFF);
        data.append(0xFF);
        
        // Bit 160 = byte 20 (160 / 8 = 20)
        let result = extract_bits(data.span(), 160, 21);
        // Should extract 21 bits starting at bit 160 (from the 0xFF bytes)
        assert(result > 0, 'extract_bits_spanning_failed');
    }

    #[test]
    fn test_extract_index_0() {
        // Create a solution with known values
        let mut data = array![];
        let mut i: u32 = 0;
        while i < 1344 {
            data.append(0x00);
            i += 1;
        };
        
        let index = extract_index(data.span(), 0);
        assert(index == 0, 'assertion_failed');
    }

    #[test]
    fn test_check_bits_zero_valid() {
        let value: u256 = 0x00000000;
        assert(check_bits_zero(value, 20), 'check_bits_zero_valid_failed');
    }

    #[test]
    fn test_check_bits_zero_invalid() {
        let value: u256 = 0x00100000;
        assert(!check_bits_zero(value, 21), 'check_bits_zero_invalid_failed');
    }

    #[test]
    fn test_get_bit_mask_20() {
        let mask = get_bit_mask(20);
        assert(mask == 0xFFFFF, 'assertion_failed');
    }

    #[test]
    fn test_get_bit_mask_0() {
        let mask = get_bit_mask(0);
        assert(mask == 0, 'assertion_failed');
    }

    #[test]
    fn test_encode_u32_le() {
        let value: u32 = 0x12345678;
        let bytes = encode_u32_le(value);
        assert(bytes.len() == 4, 'assertion_failed');
        assert(*bytes[0] == 0x78, 'assertion_failed');
        assert(*bytes[1] == 0x56, 'assertion_failed');
        assert(*bytes[2] == 0x34, 'assertion_failed');
        assert(*bytes[3] == 0x12, 'assertion_failed');
    }

    #[test]
    fn test_decode_u32_le() {
        let bytes = array![0x78, 0x56, 0x34, 0x12];
        let value = decode_u32_le(@bytes);
        assert(value == 0x12345678, 'assertion_failed');
    }

    #[test]
    fn test_encode_decode_u32_roundtrip() {
        let original: u32 = 0xDEADBEEF;
        let encoded = encode_u32_le(original);
        let decoded = decode_u32_le(@encoded);
        assert(decoded == original, 'assertion_failed');
    }

    #[test]
    fn test_rotate_right_u256() {
        // Test with a smaller rotation that won't overflow
        let value: u256 = u256 { low: 0x0000000000000001_u128, high: 0 };
        let rotated = rotate_right_u256(value, 1);
        // Rotating right by 1 should move the bit to the high part
        assert(rotated.high > 0, 'rotate_right_u256_failed');
    }

    #[test]
    fn test_rotate_left_u256() {
        let value: u256 = 0x0000000000000000000000000000000000000000000000000000000000000001;
        let rotated = rotate_left_u256(value, 1);
        assert(rotated == 0x0000000000000000000000000000000000000000000000000000000000000002, 'assertion_failed');
    }

    #[test]
    fn test_popcount_u256() {
        let value: u256 = 0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F;
        let count = popcount_u256(value);
        // 4 bits set in each of 32 bytes = 128 total
        assert(count == 128, 'assertion_failed');
    }
}
