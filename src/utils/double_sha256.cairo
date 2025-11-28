/// Double SHA-256 implementation for Zcash block headers
/// 
/// This module implements the double-SHA256 hash used in Bitcoin and Zcash
/// for block header hashing: SHA256(SHA256(data))

use crate::utils::hash::Digest;
use crate::utils::sha256::compute_sha256_u32_array;

/// Convert a u32 to 4 bytes (little-endian) for integer serialization
fn u32_to_bytes_le(val: u32) -> (u8, u8, u8, u8) {
    let byte0 = (val & 0xFF).try_into().unwrap();
    let byte1 = ((val / 0x100) & 0xFF).try_into().unwrap();
    let byte2 = ((val / 0x10000) & 0xFF).try_into().unwrap();
    let byte3 = (val / 0x1000000).try_into().unwrap();
    (byte0, byte1, byte2, byte3)
}

/// Convert a u32 to 4 bytes (big-endian) for hash serialization
fn u32_to_bytes_be(val: u32) -> (u8, u8, u8, u8) {
    let byte3 = (val & 0xFF).try_into().unwrap();
    let byte2 = ((val / 0x100) & 0xFF).try_into().unwrap();
    let byte1 = ((val / 0x10000) & 0xFF).try_into().unwrap();
    let byte0 = (val / 0x1000000).try_into().unwrap();
    (byte0, byte1, byte2, byte3)
}

/// Convert a u32 array (hash/digest) to bytes using big-endian per u32
/// This ensures consistency: SHA-256 outputs big-endian u32s, we store them as-is,
/// and serialize as big-endian to get the correct raw bytes.
fn u32_array_to_bytes(arr: [u32; 8]) -> Array<u8> {
    let mut bytes = ArrayTrait::new();
    
    // Destructure the array to access elements
    let [v0, v1, v2, v3, v4, v5, v6, v7] = arr;
    
    // Process each u32 as big-endian (consistent with SHA-256 output format)
    let (b0, b1, b2, b3) = u32_to_bytes_be(v0);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v1);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v2);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v3);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v4);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v5);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v6);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    let (b0, b1, b2, b3) = u32_to_bytes_be(v7);
    bytes.append(b0); bytes.append(b1); bytes.append(b2); bytes.append(b3);
    
    bytes
}

/// Convert a Digest to bytes for SHA-256 hashing
/// Digest stores big-endian u32s from SHA-256 output
/// We serialize each u32 as big-endian bytes (internal byte order)
fn digest_to_bytes(digest: @Digest) -> Array<u8> {
    let value_array = *digest.value;
    u32_array_to_bytes(value_array)
}

/// Convert two Digests to concatenated bytes (for parent node hashing)
fn two_digests_to_bytes(a: @Digest, b: @Digest) -> Array<u8> {
    let mut bytes = ArrayTrait::new();
    
    // Convert first digest
    let a_bytes = digest_to_bytes(a);
    let mut i: usize = 0;
    loop {
        if i >= a_bytes.len() {
            break;
        }
        bytes.append(*a_bytes[i]);
        i += 1;
    };
    
    // Convert second digest
    let b_bytes = digest_to_bytes(b);
    let mut i: usize = 0;
    loop {
        if i >= b_bytes.len() {
            break;
        }
        bytes.append(*b_bytes[i]);
        i += 1;
    };
    
    bytes
}

/// Convert bytes to Digest
/// Expects exactly 32 bytes
fn bytes_to_digest(bytes: Span<u8>) -> Digest {
    let mut value: Array<u32> = ArrayTrait::new();
    let mut i: usize = 0;
    
    loop {
        if i >= 8 {
            break;
        }
        
        let offset = i * 4;
        let byte0: u32 = (*bytes[offset]).into();
        let byte1: u32 = (*bytes[offset + 1]).into();
        let byte2: u32 = (*bytes[offset + 2]).into();
        let byte3: u32 = (*bytes[offset + 3]).into();
        
        // Reconstruct u32 in little-endian
        let val = byte0 | (byte1 * 0x100) | (byte2 * 0x10000) | (byte3 * 0x1000000);
        value.append(val);
        
        i += 1;
    };
    
    // Convert Array to fixed-size array [u32; 8]
    let value_array: [u32; 8] = [
        *value[0], *value[1], *value[2], *value[3],
        *value[4], *value[5], *value[6], *value[7]
    ];
    
    Digest { value: value_array }
}

/// Convert u32 array from SHA-256 to Digest
fn u32_array_to_digest(arr: [u32; 8]) -> Digest {
    Digest { value: arr }
}

