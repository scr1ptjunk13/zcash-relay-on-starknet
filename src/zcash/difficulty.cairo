//! Zcash Difficulty Target Conversion
//!
//! Converts compact nBits format to target difficulty.
//! Formula: target = mantissa * 256^(exponent - 3)
//! Implements Zcash Core SetCompact() algorithm.

/// Converts compact nBits format to target difficulty
/// 
/// # Arguments
/// * `bits` - Compact difficulty format (nBits from block header)
/// 
/// # Returns
/// * `Ok(target)` - Target difficulty as u256
/// * `Err(msg)` - Invalid format or overflow

pub fn bits_to_target(bits: u32) -> Result<u256, ByteArray> {
    // Extract exponent (top 8 bits) and mantissa (bottom 23 bits)
    let exponent = bits / 0x1000000;
    let mantissa = bits & 0x007fffff;

    // Check for negative bit (0x00800000) - invalid for PoW
    if mantissa != 0 && (bits & 0x00800000) != 0 {
        return Result::Err("Target mantissa has negative bit set - invalid");
    }

    // Check for overflow conditions
    if mantissa != 0 && (
        (exponent > 34) ||
        (mantissa > 0xff && exponent > 33) ||
        (mantissa > 0xffff && exponent > 32)
    ) {
        return Result::Err("Target would overflow");
    }

    // Handle small exponents
    if exponent <= 3 {
        let shift_amount = 8 * (3 - exponent);
        let divisor = pow_2_u32(shift_amount);
        let target = mantissa / divisor;
        return Result::Ok(target.into());
    }

    // Handle large exponents: target = mantissa << (8 * (exponent - 3))
    let shift_amount = 8 * (exponent - 3);
    let mantissa_u256: u256 = mantissa.into();
    let multiplier = pow_2_u256(shift_amount);
    let target = mantissa_u256 * multiplier;
    
    Result::Ok(target)
}

/// Helper: Calculate 2^n for u32 range
fn pow_2_u32(n: u32) -> u32 {
    if n == 0 {
        return 1;
    }
    if n >= 32 {
        return 0;
    }
    
    let mut result: u32 = 1;
    let mut i = 0;
    while i < n {
        result = result * 2;
        i += 1;
    };
    result
}

/// Helper: Calculate 2^n for u256 range
fn pow_2_u256(n: u32) -> u256 {
    if n == 0 {
        return 1_u256;
    }
    if n >= 256 {
        return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff_u256;
    }
    
    let mut result: u256 = 1;
    let mut i = 0;
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
    fn test_bits_to_target_exponent_3() {
        let target = bits_to_target(0x03123456).unwrap();
        assert(target == 0x123456_u256, 'exp3_failed');
    }

    #[test]
    fn test_bits_to_target_exponent_4() {
        let target = bits_to_target(0x04123456).unwrap();
        assert(target == 0x12345600_u256, 'exp4_failed');
    }

    #[test]
    fn test_bits_to_target_invalid_msb() {
        let result = bits_to_target(0x04800000);
        assert!(result.is_err());
    }

    #[test]
    fn test_bits_to_target_overflow_exponent() {
        let result = bits_to_target(0x23000001);
        assert!(result.is_err());
    }

    #[test]
    fn test_bits_to_target_overflow_mantissa() {
        let result = bits_to_target(0x22000100);
        assert!(result.is_err());
    }
}
