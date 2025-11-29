// Hook for interacting with the Zcash Relay contract

import { useQuery } from "@tanstack/react-query";
import { useStarknet } from "@/lib/starknet";
import {
  Digest,
  BlockStatus,
  BlockInfo,
  digestToHex,
  hexToDigest,
  isZeroDigest,
  parseDigest,
} from "@/lib/starknet/types";

// Fetch current chain height
export function useChainHeight() {
  const { contract, isConfigured } = useStarknet();

  return useQuery({
    queryKey: ["chainHeight"],
    queryFn: async () => {
      if (!contract) throw new Error("Contract not configured");
      const result = await contract.get_chain_height();
      return Number(result);
    },
    enabled: isConfigured,
    refetchInterval: 30000, // Refetch every 30s
  });
}

// Fetch block hash at a given height
export function useBlockAtHeight(height: number | undefined) {
  const { contract, isConfigured } = useStarknet();

  return useQuery({
    queryKey: ["blockAtHeight", height],
    queryFn: async () => {
      if (!contract || height === undefined) throw new Error("Invalid params");
      const result = await contract.get_block(height);
      // Result is [u32; 8] array
      const digest = parseDigest(result);
      return digestToHex(digest);
    },
    enabled: isConfigured && height !== undefined,
  });
}

// Fetch block status by hash
export function useBlockStatus(blockHash: string | undefined) {
  const { contract, isConfigured } = useStarknet();

  return useQuery({
    queryKey: ["blockStatus", blockHash],
    queryFn: async () => {
      if (!contract || !blockHash) throw new Error("Invalid params");
      const digest = hexToDigest(blockHash);
      const digestStruct = { value: digest.map(v => v.toString()) };
      const result = await contract.get_status(digestStruct);
      
      // Parse the struct response - prev_block_digest is [u32; 8]
      const status: BlockStatus = {
        registration_timestamp: BigInt(result.registration_timestamp?.toString() || "0"),
        prev_block_digest: parseDigest(result.prev_block_digest),
        pow: BigInt(result.pow?.toString() || "0"),
        n_time: Number(result.n_time || 0),
      };
      return status;
    },
    enabled: isConfigured && !!blockHash,
  });
}

// Check if block is finalized
export function useIsBlockFinalized(blockHash: string | undefined) {
  const { contract, isConfigured } = useStarknet();

  return useQuery({
    queryKey: ["isBlockFinalized", blockHash],
    queryFn: async () => {
      if (!contract || !blockHash) throw new Error("Invalid params");
      const digest = hexToDigest(blockHash);
      const digestStruct = { value: digest.map(v => v.toString()) };
      const result = await contract.is_block_finalized(digestStruct);
      return Boolean(result);
    },
    enabled: isConfigured && !!blockHash,
  });
}

// Get cumulative PoW at height
export function useCumulativePow(height: number | undefined, maxDepth: number = 100) {
  const { contract, isConfigured } = useStarknet();

  return useQuery({
    queryKey: ["cumulativePow", height, maxDepth],
    queryFn: async () => {
      if (!contract || height === undefined) throw new Error("Invalid params");
      const result = await contract.get_cumulative_pow_at_height(height, maxDepth);
      return BigInt(result.toString());
    },
    enabled: isConfigured && height !== undefined,
  });
}

// Fetch multiple recent blocks
export function useRecentBlocks(count: number = 5) {
  const { contract, isConfigured } = useStarknet();
  const { data: currentHeight } = useChainHeight();

  return useQuery({
    queryKey: ["recentBlocks", currentHeight, count],
    queryFn: async (): Promise<BlockInfo[]> => {
      if (!contract || currentHeight === undefined) {
        throw new Error("Contract not ready");
      }

      const blocks: BlockInfo[] = [];
      const startHeight = currentHeight;
      const endHeight = Math.max(0, currentHeight - count + 1);

      for (let height = startHeight; height >= endHeight; height--) {
        try {
          // Get block hash at this height
          const hashResult = await contract.get_block(height);
          const digest = parseDigest(hashResult);

          if (isZeroDigest(digest)) continue;

          const hash = digestToHex(digest);
          
          // Format digest as struct for contract calls: { value: [...] }
          const digestStruct = { value: digest.map(v => v.toString()) };

          // Get block status
          const statusResult = await contract.get_status(digestStruct);
          const registrationTime = Number(statusResult.registration_timestamp || 0);
          const nTime = Number(statusResult.n_time || 0);
          const pow = BigInt(statusResult.pow?.toString() || "0");

          // Check if finalized
          const isFinalized = await contract.is_block_finalized(digestStruct);

          // Get prev hash
          const prevDigest = parseDigest(statusResult.prev_block_digest);

          blocks.push({
            height,
            hash,
            prevHash: digestToHex(prevDigest),
            timestamp: nTime,
            registrationTimestamp: registrationTime,
            pow,
            status: isFinalized ? "finalized" : "verified",
            confirmations: currentHeight - height,
            isCanonical: true,
          });
        } catch (err) {
          console.warn(`Failed to fetch block at height ${height}:`, err);
        }
      }

      return blocks;
    },
    enabled: isConfigured && currentHeight !== undefined,
    refetchInterval: 60000, // Refetch every minute
  });
}

// Fetch a single block by hash or height
export function useBlock(hashOrHeight: string | undefined) {
  const { contract, isConfigured } = useStarknet();
  const { data: currentHeight } = useChainHeight();

  return useQuery({
    queryKey: ["block", hashOrHeight, currentHeight],
    queryFn: async (): Promise<BlockInfo | null> => {
      if (!contract || !hashOrHeight) throw new Error("Invalid params");

      let blockHash: string;
      let height: number;

      // Check if it's a height (numeric) or hash (0x...)
      if (/^\d+$/.test(hashOrHeight)) {
        height = parseInt(hashOrHeight, 10);
        const hashResult = await contract.get_block(height);
        const digest = parseDigest(hashResult);
        if (isZeroDigest(digest)) return null;
        blockHash = digestToHex(digest);
      } else {
        blockHash = hashOrHeight.startsWith("0x") ? hashOrHeight : `0x${hashOrHeight}`;
        const digest = hexToDigest(blockHash);
        const digestStruct = { value: digest.map(v => v.toString()) };
        const heightResult = await contract.get_block_height(digestStruct);
        height = Number(heightResult);
      }

      const digest = hexToDigest(blockHash);
      const digestStruct = { value: digest.map(v => v.toString()) };
      const statusResult = await contract.get_status(digestStruct);
      const registrationTime = Number(statusResult.registration_timestamp || 0);
      const nTime = Number(statusResult.n_time || 0);

      if (registrationTime === 0 && nTime === 0) return null;

      const pow = BigInt(statusResult.pow?.toString() || "0");
      const isFinalized = await contract.is_block_finalized(digestStruct);

      const prevDigest = parseDigest(statusResult.prev_block_digest);
      const chainHeight = currentHeight ?? height;

      return {
        height,
        hash: blockHash,
        prevHash: digestToHex(prevDigest),
        timestamp: nTime,
        registrationTimestamp: registrationTime,
        pow,
        status: isFinalized ? "finalized" : "verified",
        confirmations: chainHeight - height,
        isCanonical: true,
      };
    },
    enabled: isConfigured && !!hashOrHeight,
  });
}
