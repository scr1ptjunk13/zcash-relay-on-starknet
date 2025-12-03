import { Card } from "@/components/ui/card";
import { ExternalLink, Github, Terminal, Shield, Zap, Box, CheckCircle2 } from "lucide-react";
import { STARKNET_CONFIG } from "@/lib/starknet/config";

const Docs = () => {
  const contractAddress = STARKNET_CONFIG.contractAddress || "Not configured";
  const explorerUrl = `${STARKNET_CONFIG.explorerUrl}/contract/${contractAddress}`;

  return (
    <div className="min-h-screen py-12 px-4">
      <div className="container mx-auto max-w-4xl">
        <div className="mb-8">
          <div className="flex items-center gap-3 mb-2">
            <img src="/logo.png" alt="ZULU" className="w-10 h-10" />
            <h1 className="text-4xl font-display font-bold">Z.U.L.U. Documentation</h1>
          </div>
          <p className="text-muted-foreground">
            Learn how the Zcash Universal Linking Utility works
          </p>
        </div>

        <div className="space-y-8">
          {/* Overview */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4 flex items-center gap-2">
              <Shield className="w-6 h-6 text-primary" />
              Overview
            </h2>
            <div className="space-y-4 text-muted-foreground">
              <p>
                <strong className="text-foreground">Z.U.L.U. (Zcash Universal Linking Utility)</strong> is the first trustless bridge between Zcash and Starknet, 
                using on-chain Equihash proof-of-work verification implemented in Cairo.
              </p>
              <p>
                Unlike traditional bridges that require trusted signers or multisigs, ZULU 
                verifies every block's PoW directly on Starknet using optimized Blake2b and Equihash algorithms,
                ensuring complete trustlessness and censorship resistance.
              </p>
              <div className="grid grid-cols-3 gap-4 mt-6">
                <div className="text-center p-4 bg-muted/30 ">
                  <div className="text-2xl font-bold text-primary">11</div>
                  <div className="text-xs">TXs per block</div>
                </div>
                <div className="text-center p-4 bg-muted/30 ">
                  <div className="text-2xl font-bold text-primary">512</div>
                  <div className="text-xs">Equihash indices</div>
                </div>
                <div className="text-center p-4 bg-muted/30 ">
                  <div className="text-2xl font-bold text-primary">100%</div>
                  <div className="text-xs">Trustless</div>
                </div>
              </div>
            </div>
          </Card>

          {/* How It Works */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4 flex items-center gap-2">
              <Zap className="w-6 h-6 text-primary" />
              How Block Verification Works
            </h2>
            <div className="space-y-4 text-muted-foreground">
              <p>Each Zcash block is verified through <strong className="text-foreground">11 on-chain transactions</strong>:</p>
              <ol className="space-y-3 ml-4">
                <li className="flex items-start gap-3">
                  <span className="w-6 h-6  bg-primary/20 text-primary text-xs flex items-center justify-center flex-shrink-0 mt-0.5">1</span>
                  <span><strong className="text-foreground">Initialize</strong> - Submit block header (version, prev_hash, merkle_root, time, bits, nonce)</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-6 h-6  bg-primary/20 text-primary text-xs flex items-center justify-center flex-shrink-0 mt-0.5">2-9</span>
                  <span><strong className="text-foreground">Verify Equihash</strong> - Submit 8 batches of 64 solution indices each, verifying Blake2b hashes and XOR conditions</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-6 h-6  bg-primary/20 text-primary text-xs flex items-center justify-center flex-shrink-0 mt-0.5">10</span>
                  <span><strong className="text-foreground">Finalize Equihash</strong> - Complete merkle tree construction and validate final hash meets difficulty target</span>
                </li>
                <li className="flex items-start gap-3">
                  <span className="w-6 h-6  bg-primary/20 text-primary text-xs flex items-center justify-center flex-shrink-0 mt-0.5">11</span>
                  <span><strong className="text-foreground">Add to Chain</strong> - Register block in canonical chain with cumulative PoW tracking</span>
                </li>
              </ol>
            </div>
          </Card>

          {/* Transaction Verification */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4 flex items-center gap-2">
              <CheckCircle2 className="w-6 h-6 text-primary" />
              Transaction Verification
            </h2>
            <div className="space-y-4 text-muted-foreground">
              <p>
                Once a block is verified, you can prove any transaction exists in that block using a <strong className="text-foreground">Merkle proof</strong>.
              </p>
              <div className="bg-muted/30 p-4  space-y-3">
                <p className="text-sm font-medium text-foreground">To verify a transaction:</p>
                <ol className="list-decimal list-inside space-y-2 text-sm">
                  <li>Get the block height and transaction ID from Zcash</li>
                  <li>Go to the <strong>Bridge</strong> page</li>
                  <li>Enter the TX ID and block height</li>
                  <li>Click "Generate Merkle Proof" then "Verify on Starknet"</li>
                </ol>
              </div>
              <div className="mt-4">
                <p className="text-sm font-medium text-foreground mb-2">Get transaction data using the helper script:</p>
                <pre className="bg-muted p-4  overflow-x-auto">
                  <code className="font-mono text-sm text-green-400">{`# Get all info for a verified block
python scripts/get-block-txs.py <block_height>

# Example: Get block 6 data
python scripts/get-block-txs.py 6`}</code>
                </pre>
              </div>
            </div>
          </Card>

          {/* Contract Address */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4 flex items-center gap-2">
              <Box className="w-6 h-6 text-primary" />
              Contract Address
            </h2>
            <div className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground mb-2">Starknet Sepolia Testnet</p>
                <div className="flex items-center gap-2 flex-wrap">
                  <code className="font-mono text-xs bg-muted px-3 py-2 break-all">
                    {contractAddress}
                  </code>
                  {contractAddress !== "Not configured" && (
                    <a
                      href={explorerUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-primary hover:text-primary/80 flex items-center gap-1 text-sm"
                    >
                      View on Voyager <ExternalLink className="w-3 h-3" />
                    </a>
                  )}
                </div>
              </div>
            </div>
          </Card>

          {/* Integration Guide */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4 flex items-center gap-2">
              <Terminal className="w-6 h-6 text-primary" />
              Contract Integration
            </h2>
            <div className="space-y-6">
              <div>
                <h3 className="font-semibold mb-2 text-foreground">Read Functions</h3>
                <pre className="bg-muted p-4  overflow-x-auto">
                  <code className="font-mono text-sm">{`// Get current chain height
fn get_chain_height() -> u64

// Get block hash at height
fn get_block(height: u64) -> Digest

// Check if block is finalized
fn is_block_finalized(block_hash: Digest) -> bool

// Verify a transaction exists in a block
fn verify_transaction_in_block(
    block_hash: Digest,
    tx_id: Digest,
    merkle_branch: Array<Digest>,
    merkle_index: u32
) -> Result<bool, RelayError>`}</code>
                </pre>
              </div>
              <div>
                <h3 className="font-semibold mb-2 text-foreground">JavaScript Example</h3>
                <pre className="bg-muted p-4  overflow-x-auto">
                  <code className="font-mono text-sm">{`import { Contract, RpcProvider } from 'starknet';

const provider = new RpcProvider({ nodeUrl: 'YOUR_RPC_URL' });
const contract = new Contract(ABI, CONTRACT_ADDRESS, provider);

// Get chain height
const height = await contract.get_chain_height();

// Check if block is verified
const isFinalized = await contract.is_block_finalized(blockHashDigest);`}</code>
                </pre>
              </div>
            </div>
          </Card>

          {/* Architecture */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4">Architecture</h2>
            <div className="space-y-4 text-muted-foreground">
              <div className="grid md:grid-cols-2 gap-4">
                <div className="bg-muted/30 p-4 ">
                  <h4 className="font-semibold text-foreground mb-2">Cairo Contracts</h4>
                  <ul className="text-sm space-y-1">
                    <li>- Optimized Blake2b implementation</li>
                    <li>- Equihash (200,9) verifier</li>
                    <li>- Incremental verification state</li>
                    <li>- Merkle proof verification</li>
                  </ul>
                </div>
                <div className="bg-muted/30 p-4 ">
                  <h4 className="font-semibold text-foreground mb-2">Relay Infrastructure</h4>
                  <ul className="text-sm space-y-1">
                    <li>- Zcash RPC integration</li>
                    <li>- Block header parsing</li>
                    <li>- Solution index extraction</li>
                    <li>- Automated batch submission</li>
                  </ul>
                </div>
              </div>
            </div>
          </Card>

          {/* Links */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4">Resources</h2>
            <div className="flex flex-wrap gap-4">
              <a
                href="https://github.com/scr1ptjunk13/zcash-relay-on-starknet"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 px-4 py-2 bg-muted  hover:bg-muted/80 transition-colors"
              >
                <Github className="w-5 h-5" />
                <span>GitHub Repository</span>
              </a>
              <a
                href="https://z.cash/technology/equihash/"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 px-4 py-2 bg-muted  hover:bg-muted/80 transition-colors"
              >
                <ExternalLink className="w-4 h-4" />
                <span>Equihash Paper</span>
              </a>
              <a
                href="https://docs.starknet.io/"
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-2 px-4 py-2 bg-muted  hover:bg-muted/80 transition-colors"
              >
                <ExternalLink className="w-4 h-4" />
                <span>Starknet Docs</span>
              </a>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default Docs;
