// Starknet Types for Zcash Relay

import { num } from "starknet";

// Digest is a 256-bit hash stored as [u32; 8] in Cairo
export type Digest = bigint[];  // Array of 8 u32 values

// BlockStatus from the contract
export interface BlockStatus {
  registration_timestamp: bigint;
  prev_block_digest: Digest;
  pow: bigint;
  n_time: number;
}

// Block info for display
export interface BlockInfo {
  height: number;
  hash: string;
  prevHash: string;
  merkleRoot?: string;
  timestamp: number; // Unix timestamp (n_time from block header)
  registrationTimestamp: number; // When registered on Starknet
  pow: bigint;
  status: "finalized" | "verified" | "pending";
  confirmations: number;
  isCanonical: boolean;
}

// Stats for the home page
export interface RelayStats {
  currentHeight: number;
  blocksVerified: number;
  totalPow: bigint;
  avgCost: string; // Formatted string like "0.003 STRK"
}

// Helper: Convert [u32; 8] array to hex string
export function digestToHex(digest: Digest): string {
  if (!digest || digest.length !== 8) return "0x0";
  // Each u32 becomes 8 hex chars
  return "0x" + digest.map(v => 
    BigInt(v).toString(16).padStart(8, "0")
  ).join("");
}

// Helper: Convert hex string to [u32; 8] Digest
export function hexToDigest(hex: string): Digest {
  const cleanHex = hex.startsWith("0x") ? hex.slice(2) : hex;
  const padded = cleanHex.padStart(64, "0");
  const values: bigint[] = [];
  for (let i = 0; i < 64; i += 8) {
    values.push(BigInt("0x" + padded.slice(i, i + 8)));
  }
  return values;
}

// Helper: Parse contract response to Digest (8 u32 values)
// Handles both { value: [...] } struct format and direct array format
export function parseDigest(response: unknown): Digest {
  // Handle struct format: { value: [...] }
  if (response && typeof response === 'object' && 'value' in response) {
    const val = (response as { value: unknown }).value;
    if (Array.isArray(val)) {
      return val.map(v => num.toBigInt(String(v)));
    }
  }
  // Handle direct array format
  if (Array.isArray(response) && response.length === 8) {
    return response.map(v => num.toBigInt(String(v)));
  }
  // Handle flat array (some RPC responses flatten nested arrays)
  if (Array.isArray(response) && response.length > 0) {
    // Take first 8 elements
    return response.slice(0, 8).map(v => num.toBigInt(String(v)));
  }
  console.warn("parseDigest: unexpected format", response);
  return [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n];
}

// Helper: Check if digest is zero (unregistered block)
export function isZeroDigest(digest: Digest): boolean {
  if (!Array.isArray(digest)) return true;
  return digest.every(v => BigInt(v) === 0n);
}

// Helper: Format PoW for display
export function formatPow(pow: bigint): string {
  if (pow === 0n) return "0";
  
  // Convert to scientific notation for large numbers
  const powNum = Number(pow);
  if (powNum >= 1e12) {
    return (powNum / 1e12).toFixed(1) + "T";
  } else if (powNum >= 1e9) {
    return (powNum / 1e9).toFixed(1) + "B";
  } else if (powNum >= 1e6) {
    return (powNum / 1e6).toFixed(1) + "M";
  } else if (powNum >= 1e3) {
    return (powNum / 1e3).toFixed(1) + "K";
  }
  return powNum.toFixed(0);
}

// Helper: Format timestamp to relative time
export function formatTimeAgo(timestamp: number): string {
  const now = Math.floor(Date.now() / 1000);
  const diff = now - timestamp;
  
  if (diff < 60) return `${diff} sec ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)} min ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} hr ago`;
  return `${Math.floor(diff / 86400)} days ago`;
}
