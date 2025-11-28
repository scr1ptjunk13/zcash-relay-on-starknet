use snforge_std::{start_cheat_block_timestamp, stop_cheat_block_timestamp};
use crate::tests::utils::deploy_utu;
use crate::zcash::block::ZcashBlockHeader;
use crate::utils::hex::{hex_to_bytes_array, hex_to_hash};
use crate::utils::hash::Digest;
use crate::interfaces::IUtuRelayZcashDispatcherTrait;

// Helper function to verify a block through the full incremental process
fn verify_block_incremental(
    utu: @crate::interfaces::IUtuRelayZcashDispatcher,
    block: ZcashBlockHeader,
    block_name: ByteArray
) -> Digest {
    println!("");
    println!("========================================");
    println!("=== VERIFYING {} ===", block_name);
    println!("========================================");
    
    // Step 1: Start verification
    println!("Step 1: Start block verification");
    let verification_id = (*utu).start_block_verification(block);
    println!("  Verification ID = {}", verification_id);
    
    // Step 2: Verify leaves in 16 batches
    println!("Step 2: Verify leaves in 16 batches");
    let mut batch_id: u32 = 0;
    while batch_id < 16 {
        (*utu).verify_leaves_batch(verification_id, batch_id, block);
        batch_id += 1;
    };
    println!("  All 512 leaves verified!");
    
    // Step 3: Build tree
    println!("Step 3: Build Equihash tree");
    (*utu).verify_tree_all_levels(verification_id, block);
    println!("  Tree built!");
    
    // Step 4: Finalize
    println!("Step 4: Finalize verification");
    let result = (*utu).finalize_block_verification(verification_id, block);
    
    match result {
        Result::Ok(block_hash) => {
            println!("  Block finalized! Hash = {:?}", block_hash);
            block_hash
        },
        Result::Err(e) => {
            panic!("Finalization failed: {:?}", e);
        }
    }
}

