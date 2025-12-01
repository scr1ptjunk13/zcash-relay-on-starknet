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

// Fetch multiple recent blocks - PARALLEL version for speed
export function useRecentBlocks(count: number = 5) {
  const { contract, isConfigured } = useStarknet();
  const { data: currentHeight } = useChainHeight();

  return useQuery({
    queryKey: ["recentBlocks", currentHeight, count],
    queryFn: async (): Promise<BlockInfo[]> => {
      if (!contract || currentHeight === undefined) {
        throw new Error("Contract not ready");
      }

      const startHeight = currentHeight;
      const endHeight = Math.max(0, currentHeight - count + 1);
      const heights = [];
      for (let h = startHeight; h >= endHeight; h--) heights.push(h);

      // Step 1: Fetch all block hashes in parallel
      const hashResults = await Promise.all(
        heights.map(h => contract.get_block(h).catch(() => null))
      );

      // Filter valid blocks and prepare for status fetch
      const validBlocks: { height: number; digest: Digest; hash: string }[] = [];
      for (let i = 0; i < heights.length; i++) {
        if (!hashResults[i]) continue;
        const digest = parseDigest(hashResults[i]);
        if (isZeroDigest(digest)) continue;
        validBlocks.push({
          height: heights[i],
          digest,
          hash: digestToHex(digest),
        });
      }

      // Step 2: Fetch all statuses AND finalization states in parallel (single batch)
      const detailPromises = validBlocks.map(async (b) => {
        const digestStruct = { value: b.digest.map(v => v.toString()) };
        const [status, isFinalized] = await Promise.all([
          contract.get_status(digestStruct).catch(() => null),
          contract.is_block_finalized(digestStruct).catch(() => false),
        ]);
        return { status, isFinalized };
      });
      const detailResults = await Promise.all(detailPromises);

      // Combine results
      const blocks: BlockInfo[] = [];
      for (let i = 0; i < validBlocks.length; i++) {
        const { status, isFinalized } = detailResults[i];
        if (!status) continue;

        const { height, hash } = validBlocks[i];
        const registrationTime = Number(status.registration_timestamp || 0);
        const nTime = Number(status.n_time || 0);
        const pow = BigInt(status.pow?.toString() || "0");
        const prevDigest = parseDigest(status.prev_block_digest);

        blocks.push({
          height,
          hash,
          prevHash: digestToHex(prevDigest),
          timestamp: nTime,
          registrationTimestamp: registrationTime,
          pow,
          status: Boolean(isFinalized) ? "finalized" : "verified",
          confirmations: currentHeight - height,
          isCanonical: true,
        });
      }

      return blocks;
    },
    enabled: isConfigured && currentHeight !== undefined,
    staleTime: 30000, // Consider data fresh for 30s
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