/// Convert Array<u8> to u32 array for SHA-256 computation (Raito format)
fn array_to_u32_array(arr: @Array<u8>) -> (Array<u32>, u32, u32) {
    let mut u32_array = ArrayTrait::new();
    let len = arr.len();
    let rem = len % 4;
    let mut index: usize = 0;
    let rounded_len = len - rem;
    
    // Convert full u32 words (4 bytes each)
    while index != rounded_len {
        let word = (*arr[index + 3]).into()
            + (*arr[index + 2]).into() * 0x100
            + (*arr[index + 1]).into() * 0x10000
            + (*arr[index]).into() * 0x1000000;
        u32_array.append(word);
        index = index + 4;
    }
    
    // Handle remaining bytes
    let last_word = match rem {
        0 => 0,
        1 => (*arr[len - 1]).into(),
        2 => (*arr[len - 1]).into() + (*arr[len - 2]).into() * 0x100,
        _ => (*arr[len - 1]).into()
            + (*arr[len - 2]).into() * 0x100
            + (*arr[len - 3]).into() * 0x10000,
    };
    
    (u32_array, last_word, rem.into())
}

/// Convert Array<u8> to ByteArray for SHA-256 computation
fn array_to_byte_array(arr: @Array<u8>) -> ByteArray {
    let mut ba = "";
    let mut i: usize = 0;
    
    loop {
        if i >= arr.len() {
            break;
        }
        ba.append_byte(*arr[i]);
        i += 1;
    };
    
    ba
}

/// Convert Span<u8> to ByteArray for SHA-256 computation
fn span_to_byte_array(span: Span<u8>) -> ByteArray {
    let mut ba = "";
    let mut i: usize = 0;
    
    loop {
        if i >= span.len() {
            break;
        }
        ba.append_byte(*span[i]);
        i += 1;
    };
    
    ba
}

/// Compute double SHA-256 of two parent hashes (for Merkle tree)
pub fn double_sha256_parent(left: @Digest, right: @Digest) -> Digest {
    // Concatenate left and right digests
    let input_bytes = two_digests_to_bytes(left, right);
    
    // Convert to u32 array for hashing (Raito format)
    let (u32_array, last_word, num_bytes) = array_to_u32_array(@input_bytes);
    
    // First SHA-256 - returns [u32; 8]
    let hash1_u32 = compute_sha256_u32_array(u32_array, last_word, num_bytes);
    
    // Convert [u32; 8] to Array<u32> for second hash
    let mut hash1_array = ArrayTrait::new();
    let [h0, h1, h2, h3, h4, h5, h6, h7] = hash1_u32;
    hash1_array.append(h0); hash1_array.append(h1); hash1_array.append(h2); hash1_array.append(h3);
    hash1_array.append(h4); hash1_array.append(h5); hash1_array.append(h6); hash1_array.append(h7);
    
    // Second SHA-256 - returns [u32; 8]
    let hash2_u32 = compute_sha256_u32_array(hash1_array, 0, 0);
    
    // Convert directly to Digest
    u32_array_to_digest(hash2_u32)
}

/// Reverse byte order for Zcash/Bitcoin block hash display format
/// SHA-256 outputs big-endian, but block hashes are displayed in little-endian
fn reverse_u32_array_bytes(arr: [u32; 8]) -> [u32; 8] {
    let [v0, v1, v2, v3, v4, v5, v6, v7] = arr;
    
    // Only reverse the array order (not individual u32 bytes)
    [v7, v6, v5, v4, v3, v2, v1, v0]
}

