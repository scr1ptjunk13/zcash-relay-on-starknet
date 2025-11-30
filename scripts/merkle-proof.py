#!/usr/bin/env python3
"""
zcash merkle proof generator

generates merkle branch proofs for transaction inclusion verification.
this is the key to proving "this tx exists on zcash" on starknet.

usage:
  python merkle-proof.py <block_hash_or_height> <txid>
  python merkle-proof.py 2590000 abc123...

outputs json with:
  - tx_id: the transaction id
  - block_hash: the block containing the tx
  - merkle_root: the block's merkle root
  - merkle_branch: array of sibling hashes (the proof)
  - merkle_index: position of tx in tree
"""

import json
import requests
import argparse
import hashlib
from typing import Dict, List, Tuple, Optional
from dotenv import load_dotenv
import os
import sys

load_dotenv()

RPC_URL = os.getenv("ZCASH_RPC_URL", "https://zcash-mainnet.gateway.tatum.io/")
RPC_KEY = os.getenv("ZCASH_RPC_API_KEY", "")


def rpc_call(method: str, params: list) -> dict:
    """make rpc call to zcash node"""
    auth = ("", RPC_KEY) if RPC_KEY else None
    payload = {"jsonrpc": "2.0", "method": method, "params": params, "id": 0}
    
    response = requests.post(RPC_URL, json=payload, auth=auth, timeout=30)
    result = response.json()
    
    if result.get("error"):
        raise Exception(f"RPC Error: {result['error']}")
    
    return result["result"]


def double_sha256(data: bytes) -> bytes:
    """double sha256 - used for merkle tree"""
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()


def hash_to_digest_array(hash_hex: str) -> List[int]:
    """
    convert hash hex to Digest { value: [u32; 8] } format
    
    zcash txids are displayed in reverse byte order (like block hashes).
    we need internal format for the contract.
    """
    hash_hex = hash_hex.replace("0x", "").zfill(64)
    hash_bytes = bytes.fromhex(hash_hex)
    
    # reverse to get internal format
    raw_bytes = hash_bytes[::-1]
    
    # read as big-endian u32s
    u32_array = []
    for i in range(0, 32, 4):
        chunk = raw_bytes[i:i+4]
        u32_array.append(int.from_bytes(chunk, 'big'))
    
    return u32_array


def hash_to_internal_hex(hash_hex: str) -> str:
    """convert display format hash to internal format hex"""
    hash_hex = hash_hex.replace("0x", "").zfill(64)
    hash_bytes = bytes.fromhex(hash_hex)
    return hash_bytes[::-1].hex()


def build_merkle_tree(tx_hashes: List[bytes]) -> Tuple[bytes, List[List[bytes]]]:
    """
    build merkle tree from transaction hashes.
    returns (root, levels) where levels[i] contains nodes at level i.
    level 0 = leaves (transactions)
    """
    if not tx_hashes:
        return bytes(32), [[]]
    
    # level 0 = transaction hashes (already in internal byte order)
    levels = [tx_hashes[:]]
    current_level = tx_hashes[:]
    
    while len(current_level) > 1:
        next_level = []
        
        # if odd number, duplicate last
        if len(current_level) % 2 == 1:
            current_level.append(current_level[-1])
        
        # hash pairs
        for i in range(0, len(current_level), 2):
            combined = current_level[i] + current_level[i + 1]
            parent = double_sha256(combined)
            next_level.append(parent)
        
        levels.append(next_level)
        current_level = next_level
    
    return current_level[0], levels


def get_merkle_proof(tx_hashes: List[bytes], tx_index: int) -> Tuple[List[bytes], bytes]:
    """
    get merkle branch proof for tx at given index.
    returns (branch, root) where branch is array of sibling hashes.
    """
    root, levels = build_merkle_tree(tx_hashes)
    
    branch = []
    idx = tx_index
    
    for level in levels[:-1]:  # skip root level
        # duplicate last if odd (like tree building)
        level_copy = level[:]
        if len(level_copy) % 2 == 1:
            level_copy.append(level_copy[-1])
        
        # get sibling
        if idx % 2 == 0:
            sibling_idx = idx + 1
        else:
            sibling_idx = idx - 1
        
        if sibling_idx < len(level_copy):
            branch.append(level_copy[sibling_idx])
        
        idx = idx // 2
    
    return branch, root


def get_block_txids(block_identifier: str) -> Tuple[str, List[str], str]:
    """
    get block hash and all txids for a block.
    block_identifier can be hash or height.
    returns (block_hash, txids, merkle_root)
    """
    # if numeric, treat as height
    try:
        height = int(block_identifier)
        block_hash = rpc_call("getblockhash", [height])
    except ValueError:
        block_hash = block_identifier
    
    # get block with txids
    block = rpc_call("getblock", [block_hash, 1])  # verbosity 1 = include txids
    
    return block_hash, block["tx"], block["merkleroot"]


