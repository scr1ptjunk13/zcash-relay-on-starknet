#!/usr/bin/env python3
"""
Compute verification_id from block hash.
Simple approach: pack first 7 u32s of block hash into felt252
Matches Cairo's compute_verification_id_from_hash
"""
import sys
import argparse
from pathlib import Path
sys.path.append(str(Path(__file__).parent))
from fetch import fetch_block_header


def compute_verification_id_from_block_hash(block_hash_hex: str) -> int:
    """
    Compute verification_id from block hash.
    
    Cairo implementation:
    - Destructure Digest [u32; 8] = [v0, v1, v2, v3, v4, v5, v6, v7]
    - result = v0 * 2^192 + v1 * 2^160 + v2 * 2^128 + v3 * 2^96 + v4 * 2^64 + v5 * 2^32 + v6
    
    Cairo's hex_to_hash processes hex string sequentially:
    - "08ce3d97" -> 0x08ce3d97 (big-endian)
    """
    # Remove 0x prefix if present
    block_hash_hex = block_hash_hex.replace("0x", "")
    
    # Block hash from RPC is in display format (reversed)
    # Convert to internal format (reversed bytes)
    hash_bytes = bytes.fromhex(block_hash_hex)
    internal_bytes = hash_bytes[::-1]
    internal_hex = internal_bytes.hex()
    
    # Convert to u32 array the same way Cairo's hex_to_hash does:
    # Process 8 hex chars at a time, interpret as big-endian u32
    u32_array = []
    for i in range(0, 64, 8):
        chunk_hex = internal_hex[i:i+8]
        u32_array.append(int(chunk_hex, 16))  # Big-endian (same as Cairo)
    
    # Pack first 7 u32s into result (same as Cairo)
    result = 0
    for i in range(7):
        result = result * 0x100000000 + u32_array[i]
    
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Compute verification_id for a block')
    parser.add_argument('block', type=int, help='Block number')
    args = parser.parse_args()
    
    # Fetch block
    header = fetch_block_header(args.block, verify=True)
    
    # Get block hash
    block_hash = header['block_hash']
    
    # Compute verification_id
    verification_id = compute_verification_id_from_block_hash(block_hash)
    
    print(f"0x{verification_id:056x}")
