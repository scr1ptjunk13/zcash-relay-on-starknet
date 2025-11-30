// Blake2b optimized for zcash Equihash verification

// - unroll all 12 rounds (loops are expensive in cairo, who knew)
// - hardcode the sigma permutations instead of lookup tables
// - precompute the equihash init state (saves param block construction every hash)
// - cache the first block compression (the header is same for all 512 hashes!)

use core::array::ArrayTrait;
use core::num::traits::{WrappingAdd, WrappingMul};
use core::traits::{Into, TryInto};
use core::integer::u64_safe_divmod;
use core::num::traits::Zero;

pub type Blake2bDigest = Array<u8>;

const BLAKE2B_BLOCKBYTES: usize = 128;

#[derive(Copy, Drop)]
struct Blake2bParams {
    outlen: u32,
    personal: [u8; 16],
}

#[derive(Drop)]
struct Blake2bState {
    h0: u64, h1: u64, h2: u64, h3: u64, h4: u64, h5: u64, h6: u64, h7: u64,
    t0: u64,
    t1: u64,
    buf: Array<u8>,
    buflen: u32,
    outlen: u32
}

// blake2b iv constants - these are from the spec
const IV0: u64 = 0x6A09E667F3BCC908;
const IV1: u64 = 0xBB67AE8584CAA73B;
const IV2: u64 = 0x3C6EF372FE94F82B;
const IV3: u64 = 0xA54FF53A5F1D36F1;
const IV4: u64 = 0x510E527FADE682D1;
const IV5: u64 = 0x9B05688C2B3E6C1F;
const IV6: u64 = 0x1F83D9ABFB41BD6B;
const IV7: u64 = 0x5BE0CD19137E2179;

// precomputed init state for zcash equihash (n=200, k=9, outlen=50)
// this is the big brain move - instead of building param block and xoring every time,
// just precompute h[i] = IV[i] ^ param_word[i] once and hardcode it
// personalization is "ZcashPoW" + LE(200) + LE(9)

const EQUIHASH_H0: u64 = 0x6A09E667F2BDC93A; // IV0 ^ 0x01010032
const EQUIHASH_H1: u64 = 0xBB67AE8584CAA73B; // IV1 ^ 0
const EQUIHASH_H2: u64 = 0x3C6EF372FE94F82B; // IV2 ^ 0
const EQUIHASH_H3: u64 = 0xA54FF53A5F1D36F1; // IV3 ^ 0
const EQUIHASH_H4: u64 = 0x510E527FADE682D1; // IV4 ^ 0
const EQUIHASH_H5: u64 = 0x9B05688C2B3E6C1F; // IV5 ^ 0
const EQUIHASH_H6: u64 = 0x48EC89C38820DE31; // IV6 ^ "ZcashPoW"
const EQUIHASH_H7: u64 = 0x5BE0CD10137E21B1; // IV7 ^ (200 | 9<<32)
const EQUIHASH_OUTLEN: u32 = 50;


// rotation functions - blake2b needs rotr by 32, 24, 16, 63
// cairo doesnt have native rotate so we use divmod trick
// basically: rotr(x, n) = (x >> n) | (x << (64-n))
// but in felt land we do: lo = x % 2^n, hi = x / 2^n, result = lo * 2^(64-n) + hi
fn rotr64_32(x: u64) -> u64 {
    let (hi, lo) = u64_safe_divmod(x, 0x100000000_u64.try_into().unwrap());
    lo * 0x100000000_u64 + hi
}

fn rotr64_24(x: u64) -> u64 {
    let (hi, lo) = u64_safe_divmod(x, 0x1000000_u64.try_into().unwrap());
    lo * 0x10000000000_u64 + hi
}

fn rotr64_16(x: u64) -> u64 {
    let (hi, lo) = u64_safe_divmod(x, 0x10000_u64.try_into().unwrap());
    lo * 0x1000000000000_u64 + hi
}

