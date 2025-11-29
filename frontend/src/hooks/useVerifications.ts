/**
 * Hook for fetching verification timeline data
 * Reads from local JSON file (imported at build time)
 * For real-time updates, connects to backend WebSocket
 */

import { useQuery } from "@tanstack/react-query";
import { useState, useEffect } from "react";

// Import verification data directly (available at build time)
import verificationsData from "@/data/verifications.json";

export interface VerificationStep {
  step: number;
  name: string;
  txHash: string;
  time: number;
  gas?: number;
  actualFee?: number;      // Real fee in STRK
  actualFeeRaw?: string;   // Raw fee in FRI
  unit?: string;
}

export interface BlockVerification {
  verification_id: string;
  totalTime?: number;
  totalGas?: number;
  totalFee?: number;       // Real total fee in STRK
  transactions: VerificationStep[];
}

// Get verification data for a specific block
export function useBlockVerification(height: number | undefined) {
  return useQuery({
    queryKey: ["verification", height],
    queryFn: async (): Promise<BlockVerification | null> => {
      if (height === undefined) return null;
      
      const blockKey = `block_${height}` as keyof typeof verificationsData;
      const data = verificationsData[blockKey];
      
      if (data) {
        return data as BlockVerification;
      }
      
      return null;
    },
    enabled: height !== undefined,
  });
}

// Get all verifications
export function useAllVerifications() {
  return useQuery({
    queryKey: ["allVerifications"],
    queryFn: async () => {
      return verificationsData as Record<string, BlockVerification>;
    },
  });
}

// Format gas to readable string
export function formatGas(gas: number | undefined): string {
  if (gas === undefined || gas === null) return "—";
  if (gas >= 1000000) {
    return `${(gas / 1000000).toFixed(2)}M`;
  }
  if (gas >= 1000) {
    return `${(gas / 1000).toFixed(0)}K`;
  }
  return gas.toLocaleString();
}

// Calculate estimated STRK cost from gas
export function calculateStrkCost(totalGas: number | undefined): string {
  if (totalGas === undefined || totalGas === null) return "—";
  // Approximate: 1 gas ≈ 0.000000001 STRK on Sepolia
  // Total ~2.6M gas ≈ 0.0026 STRK
  const strkCost = (totalGas / 1_000_000_000) * 1;
  return strkCost.toFixed(5);
}

// WebSocket hook for real-time updates (optional - for live verification)
export function useVerificationWebSocket(
  onProgress?: (data: { height: number; step: number }) => void,
  onComplete?: (data: { height: number; success: boolean }) => void
) {
  const [connected, setConnected] = useState(false);
  
  useEffect(() => {
    // Only connect if we have callbacks
    if (!onProgress && !onComplete) return;
    
    const ws = new WebSocket('ws://localhost:3002');
    
    ws.onopen = () => {
      console.log('[WS] Connected');
      setConnected(true);
    };
    
    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'progress' && onProgress) {
          onProgress(data);
        } else if (data.type === 'complete' && onComplete) {
          onComplete(data);
        }
      } catch (err) {
        console.error('[WS] Parse error:', err);
      }
    };
    
    ws.onclose = () => {
      console.log('[WS] Disconnected');
      setConnected(false);
    };
    
    ws.onerror = (err) => {
      console.error('[WS] Error:', err);
    };
    
    return () => {
      ws.close();
    };
  }, [onProgress, onComplete]);
  
  return { connected };
}