/// Serialize Zcash block header to bytes (WITHOUT n_solution)
/// Returns exactly 140 bytes for use in Equihash verification
/// 
/// Format:
/// - nVersion (4 bytes, little-endian)
/// - hashPrevBlock (32 bytes, internal byte order)
/// - hashMerkleRoot (32 bytes, internal byte order)
/// - hashBlockCommitments (32 bytes, internal byte order)
/// - nTime (4 bytes, little-endian)
/// - nBits (4 bytes, little-endian)
/// - nNonce (32 bytes, little-endian)
pub fn serialize_header_140(
    n_version: u32,
    hash_prev_block: @Digest,
    hash_merkle_root: @Digest,
    hash_block_commitments: @Digest,
    n_time: u32,
    n_bits: u32,
    n_nonce: u256
) -> Array<u8> {
    let mut serialized = ArrayTrait::new();
    
    // 1. nVersion (4 bytes, little-endian)
    let (b0, b1, b2, b3) = u32_to_bytes_le(n_version);
    serialized.append(b0); serialized.append(b1); 
    serialized.append(b2); serialized.append(b3);
    
    // 2. hashPrevBlock (32 bytes)
    let prev_bytes = digest_to_bytes(hash_prev_block);
    let mut i: usize = 0;
    loop {
        if i >= prev_bytes.len() {
            break;
        }
        serialized.append(*prev_bytes[i]);
        i += 1;
    };
    
    // 3. hashMerkleRoot (32 bytes)
    let merkle_bytes = digest_to_bytes(hash_merkle_root);
    let mut i: usize = 0;
    loop {
        if i >= merkle_bytes.len() {
            break;
        }
        serialized.append(*merkle_bytes[i]);
        i += 1;
    };
    
    // 4. hashBlockCommitments (32 bytes)
    let commitment_bytes = digest_to_bytes(hash_block_commitments);
    let mut i: usize = 0;
    loop {
        if i >= commitment_bytes.len() {
            break;
        }
        serialized.append(*commitment_bytes[i]);
        i += 1;
    };
    
    // 5. nTime (4 bytes, little-endian)
    let (b0, b1, b2, b3) = u32_to_bytes_le(n_time);
    serialized.append(b0); serialized.append(b1); 
    serialized.append(b2); serialized.append(b3);
    
    // 6. nBits (4 bytes, little-endian)
    let (b0, b1, b2, b3) = u32_to_bytes_le(n_bits);
    serialized.append(b0); serialized.append(b1); 
    serialized.append(b2); serialized.append(b3);
    
    // 7. nNonce (32 bytes, little-endian)
    let mut nonce = n_nonce;
    let mut i: u32 = 0;
    loop {
        if i >= 32 {
            break;
        }
        serialized.append((nonce & 0xFF).try_into().unwrap());
        nonce = nonce / 256;
        i += 1;
    };
    
    serialized
}

/// Compute double SHA-256 hash of a Zcash block header
/// 
/// Serializes the header fields in the exact format used by Zcash:
/// - nVersion (4 bytes, little-endian)
/// - hashPrevBlock (32 bytes, internal byte order)
/// - hashMerkleRoot (32 bytes, internal byte order)
/// - hashBlockCommitments (32 bytes, internal byte order)
/// - nTime (4 bytes, little-endian)
/// - nBits (4 bytes, little-endian)
/// - nNonce (32 bytes, little-endian)
/// - nSolution (variable length with CompactSize prefix)
/// 
/// Returns the block hash as a Digest (reversed for display)
pub fn double_sha256_block_header(
    n_version: u32,
    hash_prev_block: @Digest,
    hash_merkle_root: @Digest,
    hash_block_commitments: @Digest,
    n_time: u32,
    n_bits: u32,
    n_nonce: u256,
    n_solution: Span<u8>
) -> Digest {
    let mut serialized = ArrayTrait::new();
    
    // 1. nVersion (4 bytes, little-endian)
    let (b0, b1, b2, b3) = u32_to_bytes_le(n_version);
    serialized.append(b0); serialized.append(b1); 
    serialized.append(b2); serialized.append(b3);
    
    // 2. hashPrevBlock (32 bytes)
    let prev_bytes = digest_to_bytes(hash_prev_block);
    let mut i: usize = 0;
    loop {
        if i >= prev_bytes.len() {
            break;
        }
        serialized.append(*prev_bytes[i]);
        i += 1;
    };
    
    // 3. hashMerkleRoot (32 bytes)
    let merkle_bytes = digest_to_bytes(hash_merkle_root);
    let mut i: usize = 0;
    loop {
        if i >= merkle_bytes.len() {
            break;
        }
        serialized.append(*merkle_bytes[i]);
        i += 1;
    };
    
    // 4. hashBlockCommitments (32 bytes)
    let commitment_bytes = digest_to_bytes(hash_block_commitments);
    let mut i: usize = 0;
    loop {
        if i >= commitment_bytes.len() {
            break;
        }
        serialized.append(*commitment_bytes[i]);
        i += 1;
    };
    
    // 5. nTime (4 bytes, little-endian)
    let (b0, b1, b2, b3) = u32_to_bytes_le(n_time);
    serialized.append(b0); serialized.append(b1); 
    serialized.append(b2); serialized.append(b3);
    
    // 6. nBits (4 bytes, little-endian)
    let (b0, b1, b2, b3) = u32_to_bytes_le(n_bits);
    serialized.append(b0); serialized.append(b1); 
    serialized.append(b2); serialized.append(b3);
    
    // 7. nNonce (32 bytes, little-endian)
    let mut nonce = n_nonce;
    let mut i: u32 = 0;
    loop {
        if i >= 32 {
            break;
        }
        serialized.append((nonce & 0xFF).try_into().unwrap());
        nonce = nonce / 0x100;
        i += 1;
    };
    
    // 8. nSolution (variable length)
    // First, add CompactSize length prefix
    let solution_len = n_solution.len();
    
    if solution_len < 0xfd {
        // Length fits in 1 byte
        serialized.append(solution_len.try_into().unwrap());
    } else if solution_len <= 0xffff {
        // Use 0xfd marker + 2 byte length
        serialized.append(0xfd);
        serialized.append((solution_len & 0xFF).try_into().unwrap());
        serialized.append(((solution_len / 0x100) & 0xFF).try_into().unwrap());
    } else {
        // For larger sizes, use 0xfe marker + 4 byte length
        serialized.append(0xfe);
        serialized.append((solution_len & 0xFF).try_into().unwrap());
        serialized.append(((solution_len / 0x100) & 0xFF).try_into().unwrap());
        serialized.append(((solution_len / 0x10000) & 0xFF).try_into().unwrap());
        serialized.append(((solution_len / 0x1000000) & 0xFF).try_into().unwrap());
    }
    
    // Add solution data
    let mut i: usize = 0;
    loop {
        if i >= solution_len {
            break;
        }
        serialized.append(*n_solution[i]);
        i += 1;
    };
    
    // Convert to u32 array for hashing (Raito format)
    let (u32_array, last_word, num_bytes) = array_to_u32_array(@serialized);
    
    // First SHA-256 - returns [u32; 8]
    let hash1_u32 = compute_sha256_u32_array(u32_array, last_word, num_bytes);
    
    // Convert [u32; 8] to Array<u32> for second hash
    let mut hash1_array = ArrayTrait::new();
    let [h0, h1, h2, h3, h4, h5, h6, h7] = hash1_u32;
    hash1_array.append(h0); hash1_array.append(h1); hash1_array.append(h2); hash1_array.append(h3);
    hash1_array.append(h4); hash1_array.append(h5); hash1_array.append(h6); hash1_array.append(h7);
    
    // Second SHA-256 - returns [u32; 8]
    let hash2_u32 = compute_sha256_u32_array(hash1_array, 0, 0);
    
    // Convert directly to Digest (test without reversal)
    u32_array_to_digest(hash2_u32)
}

