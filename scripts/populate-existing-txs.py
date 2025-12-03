#!/usr/bin/env python3
"""
Populate verification TX hashes for existing blocks.
Run this script and paste TX hashes from Voyager.

Usage:
  python scripts/populate-existing-txs.py

Then follow prompts to enter TX hashes for each block.
"""

import json
import os

TX_LOG_FILE = "frontend/src/data/verifications.json"

STEP_NAMES = [
    "start",
    "batch[0]", "batch[1]", "batch[2]", "batch[3]",
    "batch[4]", "batch[5]", "batch[6]", "batch[7]",
    "tree",
    "finalize"
]

def load_data():
    if os.path.exists(TX_LOG_FILE):
        with open(TX_LOG_FILE, 'r') as f:
            return json.load(f)
    return {}

def save_data(data):
    os.makedirs(os.path.dirname(TX_LOG_FILE), exist_ok=True)
    with open(TX_LOG_FILE, 'w') as f:
        json.dump(data, f, indent=2)

def populate_block(block_num: int, tx_hashes: list, vid: str = ""):
    """Add TX hashes for a block."""
    data = load_data()
    block_key = f"block_{block_num}"
    
    transactions = []
    for i, tx_hash in enumerate(tx_hashes):
        if tx_hash and tx_hash.startswith("0x"):
            transactions.append({
                "step": i + 1,
                "name": STEP_NAMES[i],
                "txHash": tx_hash,
                "time": 0  # Unknown for historical
            })
    
    data[block_key] = {
        "verification_id": vid,
        "transactions": transactions
    }
    
    save_data(data)
    print(f"✓ Saved {len(transactions)} transactions for block {block_num}")

def main():
    print("=" * 50)
    print("Populate Verification TX Hashes")
    print("=" * 50)
    print()
    print("Get TX hashes from Voyager:")
    print("https://sepolia.voyager.online/contract/0x0546f738f87885a936cb8df8085b4b3fdc9bf1be6449cf5f9967c4a5892a12dc#transactions")
    print()
    
    while True:
        block_input = input("Enter block number (or 'q' to quit): ").strip()
        if block_input.lower() == 'q':
            break
        
        try:
            block_num = int(block_input)
        except ValueError:
            print("Invalid block number")
            continue
        
        vid = input(f"  Verification ID for block {block_num} (or press Enter to skip): ").strip()
        
        print(f"  Enter 11 TX hashes for block {block_num}, one per line:")
        print(f"  (Copy from Voyager, oldest to newest for this block)")
        
        tx_hashes = []
        for i in range(11):
            tx = input(f"    TX {i+1}/11 ({STEP_NAMES[i]}): ").strip()
            tx_hashes.append(tx)
        
        populate_block(block_num, tx_hashes, vid)
        print()

if __name__ == "__main__":
    main()