fn rotr64_63(x: u64) -> u64 {
    let (hi_bit, lo_bits) = u64_safe_divmod(x, 0x8000000000000000_u64.try_into().unwrap());
    lo_bits.wrapping_mul(2) + hi_bit
}

// the g mixing function
// called 8 times per round, 12 rounds = 96 calls per compress
// each call does 4 adds, 4 xors, 4 rotates
fn g(va: u64, vb: u64, vc: u64, vd: u64, x: u64, y: u64) -> (u64, u64, u64, u64) {
    let t0 = va.wrapping_add(vb).wrapping_add(x);
    let t1 = rotr64_32(vd ^ t0);
    let t2 = vc.wrapping_add(t1);
    let t3 = rotr64_24(vb ^ t2);
    let t4 = t0.wrapping_add(t3).wrapping_add(y);
    let t5 = rotr64_16(t1 ^ t4);
    let t6 = t2.wrapping_add(t5);
    let t7 = rotr64_63(t3 ^ t6);
    (t4, t7, t6, t5)
}

// load 8 bytes as little-endian u64
fn load_le_u64(bytes: Span<u8>, off: usize) -> u64 {
    let b0: u64 = (*bytes[off]).into();
    let b1: u64 = (*bytes[off + 1]).into();
    let b2: u64 = (*bytes[off + 2]).into();
    let b3: u64 = (*bytes[off + 3]).into();
    let b4: u64 = (*bytes[off + 4]).into();
    let b5: u64 = (*bytes[off + 5]).into();
    let b6: u64 = (*bytes[off + 6]).into();
    let b7: u64 = (*bytes[off + 7]).into();
    
    b0 + b1 * 0x100 + b2 * 0x10000 + b3 * 0x1000000 
    + b4 * 0x100000000 + b5 * 0x10000000000 
    + b6 * 0x1000000000000 + b7 * 0x100000000000000
}

// 128 bytes of zeros for padding
fn make_zero_buf() -> Array<u8> {
    array![
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0,
    ]
}

// builds the 64-byte param block for blake2b init
// only used for generic blake2b, equihash now uses precomputed state
fn build_param_block(p: Blake2bParams) -> Array<u8> {
    let mut b = array![
        p.outlen.try_into().unwrap(), 0_u8, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ];
    for byte in p.personal.span() {
        b.append(*byte);
    }
    b
}

// generic blake2b init - xors param block with IV
fn blake2b_init(outlen: u32, personalization: [u8; 16]) -> Blake2bState {
    let params = Blake2bParams { outlen, personal: personalization };
    let param_bytes = build_param_block(params);
    let pb = param_bytes.span();

    // h[i] = IV[i] ^ LE_64(param_bytes[8*i..])
    let h0 = IV0 ^ load_le_u64(pb, 0);
    let h1 = IV1 ^ load_le_u64(pb, 8);
    let h2 = IV2 ^ load_le_u64(pb, 16);
    let h3 = IV3 ^ load_le_u64(pb, 24);
    let h4 = IV4 ^ load_le_u64(pb, 32);
    let h5 = IV5 ^ load_le_u64(pb, 40);
    let h6 = IV6 ^ load_le_u64(pb, 48);
    let h7 = IV7 ^ load_le_u64(pb, 56);

    Blake2bState {
        h0, h1, h2, h3, h4, h5, h6, h7,
        t0: 0, t1: 0, buf: make_zero_buf(), buflen: 0, outlen,
    }
}

// fast init for equihash - uses precomputed h values, skips all the param block stuff
// this alone saves mass gas when you're doing 512 hashes per block
fn blake2b_init_equihash() -> Blake2bState {
    Blake2bState {
        h0: EQUIHASH_H0,
        h1: EQUIHASH_H1,
        h2: EQUIHASH_H2,
        h3: EQUIHASH_H3,
        h4: EQUIHASH_H4,
        h5: EQUIHASH_H5,
        h6: EQUIHASH_H6,
        h7: EQUIHASH_H7,
        t0: 0,
        t1: 0,
        buf: make_zero_buf(),
        buflen: 0,
        outlen: EQUIHASH_OUTLEN,
    }
}