#[cfg(test)]
mod tests {
    use super::{double_sha256_block_header, digest_to_bytes, bytes_to_digest, u32_array_to_bytes, u32_to_bytes_le};
    use crate::utils::hash::Digest;
    use crate::utils::hex::{hex_to_bytes_array, hex_to_hash_rev, hex_to_hash};

    #[test]
    fn test_u32_to_bytes_le() {
        let val: u32 = 0x01020304;
        let (b0, b1, b2, b3) = u32_to_bytes_le(val);
        assert_eq!(b0, 0x04, "First byte should be 0x04 (little-endian)");
        assert_eq!(b1, 0x03, "Second byte should be 0x03");
        assert_eq!(b2, 0x02, "Third byte should be 0x02");
        assert_eq!(b3, 0x01, "Fourth byte should be 0x01");
    }

    #[test]
    fn test_u32_array_to_bytes() {
        let arr: [u32; 8] = [0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10,
                             0x11121314, 0x15161718, 0x191a1b1c, 0x1d1e1f20];
        
        let bytes = u32_array_to_bytes(arr);
        assert_eq!(bytes.len(), 32, "Should produce 32 bytes");
        assert_eq!(*bytes[0], 0x04, "First byte should be 0x04 (little-endian)");
        assert_eq!(*bytes[1], 0x03, "Second byte should be 0x03");
    }

    #[test]
    fn test_digest_to_bytes() {
        let digest = Digest {
            value: [0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10,
                    0x11121314, 0x15161718, 0x191a1b1c, 0x1d1e1f20]
        };
        
        let bytes = digest_to_bytes(@digest);
        assert_eq!(bytes.len(), 32, "Should produce 32 bytes");
        assert_eq!(*bytes[0], 0x04, "First byte should be 0x04 (little-endian)");
        assert_eq!(*bytes[1], 0x03, "Second byte should be 0x03");
    }

    #[test]
    fn test_bytes_to_digest_roundtrip() {
        let original = Digest {
            value: [0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f10,
                    0x11121314, 0x15161718, 0x191a1b1c, 0x1d1e1f20]
        };
        
        let bytes = digest_to_bytes(@original);
        let recovered = bytes_to_digest(bytes.span());
        
        assert_eq!(recovered, original, "Roundtrip should preserve digest");
    }

