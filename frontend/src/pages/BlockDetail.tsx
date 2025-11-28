import { useParams, Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ArrowLeft, Copy, ExternalLink, Check } from "lucide-react";
import { useState } from "react";

const BlockDetail = () => {
  const { hashOrHeight } = useParams();
  const [copied, setCopied] = useState<string | null>(null);

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopied(id);
    setTimeout(() => setCopied(null), 2000);
  };

  // Mock data
  const block = {
    height: 2847123,
    hash: "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b",
    previousHash: "0x0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b",
    merkleRoot: "0x9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b",
    timestamp: "2025-11-28 14:23:45 UTC",
    difficulty: 21654868,
    powValue: "0x00000000000000000000000000000000000000000000000000000000ffffffff",
    status: "finalized",
    confirmations: 147,
  };

  const verificationSteps = [
    { id: 1, name: "Start Verification", tx: "0x123...", gas: 45231, status: "complete" },
    ...Array.from({ length: 16 }, (_, i) => ({
      id: i + 2,
      name: `Leaf Verification Batch ${i}`,
      tx: `0x${Math.random().toString(16).slice(2, 8)}...`,
      gas: Math.floor(Math.random() * 100000) + 50000,
      status: "complete",
    })),
    { id: 18, name: "Tree Construction", tx: "0xdef...", gas: 892441, status: "complete" },
    { id: 19, name: "Finalization", tx: "0xghi...", gas: 123456, status: "complete" },
  ];

  const totalGas = verificationSteps.reduce((sum, step) => sum + step.gas, 0);

  return (
    <div className="min-h-screen py-12 px-4">
      <div className="container mx-auto max-w-5xl">
        <Link to="/blocks">
          <Button variant="ghost" className="mb-6 gap-2">
            <ArrowLeft className="w-4 h-4" /> Back to Blocks
          </Button>
        </Link>

        <div className="flex items-center justify-between mb-8">
          <h1 className="text-4xl font-display font-bold">Block #{block.height.toLocaleString()}</h1>
          <Badge className="bg-success/10 text-success border-success/20">
            {block.status}
          </Badge>
        </div>

        {/* Block Header Card */}
        <Card className="p-6 mb-8 bg-card border-border">
          <h2 className="text-xl font-semibold mb-6">Block Header</h2>
          
          <div className="space-y-4">
            <div className="grid grid-cols-3 gap-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Height</p>
                <p className="font-mono font-semibold">{block.height.toLocaleString()}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">Confirmations</p>
                <p className="font-mono font-semibold">{block.confirmations}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">Difficulty</p>
                <p className="font-mono font-semibold">{block.difficulty.toLocaleString()}</p>
              </div>
            </div>

            <div>
              <p className="text-sm text-muted-foreground mb-1">Block Hash</p>
              <div className="flex items-center gap-2">
                <p className="font-mono text-sm break-all">{block.hash}</p>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-6 w-6 p-0"
                  onClick={() => copyToClipboard(block.hash, "hash")}
                >
                  {copied === "hash" ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
                </Button>
              </div>
            </div>

            <div>
              <p className="text-sm text-muted-foreground mb-1">Previous Hash</p>
              <Link to={`/block/${block.previousHash}`} className="flex items-center gap-2 hover:text-primary transition-colors">
                <p className="font-mono text-sm break-all">{block.previousHash}</p>
              </Link>
            </div>

            <div>
              <p className="text-sm text-muted-foreground mb-1">Merkle Root</p>
              <div className="flex items-center gap-2">
                <p className="font-mono text-sm break-all">{block.merkleRoot}</p>
                <Button
                  variant="ghost"
                  size="sm"
                  className="h-6 w-6 p-0"
                  onClick={() => copyToClipboard(block.merkleRoot, "merkle")}
                >
                  {copied === "merkle" ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
                </Button>
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Timestamp</p>
                <p className="font-mono text-sm">{block.timestamp}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">PoW Value</p>
                <p className="font-mono text-sm break-all">{block.powValue}</p>
              </div>
            </div>
          </div>
        </Card>

        {/* Verification Timeline */}
        <Card className="p-6 bg-card border-border">
          <h2 className="text-xl font-semibold mb-6">Verification Timeline</h2>
          
          <div className="space-y-4">
            {verificationSteps.map((step, index) => (
              <div key={step.id} className="flex items-start gap-4">
                <div className="flex flex-col items-center">
                  <div className="w-8 h-8 rounded-full bg-success/10 border-2 border-success flex items-center justify-center">
                    <Check className="w-4 h-4 text-success" />
                  </div>
                  {index < verificationSteps.length - 1 && (
                    <div className="w-0.5 h-8 bg-border" />
                  )}
                </div>
                
                <div className="flex-1 pb-4">
                  <div className="flex items-center justify-between mb-1">
                    <p className="font-medium">Step {step.id}: {step.name}</p>
                    <Badge variant="outline" className="font-mono text-xs">
                      {step.gas.toLocaleString()} gas
                    </Badge>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-sm text-muted-foreground">{step.tx}</span>
                    <a
                      href={`https://sepolia.starkscan.co/tx/${step.tx}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-primary hover:text-primary/80"
                    >
                      <ExternalLink className="w-3 h-3" />
                    </a>
                  </div>
                </div>
              </div>
            ))}
          </div>

          <div className="mt-6 pt-6 border-t border-border">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Total Gas Used</p>
                <p className="font-mono font-semibold text-lg">{totalGas.toLocaleString()}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">Estimated Cost</p>
                <p className="font-mono font-semibold text-lg">0.00234 ETH</p>
              </div>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
};

export default BlockDetail;
