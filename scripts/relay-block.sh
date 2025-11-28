#!/bin/bash
# Zcash block relay - usage: ./relay_block.sh <block> [--resume]

set +e
set +H

MAX_RETRIES=5
RETRY_DELAY=10
BATCH_DELAY=8

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

[ -z "$1" ] && { echo "Usage: $0 <block_number> [--resume]"; exit 1; }

BLOCK=$1
RESUME=false
[ "$2" = "--resume" ] && RESUME=true

CONTRACT="0x037f98ffad155b2534be9e38e77c40a0d5d49044b6781a2ca5e3248c0b9968ba"
ACCOUNT="testnet_account"
NETWORK="sepolia"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.relay_state_${BLOCK}"

# Timing
START_TIME=$(date +%s)
TX_COUNT=0

echo ""
echo "Relaying block $BLOCK to $NETWORK"
echo ""

# Invoke with retry
invoke() {
    local func=$1 calldata=$2 desc=$3 attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        output=$(sncast --account $ACCOUNT invoke --contract-address $CONTRACT --function $func --calldata $calldata --network $NETWORK 2>&1)
        if echo "$output" | grep -q "Transaction Hash:"; then
            tx=$(echo "$output" | grep -oP 'Transaction Hash: \K0x[a-f0-9]+' | head -1)
            echo -e "${GREEN}$desc${NC} $tx"
            ((TX_COUNT++))
            return 0
        fi
        echo "$output" | grep -qi "already\|duplicate" && { echo -e "${YELLOW}$desc (skipped)${NC}"; return 0; }
        echo -e "${YELLOW}$desc retry $attempt/$MAX_RETRIES${NC}"
        sleep $RETRY_DELAY
        ((attempt++))
    done
    echo -e "${RED}$desc FAILED${NC}"
    return 1
}

save_state() { echo "$1" > "$STATE_FILE"; echo "VID=$VID" >> "$STATE_FILE"; }
load_state() { [ -f "$STATE_FILE" ] && { head -1 "$STATE_FILE"; source "$STATE_FILE" 2>/dev/null; } || echo "0"; }

cd "$SCRIPT_DIR/.."

# Fetch block
echo -n "Fetching block $BLOCK... "
HEADER=$(python scripts/format-block-calldata.py $BLOCK -v 2>/dev/null)
[ -z "$HEADER" ] && { echo -e "${RED}failed${NC}"; exit 1; }
echo "ok ($(echo $HEADER | wc -w) felts)"

# Get verification ID
VID=$(python scripts/compute-verification-id.py $BLOCK 2>/dev/null)
[ -z "$VID" ] && { echo -e "${RED}Failed to compute verification_id${NC}"; exit 1; }
echo "Verification ID: $VID"
echo ""

LAST=0
[ "$RESUME" = true ] && [ -f "$STATE_FILE" ] && { LAST=$(load_state); echo "Resuming from step $((LAST+1))"; }

# TX1: Start
[ $LAST -lt 1 ] && { invoke "start_block_verification" "$HEADER" "1/19 start" || exit 1; save_state 1; sleep 12; }

# TX2-17: Batches
FAILED=()
for i in {0..15}; do
    step=$((i+2))
    [ $LAST -lt $step ] && {
        invoke "verify_leaves_batch" "$VID $i $HEADER" "$((i+2))/19 batch $i" && save_state $step || FAILED+=($i)
        sleep $BATCH_DELAY
    }
done

# Retry failed
for i in "${FAILED[@]}"; do
    invoke "verify_leaves_batch" "$VID $i $HEADER" "$((i+2))/19 batch $i (retry)" || { echo "Batch $i failed. Use --resume"; exit 1; }
    save_state $((i+2))
    sleep $BATCH_DELAY
done

# TX18: Tree
[ $LAST -lt 18 ] && { invoke "verify_tree_all_levels" "$VID $HEADER" "18/19 tree" || exit 1; save_state 18; sleep 12; }

# TX19: Finalize
[ $LAST -lt 19 ] && { invoke "finalize_block_verification" "$VID $HEADER" "19/19 finalize" || exit 1; save_state 19; }

rm -f "$STATE_FILE"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo ""
echo -e "${GREEN}Block $BLOCK relayed successfully${NC}"
echo "Time: ${MINS}m ${SECS}s | TXs: $TX_COUNT"
echo "https://sepolia.starkscan.co/contract/$CONTRACT"