// ============================================================================
// TEST: Multi-Transaction Incremental Equihash Verification
// Verifies Genesis (Block 0) and Block 1, then tests all contract queries
// ============================================================================
#[test]
fn test_incremental_equihash_verification() {
    let utu = deploy_utu();
    
    // ========================================================================
    // BLOCK 0: Genesis Block
    // ========================================================================
    let timestamp0: u32 = 1477641360;
    start_cheat_block_timestamp(utu.contract_address, timestamp0.into());
    
    let solution0: Array<u8> = hex_to_bytes_array(
        "000a889f00854b8665cd555f4656f68179d31ccadc1b1f7fb0952726313b16941da348284d67add4686121d4e3d930160c1348d8191c25f12b267a6a9c131b5031cbf8af1f79c9d513076a216ec87ed045fa966e01214ed83ca02dc1797270a454720d3206ac7d931a0a680c5c5e099057592570ca9bdf6058343958b31901fce1a15a4f38fd347750912e14004c73dfe588b903b6c03166582eeaf30529b14072a7b3079e3a684601b9b3024054201f7440b0ee9eb1a7120ff43f713735494aa27b1f8bab60d7f398bca14f6abb2adbf29b04099121438a7974b078a11635b594e9170f1086140b4173822dd697894483e1c6b4e8b8dcd5cb12ca4903bc61e108871d4d915a9093c18ac9b02b6716ce1013ca2c1174e319c1a570215bc9ab5f7564765f7be20524dc3fdf8aa356fd94d445e05ab165ad8bb4a0db096c097618c81098f91443c719416d39837af6de85015dca0de89462b1d8386758b2cf8a99e00953b308032ae44c35e05eb71842922eb69797f68813b59caf266cb6c213569ae3280505421a7e3a0a37fdf8e2ea354fc5422816655394a9454bac542a9298f176e211020d63dee6852c40de02267e2fc9d5e1ff2ad9309506f02a1a71a0501b16d0d36f70cdfd8de78116c0c506ee0b8ddfdeb561acadf31746b5a9dd32c21930884397fb1682164cb565cc14e089d66635a32618f7eb05fe05082b8a3fae620571660a6b89886eac53dec109d7cbb6930ca698a168f301a950be152da1be2b9e07516995e20baceebecb5579d7cdbc16d09f3a50cb3c7dffe33f26686d4ff3f8946ee6475e98cf7b3cf9062b6966e838f865ff3de5fb064a37a21da7bb8dfd2501a29e184f207caaba364f36f2329a77515dcb710e29ffbf73e2bbd773fab1f9a6b005567affff605c132e4e4dd69f36bd201005458cfbd2c658701eb2a700251cefd886b1e674ae816d3f719bac64be649c172ba27a4fd55947d95d53ba4cbc73de97b8af5ed4840b659370c556e7376457f51e5ebb66018849923db82c1c9a819f173cccdb8f3324b239609a300018d0fb094adf5bd7cbb3834c69e6d0b3798065c525b20f040e965e1a161af78ff7561cd874f5f1b75aa0bc77f720589e1b810f831eac5073e6dd46d00a2793f70f7427f0f798f2f53a67e615e65d356e66fe40609a958a05edb4c175bcc383ea0530e67ddbe479a898943c6e3074c6fcc252d6014de3a3d292b03f0d88d312fe221be7be7e3c59d07fa0f2f4029e364f1f355c5d01fa53770d0cd76d82bf7e60f6903bc1beb772e6fde4a70be51d9c7e03c8d6d8dfb361a234ba47c470fe630820bbd920715621b9fbedb49fcee165ead0875e6c2b1af16f50b5d6140cc981122fcbcf7c5a4e3772b3661b628e08380abc545957e59f634705b1bbde2f0b4e055a5ec5676d859be77e20962b645e051a880fddb0180b4555789e1f9344a436a84dc5579e2553f1e5fb0a599c137be36cabbed0319831fea3fddf94ddc7971e4bcf02cdc93294a9aab3e3b13e3b058235b4f4ec06ba4ceaa49d675b4ba80716f3bc6976b1fbf9c8bf1f3e3a4dc1cd83ef9cf816667fb94f1e923ff63fef072e6a19321e4812f96cb0ffa864da50ad74deb76917a336f31dce03ed5f0303aad5e6a83634f9fcc371096f8288b8f02ddded5ff1bb9d49331e4a84dbe1543164438fde9ad71dab024779dcdde0b6602b5ae0a6265c14b94edd83b37403f4b78fcd2ed555b596402c28ee81d87a909c4e8722b30c71ecdd861b05f61f8b1231795c76adba2fdefa451b283a5d527955b9f3de1b9828e7b2e74123dd47062ddcc09b05e7fa13cb2212a6fdbc65d7e852cec463ec6fd929f5b8483cf3052113b13dac91b69f49d1b7d1aec01c4a68e41ce157"
    );
    
    let block0: ZcashBlockHeader = ZcashBlockHeader {
        n_version: 4,
        hash_prev_block: hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000"),
        // Internal format: RPC merkleroot reversed
        hash_merkle_root: hex_to_hash("db4d7a85b768123f1dff1d4c4cece70083b2d27e117b4ac2e31d087988a5eac4"),
        hash_block_commitments: hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000"),
        n_time: 1477641360,
        n_bits: 520617983,
        n_nonce: 4695_u256,
        n_solution: solution0.span(),
    };
    
    let genesis_hash = verify_block_incremental(@utu, block0, "BLOCK 0 (Genesis)");
    
    // Debug: Check chain state after genesis
    println!("");
    println!("=== DEBUG: After Genesis ===");
    let height_after_genesis = utu.get_chain_height();
    let tip_after_genesis = utu.get_block(0);
    println!("Chain height after genesis: {}", height_after_genesis);
    println!("Genesis hash returned: {:?}", genesis_hash);
    println!("Block at height 0: {:?}", tip_after_genesis);
    
    // Check what block 1's prev_block should be (should match genesis_hash)
    // hex_to_hash reads big-endian, so format u32s directly as hex
    let expected_prev = hex_to_hash("08ce3d9731b000c08338455c8a4a6bd05da16e26b11daa1b917184ece80f0400");
    println!("Block 1 hash_prev_block will be: {:?}", expected_prev);
    println!("Genesis hash: {:?}", genesis_hash);
    println!("Do they match? {}", genesis_hash == expected_prev);
    
    stop_cheat_block_timestamp(utu.contract_address);
    
    // ========================================================================
    // BLOCK 1
    // ========================================================================
    let timestamp1: u32 = 1477671596;
    start_cheat_block_timestamp(utu.contract_address, timestamp1.into());
    
    // Block 1 solution (1344 bytes) - PASTE YOUR SOLUTION HERE
    let solution1: Array<u8> = hex_to_bytes_array(
        "002b2ee0d2f5d0c1ebf5a265b6f5b428f2fdc9aaea07078a6c5cab4f1bbfcd56489863deae6ea3fd8d3d0762e8e5295ff2670c9e90d8e8c68a54a40927e82a65e1d44ced20d835818e172d7b7f5ffe0245d0c3860a3f11af5658d68b6a7253b4684ffef5242fefa77a0bfc3437e8d94df9dc57510f5a128e676dd9ddf23f0ef75b460090f507499585541ab53a470c547ea02723d3a979930941157792c4362e42d3b9faca342a5c05a56909b046b5e92e2870fca7c932ae2c2fdd97d75b6e0ecb501701c1250246093c73efc5ec2838aeb80b59577741aa5ccdf4a631b79f70fc419e28714fa22108d991c29052b2f5f72294c355b57504369313470ecdd8e0ae97fc48e243a38c2ee7315bb05b7de9602047e97449c81e46746513221738dc729d7077a1771cea858865d85261e71e82003ccfbba2416358f023251206d6ef4c5596bc35b2b5bce3e9351798aa2c9904723034e5815c7512d260cc957df5db6adf9ed7272483312d1e68c60955a944e713355089876a704aef06359238f6de5a618f7bd0b4552ba72d05a6165e582f62d55ff2e1b76991971689ba3bee16a520fd85380a6e5a31de4dd4654d561101ce0ca390862d5774921eae2c284008692e9e08562144e8aa1f399a9d3fab0c4559c1f12bc945e626f7a89668613e8829767f4116ee9a4f832cf7c3ade3a7aba8cb04de39edd94d0d05093ed642adf9fbd9d373a80832ffd1c62034e4341546b3515f0e42e6d8570393c6754be5cdb7753b4709527d3f164aebf3d315934f7b3736a1b31052f6cc5699758950331163b3df05b9772e9bf99c8c77f8960e10a15edb06200106f45742d740c422c86b7e4f5a52d3732aa79ee54cfc92f76e03c268ae226477c19924e733caf95b8f350233a5312f4ed349d3ad76f032358f83a6d0d6f83b2a456742aad7f3e615fa72286300f0ea1c9793831ef3a5a4ae08640a6e32f53d1cba0be284b25e923d0d110ba227e54725632efcbbe17c05a9cde976504f6aece0c461b562cfae1b85d5f6782ee27b3e332ac0775f681682ce524b32889f1dc4231226f1aada0703beaf8d41732c9647a0a940a86f8a1be7f239c44fcaa7ed7a055506bdbe1df848f9e047226bee1b6d788a03f6e352eead99b419cfc41741942dbeb7a5c55788d5a3e636d8aab7b36b4db71d16700373bbc1cdeba8f9b1db10bf39a621bc737ea4f4e333698d6e09b51ac7a97fb6fd117ccad1d6b6b3a7451699d5bfe448650396d7b58867b3b0872be13ad0b43da267df0ad77025155f04e20c56d6a9befb3e9c7d23b82cbf3a534295ebda540682cc81be9273781b92519c858f9c25294fbacf75c3b3c15bda6d36de1c83336f93e96910dbdcb190d6ef123c98565ff6df1e903f57d4e4df167ba6b829d6d9713eb2126b0cf869940204137babcc6a1b7cb2f0b94318a7460e5d1a605c249bd2e72123ebad332332c18adcb285ed8874dbde084ebcd4f744465350d57110f037fffed1569d642c258749e65b0d13e117eaa37014a769b5ab479b7c77178880e77099f999abe712e543dbbf626ca9bcfddc42ff2f109d21c8bd464894e55ae504fdf81e1a7694180225da7dac8879abd1036cf26bb50532b8cf138b337a1a1bd1a43f8dd70b7399e2690c8e7a5a1fe099026b8f2a6f65fc0dbedda15ba65e0abd66c7176fb426980549892b4817de78e345a7aeab05744c3def4a2f283b4255b02c91c1af7354a368c67a11703c642a385c7453131ce3a78b24c5e22ab7e136a38498ce82082181884418cb4d6c2920f258a3ad20cfbe7104af1c6c6cb5e58bf29a9901721ad19c0a260cd09a3a772443a45aea4a5c439a95834ef5dc2e26343278947b7b796f796ae9bcadb29e2899a1d7313e6f7bfb6f8b"
    );
    
    let block1: ZcashBlockHeader = ZcashBlockHeader {
        n_version: 4,
        // Internal format - should match genesis hash computed by contract
        hash_prev_block: hex_to_hash("08ce3d9731b000c08338455c8a4a6bd05da16e26b11daa1b917184ece80f0400"),
        // Internal format: RPC merkleroot reversed
        hash_merkle_root: hex_to_hash("0946edb9c083c9942d92305444527765fad789c438c717783276a9f7fbf61b85"),
        hash_block_commitments: hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000"),
        n_time: 1477671596,
        n_bits: 520617983,
        n_nonce: 65287811468847057408502463983532662785575885260876759635706035709898922669173_u256,
        n_solution: solution1.span(),
    };
    
    let block1_hash = verify_block_incremental(@utu, block1, "BLOCK 1");
    
    stop_cheat_block_timestamp(utu.contract_address);
    
    // ========================================================================
    // CONTRACT QUERIES - Test all read functions
    // ========================================================================
    println!("");
    println!("========================================");
    println!("=== CONTRACT QUERY TESTS ===");
    println!("========================================");
    
    // 1. Chain height
    println!("");
    println!("=== get_chain_height ===");
    let chain_height = utu.get_chain_height();
    println!("Chain height: {}", chain_height);
    assert(chain_height == 1, 'Chain height should be 1');
    
    // 2. Get blocks
    println!("");
    println!("=== get_block ===");
    let block_at_0 = utu.get_block(0);
    let block_at_1 = utu.get_block(1);
    println!("Block at height 0: {:?}", block_at_0);
    println!("Block at height 1: {:?}", block_at_1);
    assert(block_at_0 == genesis_hash, 'Block 0 should be genesis');
    assert(block_at_1 == block1_hash, 'Block 1 should match');
    
    // 3. Finality depth
    println!("");
    println!("=== get_finality_depth ===");
    let finality_depth = utu.get_finality_depth();
    println!("Finality depth: {}", finality_depth);
    
    // 4. Block status
    println!("");
    println!("=== get_status ===");
    let status0 = utu.get_status(genesis_hash);
    let status1 = utu.get_status(block1_hash);
    println!("Genesis status - PoW: {}, time: {}", status0.pow, status0.n_time);
    println!("Block 1 status - PoW: {}, time: {}", status1.pow, status1.n_time);
    assert(status0.pow == 8192, 'Genesis PoW should be 8192');
    assert(status1.pow == 8192, 'Block 1 PoW should be 8192');
    
    // 5. Is canonical
    println!("");
    println!("=== is_block_canonical ===");
    let is_genesis_canonical = utu.is_block_canonical(genesis_hash, 0);
    let is_block1_canonical = utu.is_block_canonical(block1_hash, 1);
    println!("Genesis canonical at height 0: {}", is_genesis_canonical);
    println!("Block 1 canonical at height 1: {}", is_block1_canonical);
    assert(is_genesis_canonical, 'Genesis should be canonical');
    assert(is_block1_canonical, 'Block 1 should be canonical');
    
    // 6. Cumulative PoW
    println!("");
    println!("=== get_cumulative_pow ===");
    let cumulative_pow = utu.get_cumulative_pow(block1_hash, 100);
    println!("Cumulative PoW for block 1 (max 100 blocks): {}", cumulative_pow);
    // Genesis (8192) + Block 1 (8192) = 16384
    assert(cumulative_pow == 16384, 'Cumulative PoW should be 16384');
    
    // 7. Ancestry
    println!("");
    println!("=== get_block_ancestry ===");
    let ancestry_depth = utu.get_block_ancestry(block1_hash, 100);
    println!("Block 1 ancestry depth (max 100): {}", ancestry_depth);
    // Block 1 -> Genesis = depth of 2
    assert(ancestry_depth == 2, 'Ancestry depth should be 2');
    
    // 8. Is finalized
    println!("");
    println!("=== is_block_finalized ===");
    let is_genesis_finalized = utu.is_block_finalized(genesis_hash);
    let is_block1_finalized = utu.is_block_finalized(block1_hash);
    println!("Genesis finalized: {}", is_genesis_finalized);
    println!("Block 1 finalized: {}", is_block1_finalized);
    // With only 2 blocks and default finality depth (likely > 2), neither should be finalized
    
    println!("");
    println!("========================================");
    println!("=== ALL TESTS PASSED ===");
    println!("========================================");
    println!("- Genesis block verified and stored");
    println!("- Block 1 verified and extends chain");
    println!("- Chain height: {}", chain_height);
    println!("- All contract queries working correctly");
}

