// Starknet Provider for contract interactions

import React, { createContext, useContext, useMemo } from "react";
import { RpcProvider, Contract } from "starknet";
import { STARKNET_CONFIG, isContractConfigured } from "./config";
import { RELAY_ABI } from "./abi";

interface StarknetContextValue {
  provider: RpcProvider;
  contract: Contract | null;
  isConfigured: boolean;
  explorerUrl: string;
}

const StarknetContext = createContext<StarknetContextValue | null>(null);

interface StarknetProviderProps {
  children: React.ReactNode;
}

export function StarknetProvider({ children }: StarknetProviderProps) {
  const value = useMemo(() => {
    const provider = new RpcProvider({ nodeUrl: STARKNET_CONFIG.rpcUrl });
    
    const contract = isContractConfigured()
      ? new Contract({
          abi: RELAY_ABI,
          address: STARKNET_CONFIG.contractAddress,
          providerOrAccount: provider,
        })
      : null;

    return {
      provider,
      contract,
      isConfigured: isContractConfigured(),
      explorerUrl: STARKNET_CONFIG.explorerUrl,
    };
  }, []);

  return (
    <StarknetContext.Provider value={value}>
      {children}
    </StarknetContext.Provider>
  );
}

export function useStarknet() {
  const context = useContext(StarknetContext);
  if (!context) {
    throw new Error("useStarknet must be used within StarknetProvider");
  }
  return context;
}
