import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { CheckCircle2, XCircle, Loader2, ArrowRight, Shield, Zap } from "lucide-react";
import { useStarknet } from "@/lib/starknet";
import { zcashHashToDigest } from "@/lib/starknet/types";

interface MerkleProof {
  tx_id: string;
  block_hash: string;
  merkle_root: string;
  merkle_branch: string[];
  merkle_index: number;
  tx_count: number;
}

interface VerificationResult {
  success: boolean;
  message: string;
  txId?: string;
  blockHash?: string;
}

const Bridge = () => {
  const { contract, isConfigured } = useStarknet();
  
  // form state
  const [txId, setTxId] = useState("");
  const [blockHash, setBlockHash] = useState("");
  const [merkleProof, setMerkleProof] = useState<MerkleProof | null>(null);
  
  // ui state
  const [isLoading, setIsLoading] = useState(false);
  const [isVerifying, setIsVerifying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<VerificationResult | null>(null);

  // fetch merkle proof from backend or use manual input
  const handleFetchProof = async () => {
    if (!txId || !blockHash) {
      setError("please enter both tx id and block hash");
      return;
    }
    
    setIsLoading(true);
    setError(null);
    setMerkleProof(null);
    
    try {
      // call our backend to generate the proof (runs on port 3001)
      const backendUrl = import.meta.env.VITE_BACKEND_URL || 'http://localhost:3001';
      const response = await fetch(`${backendUrl}/api/merkle-proof?block=${encodeURIComponent(blockHash)}&txid=${encodeURIComponent(txId)}`);
      
      if (!response.ok) {
        const errData = await response.json().catch(() => ({}));
        throw new Error(errData.error || `http ${response.status}`);
      }
      
      const proof = await response.json();
      setMerkleProof(proof);
    } catch (err: any) {
      const msg = err?.message || String(err);
      if (msg.includes('fetch') || msg.includes('network')) {
        setError("backend not available. run 'npm start' in backend/ or use merkle-proof.py script offline.");
      } else {
        setError(`failed to fetch proof: ${msg}`);
      }
    } finally {
      setIsLoading(false);
    }
  };

  // verify transaction on-chain
  const handleVerify = async () => {
    if (!contract || !merkleProof) {
      setError("no proof loaded");
      return;
    }
    
    setIsVerifying(true);
    setError(null);
    setResult(null);
    
    try {
      // convert to contract format (zcash uses display format, contract uses internal)
      const blockHashDigest = zcashHashToDigest(merkleProof.block_hash);
      const txIdDigest = zcashHashToDigest(merkleProof.tx_id);
      
      // format as structs
      const blockHashStruct = { value: blockHashDigest.map(v => v.toString()) };
      const txIdStruct = { value: txIdDigest.map(v => v.toString()) };
      
      // convert merkle branch to array of digest structs
      const merkleBranchArray = merkleProof.merkle_branch.map(hash => {
        const digest = zcashHashToDigest(hash);
        return { value: digest.map(v => v.toString()) };
      });
      
      // call verify_transaction_in_block
      const verifyResult = await contract.verify_transaction_in_block(
        blockHashStruct,
        txIdStruct,
        merkleBranchArray,
        merkleProof.merkle_index
      );
      
      // check result - it returns Result<bool, RelayError>
      // if success, the result is Ok(true)
      const isValid = verifyResult === true || verifyResult?.Ok === true;
      
      setResult({
        success: isValid,
        message: isValid 
          ? "transaction verified! this zcash transaction is confirmed on starknet."
          : "verification failed - merkle proof invalid",
        txId: merkleProof.tx_id,
        blockHash: merkleProof.block_hash,
      });
      
    } catch (err: any) {
      const errMsg = err?.message || String(err);
      
      // check for specific errors
      if (errMsg.includes("BlockNotFound")) {
        setResult({
          success: false,
          message: "block not found - this block hasn't been relayed to starknet yet",
          txId: merkleProof.tx_id,
          blockHash: merkleProof.block_hash,
        });
      } else if (errMsg.includes("InvalidMerkleProof")) {
        setResult({
          success: false,
          message: "invalid merkle proof - the transaction proof doesn't match the block's merkle root",
          txId: merkleProof.tx_id,
          blockHash: merkleProof.block_hash,
        });
      } else {
        setError(`verification error: ${errMsg}`);
      }
    } finally {
      setIsVerifying(false);
    }
  };

  // handle manual proof input (paste JSON)
  const handleProofPaste = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    try {
      const proof = JSON.parse(e.target.value);
      if (proof.tx_id && proof.block_hash && proof.merkle_branch) {
        setMerkleProof(proof);
        setTxId(proof.tx_id);
        setBlockHash(proof.block_hash);
        setError(null);
      } else {
        setError("invalid proof format");
      }
    } catch {
      // not valid JSON yet, ignore
    }
  };

  return (
    <div className="min-h-screen py-8 px-4">
      <div className="container mx-auto max-w-4xl">
        
        {/* header */}
        <div className="text-center mb-8">
          <h1 className="text-2xl md:text-3xl font-normal mb-2">Transaction Verification</h1>
          <p className="text-sm text-muted-foreground">
            prove a zcash transaction exists using starknet's trustless relay
          </p>
        </div>

        {/* main flow */}
        <div className="grid gap-6">
          
          {/* step 1: input */}
          <Card>
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2">
                <span className="w-6 h-6  bg-primary/10 text-primary text-sm flex items-center justify-center">1</span>
                Enter Transaction Details
              </CardTitle>
              <CardDescription>
                provide the zcash transaction id and block hash
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <label className="text-sm text-muted-foreground mb-1 block">Transaction ID</label>
                <Input
                  placeholder="e.g. abc123def456..."
                  value={txId}
                  onChange={(e) => setTxId(e.target.value)}
                  className="font-mono text-sm"
                />
              </div>
              <div>
                <label className="text-sm text-muted-foreground mb-1 block">Block Hash (or Height)</label>
                <Input
                  placeholder="e.g. 0000000000..."
                  value={blockHash}
                  onChange={(e) => setBlockHash(e.target.value)}
                  className="font-mono text-sm"
                />
              </div>
              <Button 
                onClick={handleFetchProof} 
                disabled={isLoading || !txId || !blockHash}
                className="w-full"
              >
                {isLoading ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    Fetching Proof...
                  </>
                ) : (
                  <>
                    Generate Merkle Proof <ArrowRight className="w-4 h-4 ml-2" />
                  </>
                )}
              </Button>
              
              {/* manual proof input */}
              <div className="pt-4 border-t">
                <label className="text-sm text-muted-foreground mb-1 block">
                  Or paste proof JSON (from merkle-proof.py):
                </label>
                <textarea
                  className="w-full h-24 p-2 text-xs font-mono bg-muted border resize-none"
                  placeholder='{"tx_id": "...", "block_hash": "...", "merkle_branch": [...], "merkle_index": 0}'
                  onChange={handleProofPaste}
                />
              </div>
            </CardContent>
          </Card>

          {/* step 2: proof loaded */}
          {merkleProof && (
            <Card className="border-primary/50">
              <CardHeader>
                <CardTitle className="text-lg flex items-center gap-2">
                  <span className="w-6 h-6  bg-primary/10 text-primary text-sm flex items-center justify-center">2</span>
                  Merkle Proof Ready
                  <Badge variant="secondary" className="ml-auto">
                    {merkleProof.merkle_branch.length} levels
                  </Badge>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="grid grid-cols-2 gap-4 text-sm">
                  <div>
                    <span className="text-muted-foreground">TX Index:</span>
                    <span className="ml-2 font-mono">{merkleProof.merkle_index}</span>
                  </div>
                  <div>
                    <span className="text-muted-foreground">Total TXs:</span>
                    <span className="ml-2 font-mono">{merkleProof.tx_count}</span>
                  </div>
                </div>
                <div className="text-xs font-mono bg-muted p-2 break-all">
                  <span className="text-muted-foreground">tx: </span>
                  {merkleProof.tx_id.slice(0, 32)}...
                </div>
                
                <Button 
                  onClick={handleVerify}
                  disabled={isVerifying || !isConfigured}
                  className="w-full"
                  variant="default"
                >
                  {isVerifying ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Verifying On-Chain...
                    </>
                  ) : (
                    <>
                      <Shield className="w-4 h-4 mr-2" />
                      Verify on Starknet
                    </>
                  )}
                </Button>
                
                {!isConfigured && (
                  <p className="text-xs text-muted-foreground text-center">
                    contract not configured - set VITE_RELAY_CONTRACT_ADDRESS
                  </p>
                )}
              </CardContent>
            </Card>
          )}

          {/* error display */}
          {error && (
            <Alert variant="destructive">
              <XCircle className="w-4 h-4" />
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          {/* result display */}
          {result && (
            <Card className={result.success ? "border-green-500/50 bg-green-500/5" : "border-red-500/50 bg-red-500/5"}>
              <CardContent className="pt-6">
                <div className="flex items-start gap-4">
                  {result.success ? (
                    <CheckCircle2 className="w-8 h-8 text-green-500 flex-shrink-0" />
                  ) : (
                    <XCircle className="w-8 h-8 text-red-500 flex-shrink-0" />
                  )}
                  <div>
                    <h3 className={`font-medium ${result.success ? "text-green-400" : "text-red-400"}`}>
                      {result.success ? "✓ Transaction Verified!" : "✗ Verification Failed"}
                    </h3>
                    <p className="text-sm text-muted-foreground mt-1">
                      {result.message}
                    </p>
                    {result.txId && (
                      <p className="text-xs font-mono text-muted-foreground mt-2 break-all">
                        TX: {result.txId}
                      </p>
                    )}
                  </div>
                </div>
              </CardContent>
            </Card>
          )}

          {/* info section */}
          <Card className="bg-muted/30">
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <Zap className="w-4 h-4" />
                How It Works
              </CardTitle>
            </CardHeader>
            <CardContent className="text-sm text-muted-foreground space-y-2">
              <p>
                <strong>1. merkle proof</strong> — every zcash block contains a merkle tree of all transactions.
                the proof is the path from your tx to the root.
              </p>
              <p>
                <strong>2. on-chain verification</strong> — the relay contract stores the merkle root for each
                verified block. we recompute the root from your proof and compare.
              </p>
              <p>
                <strong>3. trustless</strong> — no oracles, no multisigs. pure cryptography.
                if the proof passes, your tx is confirmed on zcash mainnet.
              </p>
            </CardContent>
          </Card>

        </div>
      </div>
    </div>
  );
};

export default Bridge;