// the compression function
// instead of looking up sigma[round][i], we just hardcode the whole thing
fn compress(ref state: Blake2bState, block: Span<u8>, is_last: bool) {
    // load all 16 message words upfront
    let m0 = load_le_u64(block, 0);
    let m1 = load_le_u64(block, 8);
    let m2 = load_le_u64(block, 16);
    let m3 = load_le_u64(block, 24);
    let m4 = load_le_u64(block, 32);
    let m5 = load_le_u64(block, 40);
    let m6 = load_le_u64(block, 48);
    let m7 = load_le_u64(block, 56);
    let m8 = load_le_u64(block, 64);
    let m9 = load_le_u64(block, 72);
    let m10 = load_le_u64(block, 80);
    let m11 = load_le_u64(block, 88);
    let m12 = load_le_u64(block, 96);
    let m13 = load_le_u64(block, 104);
    let m14 = load_le_u64(block, 112);
    let m15 = load_le_u64(block, 120);

    // init working vector v0-v15 from state and IV
    let mut v0 = state.h0;
    let mut v1 = state.h1;
    let mut v2 = state.h2;
    let mut v3 = state.h3;
    let mut v4 = state.h4;
    let mut v5 = state.h5;
    let mut v6 = state.h6;
    let mut v7 = state.h7;
    let mut v8 = IV0;
    let mut v9 = IV1;
    let mut v10 = IV2;
    let mut v11 = IV3;
    let mut v12 = IV4 ^ state.t0;
    let mut v13 = IV5 ^ state.t1;
    let mut v14 = if is_last { IV6 ^ 0xFFFFFFFFFFFFFFFF } else { IV6 };
    let mut v15 = IV7;

    /// round 0 - sigma[0] = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m0, m1); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m2, m3); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m4, m5); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m6, m7); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m8, m9); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m10, m11); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m12, m13); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m14, m15); v3=nv3; v4=nv4; v9=nv9; v14=nv14;

    /// round 1
    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m14, m10); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m4, m8); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m9, m15); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m13, m6); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m1, m12); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m0, m2); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m11, m7); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m5, m3); v3=nv3; v4=nv4; v9=nv9; v14=nv14;

    /// round 2
    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m11, m8); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m12, m0); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m5, m2); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m15, m13); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m10, m14); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m3, m6); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m7, m1); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m9, m4); v3=nv3; v4=nv4; v9=nv9; v14=nv14;

    /// round 3
    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m7, m9); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m3, m1); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m13, m12); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m11, m14); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m2, m6); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m5, m10); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m4, m0); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m15, m8); v3=nv3; v4=nv4; v9=nv9; v14=nv14;

    /// round 4
    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m9, m0); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m5, m7); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m2, m4); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m10, m15); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m14, m1); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m11, m12); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m6, m8); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m3, m13); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    /// round 5

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m2, m12); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m6, m10); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m0, m11); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m8, m3); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m4, m13); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m7, m5); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m15, m14); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m1, m9); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    /// round 6

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m12, m5); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m1, m15); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m14, m13); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m4, m10); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m0, m7); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m6, m3); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m9, m2); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m8, m11); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    /// round 7

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m13, m11); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m7, m14); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m12, m1); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m3, m9); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m5, m0); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m15, m4); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m8, m6); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m2, m10); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    /// round 8

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m6, m15); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m14, m9); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m11, m3); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m0, m8); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m12, m2); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m13, m7); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m1, m4); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m10, m5); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    /// round 9

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m10, m2); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m8, m4); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m7, m6); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m1, m5); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m15, m11); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m9, m14); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m3, m12); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m13, m0); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    /// round 10 (same as round 0)

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m0, m1); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m2, m3); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m4, m5); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m6, m7); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m8, m9); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m10, m11); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m12, m13); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m14, m15); v3=nv3; v4=nv4; v9=nv9; v14=nv14;


    // round 11 (same as round 1)

    let (nv0, nv4, nv8, nv12) = g(v0, v4, v8, v12, m14, m10); v0=nv0; v4=nv4; v8=nv8; v12=nv12;
    let (nv1, nv5, nv9, nv13) = g(v1, v5, v9, v13, m4, m8); v1=nv1; v5=nv5; v9=nv9; v13=nv13;
    let (nv2, nv6, nv10, nv14) = g(v2, v6, v10, v14, m9, m15); v2=nv2; v6=nv6; v10=nv10; v14=nv14;
    let (nv3, nv7, nv11, nv15) = g(v3, v7, v11, v15, m13, m6); v3=nv3; v7=nv7; v11=nv11; v15=nv15;
    let (nv0, nv5, nv10, nv15) = g(v0, v5, v10, v15, m1, m12); v0=nv0; v5=nv5; v10=nv10; v15=nv15;
    let (nv1, nv6, nv11, nv12) = g(v1, v6, v11, v12, m0, m2); v1=nv1; v6=nv6; v11=nv11; v12=nv12;
    let (nv2, nv7, nv8, nv13) = g(v2, v7, v8, v13, m11, m7); v2=nv2; v7=nv7; v8=nv8; v13=nv13;
    let (nv3, nv4, nv9, nv14) = g(v3, v4, v9, v14, m5, m3); v3=nv3; v4=nv4; v9=nv9; v14=nv14;

    // Finalize h
    state.h0 = state.h0 ^ v0 ^ v8;
    state.h1 = state.h1 ^ v1 ^ v9;
    state.h2 = state.h2 ^ v2 ^ v10;
    state.h3 = state.h3 ^ v3 ^ v11;
    state.h4 = state.h4 ^ v4 ^ v12;
    state.h5 = state.h5 ^ v5 ^ v13;
    state.h6 = state.h6 ^ v6 ^ v14;
    state.h7 = state.h7 ^ v7 ^ v15;
}