    #[test]
    fn test_zcash_genesis_block_hash() {
        // Zcash Genesis Block (Block 0) - Verified by Python: ✓ VALID
        
        // Equihash solution (1344 bytes)
        let solution: Array<u8> = hex_to_bytes_array("000a889f00854b8665cd555f4656f68179d31ccadc1b1f7fb0952726313b16941da348284d67add4686121d4e3d930160c1348d8191c25f12b267a6a9c131b5031cbf8af1f79c9d513076a216ec87ed045fa966e01214ed83ca02dc1797270a454720d3206ac7d931a0a680c5c5e099057592570ca9bdf6058343958b31901fce1a15a4f38fd347750912e14004c73dfe588b903b6c03166582eeaf30529b14072a7b3079e3a684601b9b3024054201f7440b0ee9eb1a7120ff43f713735494aa27b1f8bab60d7f398bca14f6abb2adbf29b04099121438a7974b078a11635b594e9170f1086140b4173822dd697894483e1c6b4e8b8dcd5cb12ca4903bc61e108871d4d915a9093c18ac9b02b6716ce1013ca2c1174e319c1a570215bc9ab5f7564765f7be20524dc3fdf8aa356fd94d445e05ab165ad8bb4a0db096c097618c81098f91443c719416d39837af6de85015dca0de89462b1d8386758b2cf8a99e00953b308032ae44c35e05eb71842922eb69797f68813b59caf266cb6c213569ae3280505421a7e3a0a37fdf8e2ea354fc5422816655394a9454bac542a9298f176e211020d63dee6852c40de02267e2fc9d5e1ff2ad9309506f02a1a71a0501b16d0d36f70cdfd8de78116c0c506ee0b8ddfdeb561acadf31746b5a9dd32c21930884397fb1682164cb565cc14e089d66635a32618f7eb05fe05082b8a3fae620571660a6b89886eac53dec109d7cbb6930ca698a168f301a950be152da1be2b9e07516995e20baceebecb5579d7cdbc16d09f3a50cb3c7dffe33f26686d4ff3f8946ee6475e98cf7b3cf9062b6966e838f865ff3de5fb064a37a21da7bb8dfd2501a29e184f207caaba364f36f2329a77515dcb710e29ffbf73e2bbd773fab1f9a6b005567affff605c132e4e4dd69f36bd201005458cfbd2c658701eb2a700251cefd886b1e674ae816d3f719bac64be649c172ba27a4fd55947d95d53ba4cbc73de97b8af5ed4840b659370c556e7376457f51e5ebb66018849923db82c1c9a819f173cccdb8f3324b239609a300018d0fb094adf5bd7cbb3834c69e6d0b3798065c525b20f040e965e1a161af78ff7561cd874f5f1b75aa0bc77f720589e1b810f831eac5073e6dd46d00a2793f70f7427f0f798f2f53a67e615e65d356e66fe40609a958a05edb4c175bcc383ea0530e67ddbe479a898943c6e3074c6fcc252d6014de3a3d292b03f0d88d312fe221be7be7e3c59d07fa0f2f4029e364f1f355c5d01fa53770d0cd76d82bf7e60f6903bc1beb772e6fde4a70be51d9c7e03c8d6d8dfb361a234ba47c470fe630820bbd920715621b9fbedb49fcee165ead0875e6c2b1af16f50b5d6140cc981122fcbcf7c5a4e3772b3661b628e08380abc545957e59f634705b1bbde2f0b4e055a5ec5676d859be77e20962b645e051a880fddb0180b4555789e1f9344a436a84dc5579e2553f1e5fb0a599c137be36cabbed0319831fea3fddf94ddc7971e4bcf02cdc93294a9aab3e3b13e3b058235b4f4ec06ba4ceaa49d675b4ba80716f3bc6976b1fbf9c8bf1f3e3a4dc1cd83ef9cf816667fb94f1e923ff63fef072e6a19321e4812f96cb0ffa864da50ad74deb76917a336f31dce03ed5f0303aad5e6a83634f9fcc371096f8288b8f02ddded5ff1bb9d49331e4a84dbe1543164438fde9ad71dab024779dcdde0b6602b5ae0a6265c14b94edd83b37403f4b78fcd2ed555b596402c28ee81d87a909c4e8722b30c71ecdd861b05f61f8b1231795c76adba2fdefa451b283a5d527955b9f3de1b9828e7b2e74123dd47062ddcc09b05e7fa13cb2212a6fdbc65d7e852cec463ec6fd929f5b8483cf3052113b13dac91b69f49d1b7d1aec01c4a68e41ce157");
        
        // Block header fields (EXACT values from Python script output)
        let n_version: u32 = 4;
        let hash_prev_block = Digest { value: [0, 0, 0, 0, 0, 0, 0, 0] };
        let hash_merkle_root = Digest { value: [2239385051, 1058171063, 1277034269, 15199308, 2127737475, 3259661073, 2030575075, 3303712136] };
        let hash_block_commitments = Digest { value: [0, 0, 0, 0, 0, 0, 0, 0] };
        let n_time: u32 = 1477641360;
        let n_bits: u32 = 520617983;
        let n_nonce: u256 = 4695;
        
        // Check solution length first
        assert(solution.len() == 1344, 'Solution length wrong');
        
        // Check first few bytes of solution match Python
        assert(*solution[0] == 0x00, 'Solution byte 0 wrong');
        assert(*solution[1] == 0x0a, 'Solution byte 1 wrong');
        assert(*solution[2] == 0x88, 'Solution byte 2 wrong');
        assert(*solution[3] == 0x9f, 'Solution byte 3 wrong');
        
        // Compute block hash using double-SHA-256
        let computed_hash = double_sha256_block_header(
            n_version,
            @hash_prev_block,
            @hash_merkle_root,
            @hash_block_commitments,
            n_time,
            n_bits,
            n_nonce,
            solution.span()
        );
        
        // Expected block hash (display format - what Python shows as block_hash)
        let expected_hash = Digest { value: [147733911, 833618112, 2201503068, 2320133072, 1570860582, 2971511323, 2440135916, 3893298176] };
        
        // Verify: computed_hash == expected_hash
        assert_eq!(computed_hash, expected_hash, "Genesis block hash mismatch!");
    }

