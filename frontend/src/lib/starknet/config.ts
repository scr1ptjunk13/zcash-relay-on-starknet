// Starknet Configuration
// Replace CONTRACT_ADDRESS with your deployed relay contract address

export const STARKNET_CONFIG = {
  // Sepolia testnet - Alchemy RPC
  rpcUrl: import.meta.env.VITE_STARKNET_RPC_URL || "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/naxSdrGgMqQsiau6LBVoB",
  chainId: "SN_SEPOLIA" as const,
  explorerUrl: "https://sepolia.voyager.online",
  
  // Contract address - UPDATE THIS after deployment
  contractAddress: import.meta.env.VITE_RELAY_CONTRACT_ADDRESS || "",
} as const;

// Check if contract is configured
export const isContractConfigured = () => {
  return STARKNET_CONFIG.contractAddress.length > 0;
};
