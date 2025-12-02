#!/usr/bin/env python3
"""
Zcash Block Header Fetcher with Hash Verification
Fetches block headers and verifies block hash using double-SHA-256
"""

import json
import requests
import argparse
import hashlib
import struct
from typing import Dict, List, Tuple
from dotenv import load_dotenv
import os

load_dotenv()

RPC_URL = os.getenv("ZCASH_RPC_URL", "https://zcash-mainnet.gateway.tatum.io/")
RPC_KEY = os.getenv("ZCASH_RPC_API_KEY", "")

# Debug: print to stderr so we can see in logs
import sys
print(f"[DEBUG] RPC_URL: {RPC_URL[:50]}...", file=sys.stderr)
print(f"[DEBUG] RPC_KEY set: {bool(RPC_KEY)}", file=sys.stderr)


def rpc_call(method: str, params: list) -> dict:
    """Make RPC call to Zcash node"""
    auth = ("", RPC_KEY) if RPC_KEY else None
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 0}
    
    response = requests.post(RPC_URL, json=payload, auth=auth, timeout=10)
    result = response.json()
    
    if result.get("error"):
        raise Exception(f"RPC Error: {result['error']}")
    
    return result["result"]


def hash_to_digest(hash_hex: str) -> Dict:
    """Convert hash hex to Digest { value: [u32; 8] }
    
    RPC getblockheader returns hashes in display format (byte-reversed).
    We reverse to get internal format, then read as big-endian u32s.
    
    This matches Cairo's format:
    - hex_to_hash reads big-endian u32s from hex string
    - digest_to_bytes serializes as big-endian bytes
    - Both produce the correct raw block bytes (internal format)
    """
    hash_hex = hash_hex.replace("0x", "").zfill(64)
    hash_bytes = bytes.fromhex(hash_hex)
    
    # Reverse to get internal format (RPC returns display format = reversed)
    raw_bytes = hash_bytes[::-1]
    
    # Read as big-endian u32s (matches Cairo's hex_to_hash and digest_to_bytes)
    u32_array = []
    for i in range(0, 32, 4):
        chunk = raw_bytes[i:i+4]
        u32_array.append(int.from_bytes(chunk, 'big'))
    
    # Hex string for Python serialization (internal byte order)
    hex_string = raw_bytes.hex()
    
    # Cairo hex string for hex_to_hash: same as internal format
    # hex_to_hash reads big-endian u32s, so raw_bytes.hex() produces correct Digest
    cairo_hex = raw_bytes.hex()
    
    return {"value": u32_array, "hex": hex_string, "cairo_hex": cairo_hex}