// update - feed data into the hash state
fn blake2b_update(ref state: Blake2bState, input: Array<u8>) {
    let mut in_off: usize = 0;
    let in_len: usize = input.len();
    let in_span = input.span();

    if state.buflen != 0 {
        let filled: usize = state.buflen.try_into().unwrap();
        let take: usize = core::cmp::min(in_len - in_off, BLAKE2B_BLOCKBYTES - filled);

        let old_span = state.buf.span();
        let mut new_buf = array![];
        let mut idx: usize = 0;
        while idx < BLAKE2B_BLOCKBYTES {
            let v = if idx < filled {
                *old_span[idx]
            } else if idx < filled + take {
                *in_span[in_off + (idx - filled)]
            } else {
                0_u8
            };
            new_buf.append(v);
            idx += 1;
        };

        state.buf = new_buf;
        state.buflen = (filled + take).try_into().unwrap();
        in_off += take;

        if state.buflen == BLAKE2B_BLOCKBYTES.try_into().unwrap() {
            state.t0 = state.t0 + BLAKE2B_BLOCKBYTES.into();
            compress(ref state, state.buf.span(), false);
            state.buf = make_zero_buf();
            state.buflen = 0;
        }
    }

    while in_len - in_off > BLAKE2B_BLOCKBYTES {
        state.t0 = state.t0 + BLAKE2B_BLOCKBYTES.into();
        compress(ref state, in_span.slice(in_off, BLAKE2B_BLOCKBYTES), false);
        in_off += BLAKE2B_BLOCKBYTES;
    };

    let tail: usize = in_len - in_off;
    let mut new_buf_tail = array![];
    let mut i_tail: usize = 0;
    while i_tail < BLAKE2B_BLOCKBYTES {
        let v = if i_tail < tail { *in_span[in_off + i_tail] } else { 0_u8 };
        new_buf_tail.append(v);
        i_tail += 1;
    };
    state.buf = new_buf_tail;
    state.buflen = tail.try_into().unwrap();
}