    #[test]
    fn test_zcash_block_10210_hash() {
        // Zcash Block 10210 - Verified by Python: ✓ VALID
        
        // Equihash solution (1344 bytes) - paste your solution here
        let solution: Array<u8> = hex_to_bytes_array("00deec6f4ce797775cf3818449593c0a21f7d809df2fc0c5452ae75adb9228f59e82b2f3b64c73f8df7f027d85f4a6522550f8a180f8e48bf33cade22d38ee253e74cfdb2a4987885159c68ddc3e1760eb9bc370024139d98ab5f957c7a740a618b82fc072c40e492f10a04615409f3c03280d26009161288b18983da4c6068b97f5cbf05741a0d822a75cc257b92792494ec20f1d8e7446267991b73d2715d5e434b5ee6dd3751105ce7e6e324d86e7c9cca1c5743bc739b275be21f205e751c46204b3687231a1db09407ab327227da53809f6a78c0f68bf75b4102ba0667497c3f2c3ffe1093889fec6ea12275fb75137534e675a4ebd279dba480856b5623ff75617c121f580f84eead23bc6136c4b2f5b379aced74ba5cf5e266c75f0c5be5403faaa67152116d4efb5e3cbd303b5d15f622912731efb32842dd9bca68d0f9f14c0a20a022af850b33d7b9d8f77047142a02384265177a0f7e7fade0732213559be4e3534c3de3d1b212b49957438d8d72745237bfcb3880a04d9579e5c3589c7b5637fd9f8b3310e3f904dfb2190e56fccdaa27143b7e4ffa777f24da3819112ee08a0fc72602c0ac9672390d14d7a406e626c564c5e61adbdb4339b1a35a11236551c6a2b9250afdb2e223c3e4357a997b0958c13157a88c064660b6b5a446752eba3f204d8c3a5622dd760157160c6f2825e6c06048a0f9d5819f9278c69e1c50b21e9fce6982e34e804c1090560c252507ca932e6cd541cc0efafcdffec11cb5f3dbb1e86bd4fe871ff9dbd4f5dd98436dfdf2ab00cd74028147dd0420681e2689aadfe63711e3205883e2076a5e865e631b5f24337973b20443fd1d4066124762c8cbb3daacef3daf928d819afa61e97af141404baf79ab3c3994802bb23b8d3f8e8878a36433ef76f3169db977feacb45e805bfb01629b191508a01fbebd150012d99612657040a780163321a1dddba1d8531d00fd1a3e902f2b35f845aced2492a7d171b110969a2ad50d2ceb99d74116bbf8ee2ad80bc49ee2fb9a9d17d7e083ff647e4b182402f21d31a9dcb1c1e6ee74c7252dc61aa6ae552f864418dcd54f46f8d31cddc5eb3a6b24ffe3c36784662692f56e7daf9263a2de27ad096f6df0d13c8a732e282daa80c9a0fc843b226c066d453a7060897b1ea79506bc5e23f7cd002742f7ffd5559596aad57b5bd4855669f853dd4bc288f6bd89f8d8656ea8794d6143ab4672ec57e1d761623e1a2149624b5b63fd2f2f95d1e9b19d41e07df2db2cbe37061fae3608e330a01302d767f79b76a9d07b96cc39515a555deae921f61ab0d14ff401246181add8395239131b18e9564c7103ec431b9765550551b20bda0f4d1f70d4a11a1fcdaa1ab293d08d676911e9e96e0ebd5b8259017f29060ec8f36681ff9e3a20306d4ea73488488596ca0fa58e48220adc20e920909e5e7ea9fac060bcaa4028739f623edecce753e8a1247d0de2d44a91c937211acc83c75bbd51d9fb3a913c0cee1b30aff752ebda18addfc8f5de3969971390f1b1986619ca82be20e8547de32fbfdfbd8fbfda61e4429a871f1bd6fe528e2283bbf33faabc63e96661f38b7c63c0a8cf5cbfd12c91e1f60fa4f83f98cac3a13153b805c21d53996f54b09448d39ce805e12e10400e4b6025830e13c3ba2f57d75b8eb464bff97573194dc1047af13139b6a56a488d5fd62605a55e23211e75b54ade7dee79f5ca1baa5c40870fdc89bf4d031a6ee3b261d5ff774387883f35a7e62d7ae5ffd0f081143a240e8b543a6b4c2fe2cc4c14261b3deec9147636e9e4b17925de85184ddb2bcbe354152b069670b78087da5073ee6cce6c6ae003aa1329fddb9dec1171e37f68890b015c2cc530f5a60c8f9bd52741401");
        
        // Block header fields (EXACT values from Python script output)
        let n_version: u32 = 4;
        let hash_prev_block = Digest { value: [3798252181, 517034047, 2876761304, 2751568960, 2758128899, 2520046989, 27405155, 1] };
        let hash_merkle_root = Digest { value: [3554292982, 2758696712, 1874152899, 2148339003, 4167799780, 4006405765, 2475433488, 1695737859] };
        let hash_block_commitments = Digest { value: [0, 0, 0, 0, 0, 0, 0, 0] };
        let n_time: u32 = 1479128153;
        let n_bits: u32 = 486636873;
        let n_nonce: u256 = 195551669440262;
        
        // Check solution length
        assert(solution.len() == 1344, 'Solution length wrong');
        
        // Compute block hash using double-SHA-256
        let computed_hash = double_sha256_block_header(
            n_version,
            @hash_prev_block,
            @hash_merkle_root,
            @hash_block_commitments,
            n_time,
            n_bits,
            n_nonce,
            solution.span()
        );
        
        // Expected block hash (from Python script output)
        let expected_hash = Digest { value: [4096911322, 1902337510, 863446644, 1333529587, 481413061, 1612408193, 2816059014, 0] };
        
        // Verify: computed_hash == expected_hash
        assert_eq!(computed_hash, expected_hash, "Block 10210 hash mismatch!");
    }

