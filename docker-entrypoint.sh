#!/bin/bash
set -e

# Create .env file from environment variables
cat > /app/.env << EOF
ZCASH_RPC_URL=${ZCASH_RPC_URL}
ZCASH_RPC_API_KEY=${ZCASH_RPC_API_KEY}
STARKNET_RPC_URL=${STARKNET_RPC_URL}
STARKNET_ACCOUNT_ADDRESS=${STARKNET_ACCOUNT_ADDRESS}
STARKNET_PRIVATE_KEY=${STARKNET_PRIVATE_KEY}
CONTRACT_ADDRESS=${CONTRACT_ADDRESS}
EOF

# Create Starknet Foundry accounts file from environment variables
mkdir -p /root/.starknet_accounts
cat > /root/.starknet_accounts/starknet_open_zeppelin_accounts.json << EOF
{
  "testnet_account": {
    "network": "alpha-sepolia",
    "address": "${STARKNET_ACCOUNT_ADDRESS}",
    "class_hash": "0x5b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564",
    "deployed": true,
    "legacy": false,
    "private_key": "${STARKNET_PRIVATE_KEY}",
    "public_key": "${STARKNET_PUBLIC_KEY}",
    "salt": "0x5d35a7a6d49b7aff",
    "type": "OpenZeppelin"
  }
}
EOF

echo "Environment configured successfully"
echo "Starting Z.U.L.U. backend..."

# Execute the main command
exec "$@"
