#!/usr/bin/env python3
"""
Get block info and transaction data for demo/testing.

Usage:
  python scripts/get-block-txs.py <block_height>
  python scripts/get-block-txs.py 6

Outputs everything you need to paste into the Bridge page.
"""

import json
import requests
import sys
import os
from dotenv import load_dotenv

load_dotenv()

RPC_URL = os.getenv("ZCASH_RPC_URL", "https://zcash-mainnet.gateway.tatum.io/")
RPC_KEY = os.getenv("ZCASH_RPC_API_KEY", "")

def rpc(method, params):
    auth = ("", RPC_KEY) if RPC_KEY else None
    r = requests.post(RPC_URL, json={"jsonrpc": "2.0", "method": method, "params": params, "id": 0}, auth=auth, timeout=30)
    result = r.json()
    if result.get("error"):
        raise Exception(f"RPC Error: {result['error']}")
    return result["result"]

def double_sha256(data):
    import hashlib
    return hashlib.sha256(hashlib.sha256(data).digest()).digest()

def get_merkle_proof(tx_hashes, tx_index):
    """Generate merkle branch for a transaction"""
    if len(tx_hashes) == 1:
        return [], tx_hashes[0]
    
    branch = []
    idx = tx_index
    current = tx_hashes[:]
    
    while len(current) > 1:
        if len(current) % 2 == 1:
            current.append(current[-1])
        
        sibling_idx = idx + 1 if idx % 2 == 0 else idx - 1
        if sibling_idx < len(current):
            branch.append(current[sibling_idx][::-1].hex())  # Back to display format
        
        next_level = []
        for i in range(0, len(current), 2):
            combined = current[i] + current[i + 1]
            next_level.append(double_sha256(combined))
        
        current = next_level
        idx = idx // 2
    
    return branch, current[0]

def main():
    if len(sys.argv) < 2:
        print("Usage: python scripts/get-block-txs.py <block_height>")
        print("Example: python scripts/get-block-txs.py 6")
        sys.exit(1)
    
    height = int(sys.argv[1])
    
    print(f"\n{'='*60}")
    print(f"  ZCASH BLOCK {height} - TRANSACTION DATA")
    print(f"{'='*60}\n")
    
    # Get block
    block_hash = rpc("getblockhash", [height])
    block = rpc("getblock", [block_hash, 1])
    
    print(f"Block Hash:   {block['hash']}")
    print(f"Merkle Root:  {block['merkleroot']}")
    print(f"Timestamp:    {block['time']}")
    print(f"TX Count:     {len(block['tx'])}")
    
    print(f"\n{'-'*60}")
    print("TRANSACTIONS:")
    print(f"{'-'*60}")
    
    for i, txid in enumerate(block['tx']):
        tx_type = "coinbase" if i == 0 else "regular"
        print(f"\n  TX {i} ({tx_type}):")
        print(f"  ID: {txid}")
    
    # Generate proof for first transaction (or specify which one)
    tx_index = 0
    txid = block['tx'][tx_index]
    
    # Convert to internal format for merkle tree
    tx_hashes = [bytes.fromhex(t)[::-1] for t in block['tx']]
    branch, _ = get_merkle_proof(tx_hashes, tx_index)
    
    print(f"\n{'='*60}")
    print(f"  COPY-PASTE FOR BRIDGE PAGE")
    print(f"{'='*60}\n")
    
    print("Option 1 - Enter in form fields:")
    print(f"  Transaction ID: {txid}")
    print(f"  Block Hash:     {height}")
    
    print("\n" + "-"*60)
    
    proof_json = {
        "tx_id": txid,
        "block_hash": block['hash'],
        "merkle_branch": branch,
        "merkle_index": tx_index,
        "tx_count": len(block['tx'])
    }
    
    print("\nOption 2 - Paste this JSON:")
    print(json.dumps(proof_json))
    
    print(f"\n{'='*60}")
    print("  VERIFICATION COMMAND (optional)")
    print(f"{'='*60}\n")
    print(f"python scripts/merkle-proof.py {height} {txid}")
    print()

if __name__ == "__main__":
    main()