    #[test]
    fn test_zcash_genesis_block_hash_with_hex() {
        // Same as genesis test but using hex_to_hash instead of manual Digest values
        // This tests if hex_to_hash produces the same results as manual Digest construction
        
        // Equihash solution (1344 bytes)
        let solution: Array<u8> = hex_to_bytes_array("000a889f00854b8665cd555f4656f68179d31ccadc1b1f7fb0952726313b16941da348284d67add4686121d4e3d930160c1348d8191c25f12b267a6a9c131b5031cbf8af1f79c9d513076a216ec87ed045fa966e01214ed83ca02dc1797270a454720d3206ac7d931a0a680c5c5e099057592570ca9bdf6058343958b31901fce1a15a4f38fd347750912e14004c73dfe588b903b6c03166582eeaf30529b14072a7b3079e3a684601b9b3024054201f7440b0ee9eb1a7120ff43f713735494aa27b1f8bab60d7f398bca14f6abb2adbf29b04099121438a7974b078a11635b594e9170f1086140b4173822dd697894483e1c6b4e8b8dcd5cb12ca4903bc61e108871d4d915a9093c18ac9b02b6716ce1013ca2c1174e319c1a570215bc9ab5f7564765f7be20524dc3fdf8aa356fd94d445e05ab165ad8bb4a0db096c097618c81098f91443c719416d39837af6de85015dca0de89462b1d8386758b2cf8a99e00953b308032ae44c35e05eb71842922eb69797f68813b59caf266cb6c213569ae3280505421a7e3a0a37fdf8e2ea354fc5422816655394a9454bac542a9298f176e211020d63dee6852c40de02267e2fc9d5e1ff2ad9309506f02a1a71a0501b16d0d36f70cdfd8de78116c0c506ee0b8ddfdeb561acadf31746b5a9dd32c21930884397fb1682164cb565cc14e089d66635a32618f7eb05fe05082b8a3fae620571660a6b89886eac53dec109d7cbb6930ca698a168f301a950be152da1be2b9e07516995e20baceebecb5579d7cdbc16d09f3a50cb3c7dffe33f26686d4ff3f8946ee6475e98cf7b3cf9062b6966e838f865ff3de5fb064a37a21da7bb8dfd2501a29e184f207caaba364f36f2329a77515dcb710e29ffbf73e2bbd773fab1f9a6b005567affff605c132e4e4dd69f36bd201005458cfbd2c658701eb2a700251cefd886b1e674ae816d3f719bac64be649c172ba27a4fd55947d95d53ba4cbc73de97b8af5ed4840b659370c556e7376457f51e5ebb66018849923db82c1c9a819f173cccdb8f3324b239609a300018d0fb094adf5bd7cbb3834c69e6d0b3798065c525b20f040e965e1a161af78ff7561cd874f5f1b75aa0bc77f720589e1b810f831eac5073e6dd46d00a2793f70f7427f0f798f2f53a67e615e65d356e66fe40609a958a05edb4c175bcc383ea0530e67ddbe479a898943c6e3074c6fcc252d6014de3a3d292b03f0d88d312fe221be7be7e3c59d07fa0f2f4029e364f1f355c5d01fa53770d0cd76d82bf7e60f6903bc1beb772e6fde4a70be51d9c7e03c8d6d8dfb361a234ba47c470fe630820bbd920715621b9fbedb49fcee165ead0875e6c2b1af16f50b5d6140cc981122fcbcf7c5a4e3772b3661b628e08380abc545957e59f634705b1bbde2f0b4e055a5ec5676d859be77e20962b645e051a880fddb0180b4555789e1f9344a436a84dc5579e2553f1e5fb0a599c137be36cabbed0319831fea3fddf94ddc7971e4bcf02cdc93294a9aab3e3b13e3b058235b4f4ec06ba4ceaa49d675b4ba80716f3bc6976b1fbf9c8bf1f3e3a4dc1cd83ef9cf816667fb94f1e923ff63fef072e6a19321e4812f96cb0ffa864da50ad74deb76917a336f31dce03ed5f0303aad5e6a83634f9fcc371096f8288b8f02ddded5ff1bb9d49331e4a84dbe1543164438fde9ad71dab024779dcdde0b6602b5ae0a6265c14b94edd83b37403f4b78fcd2ed555b596402c28ee81d87a909c4e8722b30c71ecdd861b05f61f8b1231795c76adba2fdefa451b283a5d527955b9f3de1b9828e7b2e74123dd47062ddcc09b05e7fa13cb2212a6fdbc65d7e852cec463ec6fd929f5b8483cf3052113b13dac91b69f49d1b7d1aec01c4a68e41ce157");
        
        // Block header fields using hex_to_hash (from Python script output)
        let n_version: u32 = 4;
        let hash_prev_block = hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000");
        let hash_merkle_root = hex_to_hash("857a4ddb3f1268b74c1dff1d00e7ec4c7ed2b283c24a7b1179081de3c4eaa588");
        let hash_block_commitments = hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000");
        let n_time: u32 = 1477641360;
        let n_bits: u32 = 520617983;
        let n_nonce: u256 = 4695;
        
        // Compute block hash using double-SHA-256
        let computed_hash = double_sha256_block_header(
            n_version,
            @hash_prev_block,
            @hash_merkle_root,
            @hash_block_commitments,
            n_time,
            n_bits,
            n_nonce,
            solution.span()
        );
        
        // Expected block hash using hex_to_hash (from Python script output)
        let expected_hash = hex_to_hash("08ce3d9731b000c08338455c8a4a6bd05da16e26b11daa1b917184ece80f0400");
        
        // This should match the manual Digest from the other genesis test
        let manual_expected = Digest { value: [147733911, 833618112, 2201503068, 2320133072, 1570860582, 2971511323, 2440135916, 3893298176] };
        
        // Test 1: Verify hex_to_hash produces same result as manual Digest
        assert_eq!(expected_hash, manual_expected, "hex_to_hash doesn't match manual Digest!");
        
        // Test 2: Verify computed hash matches expected (same as other genesis test)
        assert_eq!(computed_hash, expected_hash, "Genesis block hash mismatch with hex_to_hash!");
    }

    #[test]
    fn test_hex_to_hash_diagnosis() {
        // Test what hex_to_hash produces vs manual construction
        
        // Test with merkle root hex - we need the INTERNAL format, not display format
        // Python gives us: [2239385051, 1058171063, 1277034269, 15199308, 2127737475, 3259661073, 2030575075, 3303712136]
        // Let's convert this to hex format that hex_to_hash expects
        let hex_merkle = "857a4ddb3f1268b74c1dff1d00e7ec4c7ed2b283c24a7b1179081de3c4eaa588";
        let from_hex = hex_to_hash(hex_merkle);
        let manual = Digest { value: [2239385051, 1058171063, 1277034269, 15199308, 2127737475, 3259661073, 2030575075, 3303712136] };
        
        // This should match now
        assert_eq!(from_hex, manual, "hex_to_hash should match manual construction!");
    }
}