#!/bin/bash
# Zcash Block Relay - Verifies Zcash blocks on Starknet
# Usage: ./relay-block.sh <height> [--resume]
# Automatically relays all blocks from current chain height to target

set +e
set +H

# Config
MAX_RETRIES=5
RETRY_DELAY=10
BATCH_DELAY=8
TOTAL_TXS=19

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Contract config
CONTRACT="0x05dba82c62d5f37161581bc0380eb98cf2a401d84e4fc5c5eb27000bf2b52ce5"
ACCOUNT="testnet_account"
NETWORK="sepolia"

# TX log file for frontend
TX_LOG_DIR="$SCRIPT_DIR/../frontend/src/data"
mkdir -p "$TX_LOG_DIR"
TX_LOG_FILE="$TX_LOG_DIR/verifications.json"

# Initialize TX log if not exists
if [ ! -f "$TX_LOG_FILE" ]; then
    echo '{}' > "$TX_LOG_FILE"
fi

[ -z "$1" ] && { echo -e "${RED}Usage:${NC} $0 <target_height> [--resume]"; exit 1; }

TARGET=$1
RESUME=false
[ "$2" = "--resume" ] && RESUME=true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Save TX to JSON log
save_tx_to_log() {
    local block=$1 step=$2 name=$3 tx_hash=$4 time=$5
    python3 -c "
import json
import os

log_file = '$TX_LOG_FILE'
block_key = 'block_$block'

# Read existing
if os.path.exists(log_file):
    with open(log_file, 'r') as f:
        data = json.load(f)
else:
    data = {}

# Initialize block if needed
if block_key not in data:
    data[block_key] = {'transactions': [], 'verification_id': ''}

# Add transaction
data[block_key]['transactions'].append({
    'step': $step,
    'name': '$name',
    'txHash': '$tx_hash',
    'time': $time
})

# Write back
with open(log_file, 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Save verification ID to log
save_vid_to_log() {
    local block=$1 vid=$2
    python3 -c "
import json
import os

log_file = '$TX_LOG_FILE'
block_key = 'block_$block'

if os.path.exists(log_file):
    with open(log_file, 'r') as f:
        data = json.load(f)
else:
    data = {}

if block_key not in data:
    data[block_key] = {'transactions': [], 'verification_id': ''}

data[block_key]['verification_id'] = '$vid'

with open(log_file, 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Invoke with retry
invoke() {
    local func=$1 calldata=$2 step=$3 desc=$4 block=$5 attempt=1
    local step_start=$(date +%s)
    
    while [ $attempt -le $MAX_RETRIES ]; do
        output=$(sncast --account $ACCOUNT invoke --contract-address $CONTRACT --function $func --calldata $calldata --network $NETWORK 2>&1)
        
        if echo "$output" | grep -q "Transaction Hash:"; then
            tx=$(echo "$output" | grep -oP 'Transaction Hash: \K0x[a-f0-9]+' | head -1)
            local step_end=$(date +%s)
            local step_time=$((step_end - step_start))
            echo -e "${GREEN}[TX $step/$TOTAL_TXS]${NC} $desc ${DIM}(${step_time}s)${NC}"
            echo -e "         ${DIM}${tx:0:18}...${tx: -8}${NC}"
            # Save full TX hash to JSON log
            save_tx_to_log "$block" "$step" "$desc" "$tx" "$step_time"
            return 0
        fi
        
        if echo "$output" | grep -qi "already\|duplicate"; then
            echo -e "${YELLOW}[TX $step/$TOTAL_TXS]${NC} $desc ${DIM}(skipped)${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}[TX $step/$TOTAL_TXS]${NC} $desc - retry $attempt/$MAX_RETRIES"
        sleep $RETRY_DELAY
        ((attempt++))
    done
    
    echo -e "${RED}[TX $step/$TOTAL_TXS]${NC} $desc ${RED}FAILED${NC}"
    return 1
}

# Relay a single block
relay_single_block() {
    local BLOCK=$1
    local STATE_FILE="$SCRIPT_DIR/.relay_state_${BLOCK}"
    local BLOCK_START=$(date +%s)
    
    echo ""
    echo -e "${BOLD}${CYAN}Block $BLOCK${NC}"
    echo -e "${DIM}─────────────────────────────────────${NC}"
    
    # Check if already verified
    BLOCK_HASH=$(sncast --account $ACCOUNT call --contract-address $CONTRACT --function get_block --calldata $BLOCK --network $NETWORK 2>&1)
    if echo "$BLOCK_HASH" | grep -qE '0x[1-9a-f]'; then
        echo -e "${GREEN}[SKIP]${NC} Already verified"
        return 0
    fi
    
    # Fetch block data
    echo -e "${BLUE}[FETCH]${NC} Fetching from Zcash..."
    HEADER=$(python scripts/format-block-calldata.py $BLOCK -v 2>/dev/null)
    if [ -z "$HEADER" ]; then
        echo -e "${RED}[ERROR]${NC} Failed to fetch block data"
        return 1
    fi
    
    # Compute verification ID
    VID=$(python scripts/compute-verification-id.py $BLOCK 2>/dev/null)
    if [ -z "$VID" ]; then
        echo -e "${RED}[ERROR]${NC} Failed to compute verification ID"
        return 1
    fi
    echo -e "${BLUE}[FETCH]${NC} VID: ${VID:0:18}..."
    # Save VID to JSON log
    save_vid_to_log "$BLOCK" "$VID"
    
    # Resume check
    LAST=0
    if [ "$RESUME" = true ] && [ -f "$STATE_FILE" ]; then
        LAST=$(head -1 "$STATE_FILE")
        source "$STATE_FILE" 2>/dev/null
        echo -e "${YELLOW}[RESUME]${NC} From TX $((LAST+1))"
    fi
    
    save_state() { echo "$1" > "$STATE_FILE"; echo "VID=$VID" >> "$STATE_FILE"; }
    
    # TX 1: Start
    if [ $LAST -lt 1 ]; then
        invoke "start_block_verification" "$HEADER" "1" "start" $BLOCK || return 1
        save_state 1
        sleep 12
    fi
    
    # TX 2-17: Batches
    FAILED=()
    for i in {0..15}; do
        step=$((i+2))
        if [ $LAST -lt $step ]; then
            if invoke "verify_leaves_batch" "$VID $i $HEADER" "$step" "batch[$i]" $BLOCK; then
                save_state $step
            else
                FAILED+=($i)
            fi
            sleep $BATCH_DELAY
        fi
    done
    
    # Retry failed
    for i in "${FAILED[@]}"; do
        step=$((i+2))
        if ! invoke "verify_leaves_batch" "$VID $i $HEADER" "$step" "batch[$i] retry" $BLOCK; then
            echo -e "${RED}[ERROR]${NC} Batch $i failed. Use --resume"
            return 1
        fi
        save_state $step
        sleep $BATCH_DELAY
    done
    
    # TX 18: Tree
    if [ $LAST -lt 18 ]; then
        invoke "verify_tree_all_levels" "$VID $HEADER" "18" "tree" $BLOCK || return 1
        save_state 18
        sleep 12
    fi
    
    # TX 19: Finalize
    if [ $LAST -lt 19 ]; then
        invoke "finalize_block_verification" "$VID $HEADER" "19" "finalize" $BLOCK || return 1
        save_state 19
    fi
    
    rm -f "$STATE_FILE"
    
    local BLOCK_END=$(date +%s)
    local BLOCK_TIME=$((BLOCK_END - BLOCK_START))
    local MINS=$((BLOCK_TIME / 60))
    local SECS=$((BLOCK_TIME % 60))
    echo -e "${GREEN}[DONE]${NC} Block $BLOCK verified ${DIM}(${MINS}m ${SECS}s)${NC}"
    
    return 0
}

# Main
echo ""
echo -e "${BOLD}${CYAN}ZCASH RELAY${NC}"
echo -e "${DIM}Target: Block $TARGET | Network: $NETWORK${NC}"
echo -e "${DIM}Contract: ${CONTRACT:0:10}...${CONTRACT: -8}${NC}"

# Get current chain height
echo -e "${BLUE}[CHECK]${NC} Getting current chain height..."
CHAIN_HEIGHT_HEX=$(sncast --account $ACCOUNT call --contract-address $CONTRACT --function get_chain_height --network $NETWORK 2>&1 | grep -oP '0x[a-f0-9]+' | head -1)

# Determine starting block
if [ -z "$CHAIN_HEIGHT_HEX" ] || [ "$CHAIN_HEIGHT_HEX" = "0x0" ]; then
    # Check if genesis exists
    GENESIS_HASH=$(sncast --account $ACCOUNT call --contract-address $CONTRACT --function get_block --calldata 0 --network $NETWORK 2>&1)
    if echo "$GENESIS_HASH" | grep -qE '0x[1-9a-f]'; then
        START_BLOCK=1
        echo -e "${BLUE}[CHECK]${NC} Genesis verified, chain height: 0"
    else
        START_BLOCK=0
        echo -e "${BLUE}[CHECK]${NC} No blocks verified yet"
    fi
else
    CURRENT_HEIGHT=$((CHAIN_HEIGHT_HEX))
    START_BLOCK=$((CURRENT_HEIGHT + 1))
    echo -e "${BLUE}[CHECK]${NC} Chain height: $CURRENT_HEIGHT"
fi

# Check if target already reached
if [ $START_BLOCK -gt $TARGET ]; then
    echo -e "${GREEN}[DONE]${NC} Block $TARGET already verified"
    echo ""
    exit 0
fi

TOTAL_BLOCKS=$((TARGET - START_BLOCK + 1))
echo -e "${BLUE}[INFO]${NC} Relaying blocks $START_BLOCK to $TARGET ($TOTAL_BLOCKS blocks)"

START_TIME=$(date +%s)
BLOCKS_DONE=0

# Relay each block sequentially
for ((BLOCK=START_BLOCK; BLOCK<=TARGET; BLOCK++)); do
    if relay_single_block $BLOCK; then
        ((BLOCKS_DONE++))
    else
        echo -e "${RED}[ERROR]${NC} Failed at block $BLOCK"
        exit 1
    fi
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo ""
echo -e "${GREEN}${BOLD}SUCCESS${NC} Relayed $BLOCKS_DONE blocks (up to #$TARGET)"
echo -e "${DIM}Total time: ${MINS}m ${SECS}s${NC}"
echo -e "${DIM}https://sepolia.starkscan.co/contract/$CONTRACT${NC}"
echo ""