def generate_merkle_proof(block_identifier: str, txid: str) -> Dict:
    """
    generate complete merkle proof for a transaction.
    
    returns dict with:
      - tx_id: transaction id (display format)
      - tx_id_internal: internal format hex for cairo
      - tx_id_digest: u32[8] array for cairo
      - block_hash: block containing tx
      - block_hash_digest: u32[8] array for cairo
      - merkle_root: from block header
      - merkle_root_digest: u32[8] array
      - merkle_branch: array of sibling hashes
      - merkle_branch_digests: array of u32[8] arrays
      - merkle_index: position in tree
    """
    block_hash, txids, merkle_root = get_block_txids(block_identifier)
    
    # find tx index
    txid_lower = txid.lower()
    tx_index = None
    for i, tid in enumerate(txids):
        if tid.lower() == txid_lower:
            tx_index = i
            break
    
    if tx_index is None:
        raise Exception(f"Transaction {txid} not found in block {block_hash}")
    
    # convert txids to internal byte order
    tx_hashes = []
    for tid in txids:
        # txid is in display format (reversed), convert to internal
        internal_bytes = bytes.fromhex(tid)[::-1]
        tx_hashes.append(internal_bytes)
    
    # generate proof
    branch, computed_root = get_merkle_proof(tx_hashes, tx_index)
    
    # verify our computed root matches block's merkle root
    expected_root_internal = bytes.fromhex(merkle_root)[::-1]
    if computed_root != expected_root_internal:
        print(f"warning: computed root {computed_root.hex()} != expected {expected_root_internal.hex()}")
    
    # format output
    result = {
        "tx_id": txid,
        "tx_id_internal": hash_to_internal_hex(txid),
        "tx_id_digest": hash_to_digest_array(txid),
        "block_hash": block_hash,
        "block_hash_internal": hash_to_internal_hex(block_hash),
        "block_hash_digest": hash_to_digest_array(block_hash),
        "merkle_root": merkle_root,
        "merkle_root_internal": hash_to_internal_hex(merkle_root),
        "merkle_root_digest": hash_to_digest_array(merkle_root),
        "merkle_branch": [b[::-1].hex() for b in branch],  # back to display format
        "merkle_branch_internal": [b.hex() for b in branch],  # internal format
        "merkle_branch_digests": [hash_to_digest_array(b[::-1].hex()) for b in branch],
        "merkle_index": tx_index,
        "tx_count": len(txids)
    }
    
    return result


def format_cairo_calldata(proof: Dict) -> str:
    """format proof as cairo calldata for sncast"""
    lines = []
    lines.append("// cairo calldata for verify_transaction_in_block")
    lines.append("")
    lines.append("// block_hash: Digest")
    lines.append(f"// {proof['block_hash']}")
    for v in proof['block_hash_digest']:
        lines.append(f"{v}")
    
    lines.append("")
    lines.append("// tx_id: Digest")
    lines.append(f"// {proof['tx_id']}")
    for v in proof['tx_id_digest']:
        lines.append(f"{v}")
    
    lines.append("")
    lines.append(f"// merkle_branch: Array<Digest> (len={len(proof['merkle_branch'])})")
    lines.append(f"{len(proof['merkle_branch'])}")
    for i, branch_digest in enumerate(proof['merkle_branch_digests']):
        lines.append(f"// branch[{i}]: {proof['merkle_branch'][i]}")
        for v in branch_digest:
            lines.append(f"{v}")
    
    lines.append("")
    lines.append(f"// merkle_index: u32")
    lines.append(f"{proof['merkle_index']}")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="generate merkle proof for zcash transaction",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
examples:
  # get proof for a tx in block 2590000
  python merkle-proof.py 2590000 <txid>
  
  # get proof by block hash
  python merkle-proof.py 0000000... <txid>
  
  # output cairo calldata
  python merkle-proof.py 2590000 <txid> --cairo
        """
    )
    parser.add_argument("block", help="block hash or height")
    parser.add_argument("txid", help="transaction id to prove")
    parser.add_argument("--cairo", action="store_true", help="output cairo calldata format")
    parser.add_argument("-o", "--output", help="output file (json)")
    
    args = parser.parse_args()
    
    try:
        print(f"fetching block {args.block}...", file=sys.stderr)
        proof = generate_merkle_proof(args.block, args.txid)
        
        if args.cairo:
            print(format_cairo_calldata(proof))
        else:
            print(json.dumps(proof, indent=2))
        
        if args.output:
            with open(args.output, "w") as f:
                json.dump(proof, f, indent=2)
            print(f"\nsaved to {args.output}", file=sys.stderr)
        
        # summary
        print(f"\n✓ proof generated", file=sys.stderr)
        print(f"  tx: {proof['tx_id'][:16]}...{proof['tx_id'][-8:]}", file=sys.stderr)
        print(f"  block: {proof['block_hash'][:16]}...", file=sys.stderr)
        print(f"  index: {proof['merkle_index']} of {proof['tx_count']} txs", file=sys.stderr)
        print(f"  branch depth: {len(proof['merkle_branch'])}", file=sys.stderr)
        
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