def calculate_pow(bits: int) -> int:
    """
    Calculate PoW (Proof of Work) from bits using Zcash formula.
    
    Based on Zcash source code (pow.cpp - GetBlockProof):
    PoW = (~target / (target + 1)) + 1
    where ~target = (2^256 - 1) - target
    
    This is equivalent to: PoW = (2^256 - target - 1) / (target + 1) + 1
    
    Target is derived from bits using: target = mantissa * 2^(8 * (exponent - 3))
    """
    # Extract mantissa (lower 24 bits) and exponent (upper 8 bits)
    mantissa = bits & 0xffffff
    exponent = (bits >> 24) & 0xff
    
    # Calculate target from bits
    if exponent <= 3:
        target = mantissa >> (8 * (3 - exponent))
    else:
        target = mantissa << (8 * (exponent - 3))
    
    # Avoid division by zero
    if target == 0:
        return 0
    
    # Calculate PoW using Zcash formula: (~target / (target + 1)) + 1
    # where ~target = (2^256 - 1) - target
    max_256bit = (1 << 256) - 1  # 2^256 - 1
    inverted_target = max_256bit - target
    pow_value = (inverted_target // (target + 1)) + 1
    
    return pow_value


def serialize_header(header_data: Dict, raw_block_hex: str) -> bytes:
    """
    Serialize Zcash block header in the exact format used for hashing.
    
    Structure:
    - nVersion (4 bytes, little-endian)
    - hashPrevBlock (32 bytes, internal byte order)
    - hashMerkleRoot (32 bytes, internal byte order)
    - hashBlockCommitments (32 bytes, internal byte order)
    - nTime (4 bytes, little-endian)
    - nBits (4 bytes, little-endian)
    - nNonce (32 bytes, little-endian)
    - nSolution (variable length with CompactSize prefix)
    """
    serialized = b''
    
    # Parse raw block to extract nSolution
    raw_bytes = bytes.fromhex(raw_block_hex)
    
    # nVersion (4 bytes)
    serialized += struct.pack('<I', header_data['n_version'])
    
    # hashPrevBlock (32 bytes) - reverse from display format
    prev_hash = bytes.fromhex(header_data['hash_prev_block']['hex'])
    serialized += prev_hash
    
    # hashMerkleRoot (32 bytes) - reverse from display format
    merkle_root = bytes.fromhex(header_data['hash_merkle_root']['hex'])
    serialized += merkle_root
    
    # hashBlockCommitments (32 bytes) - reverse from display format
    commitments = bytes.fromhex(header_data['hash_block_commitments']['hex'])
    serialized += commitments
    
    # nTime (4 bytes)
    serialized += struct.pack('<I', header_data['n_time'])
    
    # nBits (4 bytes)
    serialized += struct.pack('<I', header_data['n_bits'])
    
    # nNonce (32 bytes) - little-endian
    nonce_bytes = header_data['n_nonce'].to_bytes(32, 'little')
    serialized += nonce_bytes
    
    # nSolution - extract from raw block (starts at offset 140)
    # The solution is serialized as a CompactSize length + data
    offset = 140  # After all fixed header fields
    solution_length = raw_bytes[offset]  # First byte is CompactSize (for < 253 bytes)
    
    if solution_length < 0xfd:
        # Length fits in 1 byte
        serialized += bytes([solution_length])
        offset += 1
        solution_data = raw_bytes[offset:offset+solution_length]
        serialized += solution_data
    elif solution_length == 0xfd:
        # Next 2 bytes are length
        length = struct.unpack('<H', raw_bytes[offset+1:offset+3])[0]
        serialized += bytes([0xfd])
        serialized += struct.pack('<H', length)
        offset += 3
        solution_data = raw_bytes[offset:offset+length]
        serialized += solution_data
    else:
        # For larger sizes (0xfe, 0xff)
        raise Exception("Unexpected solution length format")
    
    return serialized


def double_sha256(data: bytes) -> str:
    """Compute double SHA-256 hash (Bitcoin/Zcash standard)"""
    first_hash = hashlib.sha256(data).digest()
    second_hash = hashlib.sha256(first_hash).digest()
    # Reverse for display (little-endian to big-endian)
    return second_hash[::-1].hex()


def verify_block_hash(header_data: Dict, raw_block_hex: str, expected_hash: str) -> Tuple[bool, str]:
    """
    Verify block hash by computing double-SHA-256 of serialized header.
    Returns (is_valid, computed_hash)
    """
    try:
        serialized = serialize_header(header_data, raw_block_hex)
        computed_hash = double_sha256(serialized)
        is_valid = computed_hash == expected_hash
        return is_valid, computed_hash
    except Exception as e:
        return False, f"Error: {e}"


def fetch_block_header(block_height: int, verify: bool = False) -> Dict:
    """
    Fetch block header matching Cairo ZcashBlockHeader struct:
    
    pub struct ZcashBlockHeader {
        pub n_version: u32,
        pub hash_prev_block: Digest,
        pub hash_merkle_root: Digest,
        pub hash_block_commitments: Digest,
        pub n_time: u32,
        pub n_bits: u32,
        pub n_nonce: u256,
        pub n_solution: Array<u8>,  // Variable length Equihash solution
    }
    
    Also includes:
    - pow: Calculated proof-of-work value from bits
    - block_hash: The hash of this block (for reference)
    - verified: Whether the hash was verified (if verify=True)
    """
    blockhash = rpc_call("getblockhash", [block_height])
    header = rpc_call("getblockheader", [blockhash])
    
    # Parse nonce and bits
    nonce = int(header.get("nonce", "0"), 16) if header.get("nonce") else 0
    bits = int(header["bits"], 16) if isinstance(header["bits"], str) else header["bits"]
    
    result = {
        "n_version": header["version"],
        "hash_prev_block": hash_to_digest(header.get("previousblockhash", "0" * 64)),
        "hash_merkle_root": hash_to_digest(header["merkleroot"]),
        "hash_block_commitments": hash_to_digest(header.get("blockcommitments", "0" * 64)),
        "n_time": header["time"],
        "n_bits": bits,
        "n_nonce": nonce,
        "pow": calculate_pow(bits),
        "block_hash": blockhash
    }
    
    # If verification requested, fetch raw block and verify
    if verify:
        raw_block = rpc_call("getblock", [blockhash, 0])
        raw_bytes = bytes.fromhex(raw_block)
        
        # Extract nSolution from raw block (starts at offset 140)
        offset = 140
        solution_length = raw_bytes[offset]
        if solution_length < 0xfd:
            offset += 1
            solution_data = raw_bytes[offset:offset+solution_length]
        elif solution_length == 0xfd:
            length = struct.unpack('<H', raw_bytes[offset+1:offset+3])[0]
            offset += 3
            solution_data = raw_bytes[offset:offset+length]
        else:
            solution_data = b''
        
        result["n_solution"] = {
            "hex": solution_data.hex(),
            "length": len(solution_data)
        }
        
        # Verify the block hash
        is_valid, computed_hash = verify_block_hash(result, raw_block, blockhash)
        result["verification"] = {
            "valid": is_valid,
            "expected_hash": blockhash,
            "computed_hash": computed_hash
        }
    
    return result


def display_header(height: int, header: Dict, show_verification: bool = False) -> None:
    """Display header in readable format"""
    print(f"[Block {height}]")
    print(f"  block_hash: {header['block_hash']}")
    print(f"  n_version: {header['n_version']}")
    print(f"  n_time: {header['n_time']}")
    print(f"  n_bits: {hex(header['n_bits'])}")
    print(f"  n_nonce: {header['n_nonce']}")
    print(f"  pow: {header['pow']}")
    
    if 'n_solution' in header:
        print(f"  n_solution_length: {header['n_solution']['length']} bytes")
    
    if show_verification and 'verification' in header:
        v = header['verification']
        status = "✓ VALID" if v['valid'] else "✗ INVALID"
        print(f"\n  Verification: {status}")
        print(f"  Expected: {v['expected_hash']}")
        print(f"  Computed: {v['computed_hash']}")
    
    print()
    print("  Cairo format (exact values for test):")
    
    # Convert block_hash to u32 array for Cairo expected_hash
    # Use hash_to_digest for consistency (block_hash is in display format like other hashes)
    expected_digest = hash_to_digest(header['block_hash'])
    expected_hash_u32 = expected_digest['value']
    
    # Convert Digest values to internal format hex strings (for hex_to_hash)
    def digest_to_internal_hex(digest_values):
        hex_parts = []
        for val in digest_values:
            hex_parts.append(f'{val:08x}')
        return ''.join(hex_parts)
    
    print(f"  let n_version: u32 = {header['n_version']};")
    print(f"  let hash_prev_block = Digest {{ value: {header['hash_prev_block']['value']} }};")
    print(f"  // hex_to_hash(\"{header['hash_prev_block']['cairo_hex']}\");")
    print(f"  let hash_merkle_root = Digest {{ value: {header['hash_merkle_root']['value']} }};")
    print(f"  // hex_to_hash(\"{header['hash_merkle_root']['cairo_hex']}\");")
    print(f"  let hash_block_commitments = Digest {{ value: {header['hash_block_commitments']['value']} }};")
    print(f"  // hex_to_hash(\"{header['hash_block_commitments']['cairo_hex']}\");")
    print(f"  let n_time: u32 = {header['n_time']};")
    print(f"  let n_bits: u32 = {header['n_bits']};")
    print(f"  let n_nonce: u256 = {header['n_nonce']};")
    print()
    if 'n_solution' in header:
        # Extract just the hex string from the solution dict
        solution_hex = header['n_solution']['hex'] if isinstance(header['n_solution'], dict) else header['n_solution']
        print(f"  let solution: Array<u8> = hex_to_bytes_array(\"{solution_hex}\");")
        print()
    # expected_hash uses same format as header hashes
    expected_cairo_hex = ''.join(f'{x:08x}' for x in expected_hash_u32)
    print(f"  let expected_hash = Digest {{ value: {expected_hash_u32} }};")
    print(f"  // hex_to_hash(\"{expected_cairo_hex}\");")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Fetch Zcash block headers with hash verification"
    )
    parser.add_argument("block", type=int, help="Block height (genesis = 0)")
    parser.add_argument("-c", "--count", type=int, default=1, help="Number of blocks")
    parser.add_argument("-o", "--output", type=str, help="Output JSON file")
    parser.add_argument("-r", "--readable", action="store_true", help="Display readable format")
    parser.add_argument("-v", "--verify", action="store_true", help="Verify block hash with double-SHA-256")
    
    args = parser.parse_args()
    
    if args.count == 1:
        header = fetch_block_header(args.block, verify=args.verify)
        
        if args.readable:
            display_header(args.block, header, show_verification=args.verify)
        else:
            print(json.dumps(header, indent=2))
        
        if args.output:
            with open(args.output, "w") as f:
                json.dump(header, f, indent=2)
    else:
        headers = []
        for i in range(args.count):
            height = args.block + i
            try:
                header = fetch_block_header(height, verify=args.verify)
                headers.append({"height": height, "header": header})
                
                if args.readable:
                    display_header(height, header, show_verification=args.verify)
                else:
                    status = ""
                    if args.verify and 'verification' in header:
                        status = " ✓" if header['verification']['valid'] else " ✗"
                    print(f"Block {height}{status}")
            except Exception as e:
                print(f"✗ Block {height}: {e}")
        
        if args.output:
            with open(args.output, "w") as f:
                json.dump(headers, f, indent=2)
            print(f"\nSaved {len(headers)} headers to {args.output}")


if __name__ == "__main__":
    main()