// finalize - pad remaining data and do final compress
fn blake2b_finalize(ref state: Blake2bState) -> Array<u8> {
    state.t0 = state.t0 + state.buflen.into();
    compress(ref state, state.buf.span(), true);

    let mut out = array![];
    let h_arr: [u64; 8] = [state.h0, state.h1, state.h2, state.h3, state.h4, state.h5, state.h6, state.h7];
    
    let mut word_idx: usize = 0;
    while word_idx < 8 && out.len() < state.outlen.try_into().unwrap() {
        let word = *h_arr.span()[word_idx];
        let mut k: usize = 0;
        while k < 8 && out.len() < state.outlen.try_into().unwrap() {
            let divisor = if k == 0 { 1_u64 }
                else if k == 1 { 0x100 }
                else if k == 2 { 0x10000 }
                else if k == 3 { 0x1000000 }
                else if k == 4 { 0x100000000 }
                else if k == 5 { 0x10000000000 }
                else if k == 6 { 0x1000000000000 }
                else { 0x100000000000000 };
            let byte: u8 = ((word / divisor) % 256).try_into().unwrap();
            out.append(byte);
            k += 1;
        };
        word_idx += 1;
    };

    out
}

pub fn blake2b_hash(input: Array<u8>, outlen: u32, personalization: [u8; 16]) -> Blake2bDigest {
    let mut st = blake2b_init(outlen, personalization);
    blake2b_update(ref st, input);
    blake2b_finalize(ref st)
}

// fast equihash blake2b - skips param block, uses precomputed init state
// for zcash equihash with n=200, k=9. returns 50-byte hash.
pub fn blake2b_equihash(input: Array<u8>) -> Blake2bDigest {
    let mut st = blake2b_init_equihash();
    blake2b_update(ref st, input);
    blake2b_finalize(ref st)
}

// cached first block optimization
// the first 128 bytes of input (header minus last 12 bytes + index) is the same
// for all 512 hashes in a batch. so we compress it once and reuse the state.
// this cuts compress calls in half. massive gas savings.

// intermediate state after first block compression
#[derive(Drop, Clone)]
pub struct Blake2bCachedState {
    pub h0: u64, pub h1: u64, pub h2: u64, pub h3: u64,
    pub h4: u64, pub h5: u64, pub h6: u64, pub h7: u64,
}

// compress the first 128 bytes once, call this at start of batch
pub fn blake2b_equihash_compress_first(first_128: Span<u8>) -> Blake2bCachedState {
    let mut state = blake2b_init_equihash();
    state.t0 = 128;
    compress(ref state, first_128, false);
    Blake2bCachedState {
        h0: state.h0, h1: state.h1, h2: state.h2, h3: state.h3,
        h4: state.h4, h5: state.h5, h6: state.h6, h7: state.h7,
    }
}

// finish hash from cached state - takes the last 12 bytes of header + 4 byte index
// builds the final padded block and does the second compress
pub fn blake2b_equihash_finish(cached: @Blake2bCachedState, header_tail: Span<u8>, idx_bytes: Span<u8>) -> Blake2bDigest {
    // build padded final block: 12 + 4 + 112 zeros = 128 bytes
    let blk: Array<u8> = array![
        *header_tail[0], *header_tail[1], *header_tail[2], *header_tail[3],
        *header_tail[4], *header_tail[5], *header_tail[6], *header_tail[7],
        *header_tail[8], *header_tail[9], *header_tail[10], *header_tail[11],
        *idx_bytes[0], *idx_bytes[1], *idx_bytes[2], *idx_bytes[3],
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ];
    
    let mut state = Blake2bState {
        h0: *cached.h0, h1: *cached.h1, h2: *cached.h2, h3: *cached.h3,
        h4: *cached.h4, h5: *cached.h5, h6: *cached.h6, h7: *cached.h7,
        t0: 144, t1: 0, buf: array![], buflen: 0, outlen: EQUIHASH_OUTLEN,
    };
    compress(ref state, blk.span(), true);
    
    // extract 50 bytes from the final state
    extract_50_bytes(state.h0, state.h1, state.h2, state.h3, state.h4, state.h5, state.h6)
}