// ============================================================================
// TEST: Full End-to-End (Once Helper Functions Are Added)
// ============================================================================
#[test]
#[ignore]  // Enable once we add helper functions
fn test_full_incremental_verification_end_to_end() {
    let utu = deploy_utu();
    let timestamp: u32 = 1477641360;
    start_cheat_block_timestamp(utu.contract_address, timestamp.into());
    
    let solution: Array<u8> = hex_to_bytes_array(
        // PASTE SOLUTION HERE
        ""
    );
    
    let block: ZcashBlockHeader = ZcashBlockHeader {
        n_version: 4,
        hash_prev_block: hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000"),
        hash_merkle_root: hex_to_hash("857a4ddb3f1268b74c1dff1d00e7ec4c7ed2b283c24a7b1179081de3c4eaa588"),
        hash_block_commitments: hex_to_hash("0000000000000000000000000000000000000000000000000000000000000000"),
        n_time: 1477641360,
        n_bits: 520617983,
        n_nonce: 4695_u256,
        n_solution: solution.span(),
    };
    
    // STEP 1: Start verification
    let verification_id = utu.start_block_verification(block);
    
    // STEP 2: Verify all leaf batches (8 batches of 64 leaves each)
    let mut batch_id: u32 = 0;
    while batch_id < 8 {
        utu.verify_leaves_batch(verification_id, batch_id, block);
        batch_id += 1;
    };
    
    // STEP 3: Combine tree levels 1-9
    // TODO: This requires:
    // - Helper function: get_verification_nodes(verification_id, level) -> Array<EquihashNode>
    // - OR: Mock implementation that reconstructs nodes from stored commitments
    
    // Example pseudocode:
    // let mut level: u32 = 1;
    // while level <= 9 {
    //     let nodes = utu.get_verification_nodes(verification_id, level - 1);
    //     let parents = utu.verify_tree_levels(verification_id, nodes.span(), level);
    //     level += 1;
    // };
    
    // STEP 4: Finalize with root node
    // let root_node = parents[0];  // From level 9
    // let result = utu.finalize_block_verification(verification_id, block, root_node);
    // assert(result.is_ok(), 'Verification should succeed');
    
    // STEP 5: Verify block was registered
    // let block_hash = hex_to_hash("08ce3d9731b000c08338455c8a4a6bd05da16e26b11daa1b917184ece80f0400");
    // let status = utu.get_status(block_hash);
    // assert(status.pow == 8192, 'PoW should be 8192');
    
    stop_cheat_block_timestamp(utu.contract_address);
}
