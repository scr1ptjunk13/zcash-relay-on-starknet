#!/usr/bin/env python3
"""
Format Zcash Block as raw calldata for sncast --calldata
Outputs space-separated felt252 values ready for sncast invoke

Cairo serialization for ZcashBlockHeader:
  - n_version: u32 (1 felt)
  - hash_prev_block: Digest { value: [u32; 8] } (8 felts, NO length prefix for fixed array)
  - hash_merkle_root: Digest { value: [u32; 8] } (8 felts)
  - hash_block_commitments: Digest { value: [u32; 8] } (8 felts)
  - n_time: u32 (1 felt)
  - n_bits: u32 (1 felt)
  - n_nonce: u256 (2 felts: low, high)
  - n_solution: Span<u8> (1 felt for length + N felts for data)

Total: 1 + 8 + 8 + 8 + 1 + 1 + 2 + (1 + 1344) = 1374 felts
"""
import sys
import argparse
from pathlib import Path
sys.path.append(str(Path(__file__).parent))
from fetch import fetch_block_header

def digest_to_calldata(digest_dict):
    """Convert Digest to calldata: 8 u32 values as felts (no length prefix for fixed array)"""
    return [str(int(v)) for v in digest_dict['value']]

def u256_to_calldata(value):
    """Convert u256 to calldata: low (128 bits), high (128 bits)"""
    low = value & ((1 << 128) - 1)
    high = value >> 128
    return [str(low), str(high)]

def solution_to_calldata(solution_hex):
    """Convert solution hex to calldata: length + bytes"""
    bytes_list = [int(solution_hex[i:i+2], 16) for i in range(0, len(solution_hex), 2)]
    # Span<u8> serializes as: length (felt) + each byte (felt)
    return [str(len(bytes_list))] + [str(b) for b in bytes_list]

def header_to_calldata(header_data):
    """Convert ZcashBlockHeader to raw calldata"""
    solution_hex = header_data['n_solution']['hex'] if isinstance(header_data['n_solution'], dict) else header_data['n_solution']
    
    calldata = []
    
    # n_version: u32
    calldata.append(str(header_data['n_version']))
    
    # hash_prev_block: Digest (8 u32s, fixed array = no length)
    calldata.extend(digest_to_calldata(header_data['hash_prev_block']))
    
    # hash_merkle_root: Digest (8 u32s)
    calldata.extend(digest_to_calldata(header_data['hash_merkle_root']))
    
    # hash_block_commitments: Digest (8 u32s)
    calldata.extend(digest_to_calldata(header_data['hash_block_commitments']))
    
    # n_time: u32
    calldata.append(str(header_data['n_time']))
    
    # n_bits: u32
    calldata.append(str(header_data['n_bits']))
    
    # n_nonce: u256 (low, high)
    calldata.extend(u256_to_calldata(header_data['n_nonce']))
    
    # n_solution: Span<u8> (length + bytes)
    calldata.extend(solution_to_calldata(solution_hex))
    
    return calldata

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Format Zcash block as raw calldata')
    parser.add_argument('block', type=int, help='Block number to format')
    parser.add_argument('-v', '--verbose', action='store_true', help='Print block info to stderr')
    args = parser.parse_args()
    
    # Fetch block
    header = fetch_block_header(args.block, verify=True)
    
    # Convert to calldata
    calldata = header_to_calldata(header)
    
    if args.verbose:
        print(f"[Block {args.block}] Calldata: {len(calldata)} felts", file=sys.stderr)
    
    # Output space-separated calldata
    print(' '.join(calldata))