// extract 50 bytes from 7 u64 words - unrolled cuz loops are slow
fn extract_50_bytes(h0: u64, h1: u64, h2: u64, h3: u64, h4: u64, h5: u64, h6: u64) -> Array<u8> {
    array![
        (h0 & 0xFF).try_into().unwrap(),
        ((h0 / 0x100) & 0xFF).try_into().unwrap(),
        ((h0 / 0x10000) & 0xFF).try_into().unwrap(),
        ((h0 / 0x1000000) & 0xFF).try_into().unwrap(),
        ((h0 / 0x100000000) & 0xFF).try_into().unwrap(),
        ((h0 / 0x10000000000) & 0xFF).try_into().unwrap(),
        ((h0 / 0x1000000000000) & 0xFF).try_into().unwrap(),
        ((h0 / 0x100000000000000) & 0xFF).try_into().unwrap(),
        (h1 & 0xFF).try_into().unwrap(),
        ((h1 / 0x100) & 0xFF).try_into().unwrap(),
        ((h1 / 0x10000) & 0xFF).try_into().unwrap(),
        ((h1 / 0x1000000) & 0xFF).try_into().unwrap(),
        ((h1 / 0x100000000) & 0xFF).try_into().unwrap(),
        ((h1 / 0x10000000000) & 0xFF).try_into().unwrap(),
        ((h1 / 0x1000000000000) & 0xFF).try_into().unwrap(),
        ((h1 / 0x100000000000000) & 0xFF).try_into().unwrap(),
        (h2 & 0xFF).try_into().unwrap(),
        ((h2 / 0x100) & 0xFF).try_into().unwrap(),
        ((h2 / 0x10000) & 0xFF).try_into().unwrap(),
        ((h2 / 0x1000000) & 0xFF).try_into().unwrap(),
        ((h2 / 0x100000000) & 0xFF).try_into().unwrap(),
        ((h2 / 0x10000000000) & 0xFF).try_into().unwrap(),
        ((h2 / 0x1000000000000) & 0xFF).try_into().unwrap(),
        ((h2 / 0x100000000000000) & 0xFF).try_into().unwrap(),
        (h3 & 0xFF).try_into().unwrap(),
        ((h3 / 0x100) & 0xFF).try_into().unwrap(),
        ((h3 / 0x10000) & 0xFF).try_into().unwrap(),
        ((h3 / 0x1000000) & 0xFF).try_into().unwrap(),
        ((h3 / 0x100000000) & 0xFF).try_into().unwrap(),
        ((h3 / 0x10000000000) & 0xFF).try_into().unwrap(),
        ((h3 / 0x1000000000000) & 0xFF).try_into().unwrap(),
        ((h3 / 0x100000000000000) & 0xFF).try_into().unwrap(),
        (h4 & 0xFF).try_into().unwrap(),
        ((h4 / 0x100) & 0xFF).try_into().unwrap(),
        ((h4 / 0x10000) & 0xFF).try_into().unwrap(),
        ((h4 / 0x1000000) & 0xFF).try_into().unwrap(),
        ((h4 / 0x100000000) & 0xFF).try_into().unwrap(),
        ((h4 / 0x10000000000) & 0xFF).try_into().unwrap(),
        ((h4 / 0x1000000000000) & 0xFF).try_into().unwrap(),
        ((h4 / 0x100000000000000) & 0xFF).try_into().unwrap(),
        (h5 & 0xFF).try_into().unwrap(),
        ((h5 / 0x100) & 0xFF).try_into().unwrap(),
        ((h5 / 0x10000) & 0xFF).try_into().unwrap(),
        ((h5 / 0x1000000) & 0xFF).try_into().unwrap(),
        ((h5 / 0x100000000) & 0xFF).try_into().unwrap(),
        ((h5 / 0x10000000000) & 0xFF).try_into().unwrap(),
        ((h5 / 0x1000000000000) & 0xFF).try_into().unwrap(),
        ((h5 / 0x100000000000000) & 0xFF).try_into().unwrap(),
        (h6 & 0xFF).try_into().unwrap(),
        ((h6 / 0x100) & 0xFF).try_into().unwrap(),
    ]
}

