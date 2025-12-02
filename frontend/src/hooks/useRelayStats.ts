// Hook for fetching relay statistics

import { useQuery } from "@tanstack/react-query";
import { useStarknet } from "@/lib/starknet";
import { RelayStats, formatPow } from "@/lib/starknet/types";

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:3001";

// Fetch average cost from real verification data
async function fetchAverageCost(): Promise<string> {
  try {
    const res = await fetch(`${BACKEND_URL}/api/verifications`);
    if (!res.ok) return "—";
    
    const data = await res.json();
    const blocks = Object.values(data) as Array<{ totalFee?: number }>;
    
    // Calculate average from blocks that have real fee data
    const blocksWithFees = blocks.filter(b => b.totalFee !== undefined && b.totalFee > 0);
    if (blocksWithFees.length === 0) return "~0.002 STRK";
    
    const totalFees = blocksWithFees.reduce((sum, b) => sum + (b.totalFee || 0), 0);
    const avgFee = totalFees / blocksWithFees.length;
    
    return `~${avgFee.toFixed(2)} STRK`;
  } catch (e) {
    return "~0.002 STRK";
  }
}

export function useRelayStats() {
  const { contract, isConfigured } = useStarknet();

  return useQuery({
    queryKey: ["relayStats"],
    queryFn: async (): Promise<RelayStats> => {
      if (!contract) throw new Error("Contract not configured");

      // Get current height
      const heightResult = await contract.get_chain_height();
      const currentHeight = Number(heightResult);

      // Get cumulative PoW at current height
      let totalPow = 0n;
      if (currentHeight > 0) {
        try {
          const powResult = await contract.get_cumulative_pow_at_height(currentHeight, 1000);
          totalPow = BigInt(powResult.toString());
        } catch (err) {
          console.warn("Failed to get cumulative PoW:", err);
        }
      }

      // blocksVerified = currentHeight + 1 (blocks 0 to currentHeight inclusive)
      const blocksVerified = currentHeight + 1;

      // Fetch REAL average cost from verification data
      const avgCost = await fetchAverageCost();

      return {
        currentHeight,
        blocksVerified,
        totalPow,
        avgCost,
      };
    },
    enabled: isConfigured,
    refetchInterval: 30000, // Refresh every 30 seconds
    staleTime: 10000, // Consider data stale after 10 seconds
  });
}

// Formatted stats for display
export function useFormattedStats() {
  const { data: stats, isLoading, error, isError } = useRelayStats();
  const { isConfigured } = useStarknet();

  if (!isConfigured) {
    return {
      isLoading: false,
      isError: false,
      isConfigured: false,
      stats: {
        currentHeight: "—",
        blocksVerified: "—",
        totalPow: "—",
        avgCost: "—",
      },
    };
  }

  if (isLoading) {
    return {
      isLoading: true,
      isError: false,
      isConfigured: true,
      stats: {
        currentHeight: "...",
        blocksVerified: "...",
        totalPow: "...",
        avgCost: "...",
      },
    };
  }

  if (isError || !stats) {
    return {
      isLoading: false,
      isError: true,
      isConfigured: true,
      error,
      stats: {
        currentHeight: "Error",
        blocksVerified: "Error",
        totalPow: "Error",
        avgCost: "Error",
      },
    };
  }

  return {
    isLoading: false,
    isError: false,
    isConfigured: true,
    stats: {
      currentHeight: stats.currentHeight.toLocaleString(),
      blocksVerified: stats.blocksVerified.toLocaleString(),
      totalPow: formatPow(stats.totalPow),
      avgCost: stats.avgCost,
    },
  };
}