// tests
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_blake2b_empty_64() {
        let input = array![];
        let outlen = 64_u32;
        let personalization = [0x00_u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];

        let hash = blake2b_hash(input, outlen, personalization);

        let expected: [u8; 64] = [
            120, 106, 2, 247, 66, 1, 89, 3, 198, 198, 253, 133, 37, 82, 210, 114, 145, 47, 71, 64,
            225, 88, 71, 97, 138, 134, 226, 23, 247, 31, 84, 25, 210, 94, 16, 49, 175, 238, 88, 83,
            19, 137, 100, 68, 147, 78, 176, 75, 144, 58, 104, 91, 20, 72, 183, 85, 213, 111, 112,
            26, 254, 155, 226, 206,
        ];

        assert(hash.len() == 64, 'wrong output length');
        assert_eq!(hash.span(), expected.span())
    }

    #[test]
    fn test_blake2b_8bytes_32() {
        let input = array![1_u8, 2, 3, 4, 5, 6, 7, 8];
        let outlen = 32_u32;
        let personalization = [0x00_u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];

        let hash = blake2b_hash(input, outlen, personalization);

        let expected: [u8; 32] = [
            234, 45, 75, 194, 31, 83, 25, 252, 92, 151, 178, 38, 110, 80, 35, 185, 67, 150, 205, 45,
            26, 249, 1, 186, 205, 43, 229, 150, 42, 112, 180, 229,
        ];

        assert(hash.len() == 32, 'wrong output length');
        assert_eq!(hash.span(), expected.span())
    }

    #[test]
    fn test_blake2b_equihash() {
        // test that blake2b_equihash matches blake2b_hash with equihash params
        let input = array![1_u8, 2, 3, 4, 5, 6, 7, 8];
        
        // equihash personalization: "ZcashPoW" + LE(200) + LE(9)
        let personalization: [u8; 16] = [
            0x5a, 0x63, 0x61, 0x73, 0x68, 0x50, 0x6f, 0x57,  // "ZcashPoW"
            0xc8, 0x00, 0x00, 0x00,  // LE(200)
            0x09, 0x00, 0x00, 0x00   // LE(9)
        ];
        
        let hash_regular = blake2b_hash(input.clone(), 50, personalization);
        let hash_fast = blake2b_equihash(input);
        
        assert(hash_fast.len() == 50, 'wrong equihash len');
        assert_eq!(hash_regular.span(), hash_fast.span())
    }

    #[test]
    fn test_blake2b_cached_equihash() {
        // test cached version produces same result as full version
        // simulate 144-byte equihash input (140 header + 4 index)
        let mut full_input: Array<u8> = array![];
        let mut i: usize = 0;
        while i < 144 { full_input.append((i % 256).try_into().unwrap()); i += 1; };
        
        // full hash using blake2b_equihash
        let hash_full = blake2b_equihash(full_input.clone());
        
        // cached version: first 128 bytes, then 12+4 bytes
        let span = full_input.span();
        let first_128 = span.slice(0, 128);
        let header_tail = span.slice(128, 12);  // header[128:140]
        let idx_bytes = span.slice(140, 4);     // the 4-byte index
        
        let cached = blake2b_equihash_compress_first(first_128);
        let hash_cached = blake2b_equihash_finish(@cached, header_tail, idx_bytes);
        
        assert(hash_cached.len() == 50, 'wrong cached len');
        assert_eq!(hash_full.span(), hash_cached.span())
    }
}
