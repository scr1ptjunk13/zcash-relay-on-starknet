import { useParams, Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ArrowLeft, Copy, Check, AlertCircle, CheckCircle2, ExternalLink } from "lucide-react";
import { useState } from "react";
import { useBlock, useChainHeight } from "@/hooks/useRelayContract";
import { useStarknet, formatPow } from "@/lib/starknet";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { useBlockVerification, formatGas, calculateStrkCost } from "@/hooks/useVerifications";

const BlockDetail = () => {
  const { hashOrHeight } = useParams();
  const [copied, setCopied] = useState<string | null>(null);
  
  const { isConfigured, explorerUrl } = useStarknet();
  const { data: block, isLoading, error } = useBlock(hashOrHeight);
  const { data: chainHeight } = useChainHeight();

  const copyToClipboard = (text: string, id: string) => {
    navigator.clipboard.writeText(text);
    setCopied(id);
    setTimeout(() => setCopied(null), 2000);
  };

  // Calculate confirmations
  const confirmations = block && chainHeight ? chainHeight - block.height : 0;

  // Format timestamp
  const formatTimestamp = (timestamp: number) => {
    if (!timestamp) return "—";
    return new Date(timestamp * 1000).toLocaleString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      timeZoneName: "short",
    });
  };

  if (!isConfigured) {
    return (
      <div className="min-h-screen py-12 px-4">
        <div className="container mx-auto max-w-5xl">
          <Link to="/blocks">
            <Button variant="ghost" className="mb-6 gap-2">
              <ArrowLeft className="w-4 h-4" /> Back to Blocks
            </Button>
          </Link>
          <Alert variant="default" className="border-yellow-500/50 bg-yellow-500/10">
            <AlertCircle className="h-4 w-4 text-yellow-500" />
            <AlertDescription className="text-yellow-200">
              Contract not configured. Set <code className="bg-muted px-1 rounded">VITE_RELAY_CONTRACT_ADDRESS</code> to view block details.
            </AlertDescription>
          </Alert>
        </div>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="min-h-screen py-12 px-4">
        <div className="container mx-auto max-w-5xl">
          <Link to="/blocks">
            <Button variant="ghost" className="mb-6 gap-2">
              <ArrowLeft className="w-4 h-4" /> Back to Blocks
            </Button>
          </Link>
          <div className="text-center py-12 text-muted-foreground">
            Loading block details...
          </div>
        </div>
      </div>
    );
  }

  if (error || !block) {
    return (
      <div className="min-h-screen py-12 px-4">
        <div className="container mx-auto max-w-5xl">
          <Link to="/blocks">
            <Button variant="ghost" className="mb-6 gap-2">
              <ArrowLeft className="w-4 h-4" /> Back to Blocks
            </Button>
          </Link>
          <Alert variant="destructive">
            <AlertCircle className="h-4 w-4" />
            <AlertDescription>
              Block not found. The block may not be verified yet or the hash/height is invalid.
            </AlertDescription>
          </Alert>
        </div>
      </div>
    );
  }

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
          <Badge className={block.status === "finalized" 
            ? "bg-success/10 text-success border-success/20"
            : "bg-warning/10 text-warning border-warning/20"
          }>
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
                <p className="font-mono font-semibold">{confirmations.toLocaleString()}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">PoW</p>
                <p className="font-mono font-semibold">{formatPow(block.pow)}</p>
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
              <Link to={`/block/${block.prevHash}`} className="flex items-center gap-2 hover:text-primary transition-colors">
                <p className="font-mono text-sm break-all">{block.prevHash}</p>
              </Link>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Registered At</p>
                <p className="font-mono text-sm">{formatTimestamp(block.timestamp)}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">Status</p>
                <p className="font-mono text-sm capitalize">{block.status}</p>
              </div>
            </div>
          </div>
        </Card>

        {/* Verification Timeline */}
        <VerificationTimeline height={block.height} explorerUrl={explorerUrl} />
      </div>
    </div>
  );
};

// Verification Timeline Component
function VerificationTimeline({ height, explorerUrl }: { height: number; explorerUrl: string }) {
  const { data: verification, isLoading } = useBlockVerification(height);
  const [copied, setCopied] = useState<string | null>(null);

  const copyHash = (hash: string, id: string) => {
    navigator.clipboard.writeText(hash);
    setCopied(id);
    setTimeout(() => setCopied(null), 2000);
  };

  if (isLoading) {
    return (
      <Card className="p-6 bg-card border-border">
        <h2 className="text-xl font-semibold mb-4">Verification Timeline</h2>
        <div className="text-muted-foreground">Loading...</div>
      </Card>
    );
  }

  if (!verification) {
    return (
      <Card className="p-6 bg-card border-border">
        <h2 className="text-xl font-semibold mb-4">Verification Timeline</h2>
        <div className="text-muted-foreground">No verification data available for this block.</div>
      </Card>
    );
  }

  return (
    <Card className="p-6 bg-card border-border">
      <h2 className="text-xl font-semibold mb-6">Verification Timeline</h2>
      
      <div className="space-y-3">
        {verification.transactions.map((tx, idx) => (
          <div
            key={tx.step}
            className="flex items-center justify-between p-3 border border-border/50 rounded-lg hover:border-border transition-colors"
          >
            <div className="flex items-center gap-3">
              <CheckCircle2 className="w-5 h-5 text-success" />
              <div>
                <span className="text-sm font-medium">Step {tx.step}: {tx.name}</span>
                <div className="flex items-center gap-2 mt-1">
                  <span className="font-mono text-xs text-muted-foreground">
                    {tx.txHash.slice(0, 10)}...{tx.txHash.slice(-6)}
                  </span>
                  <button
                    onClick={() => copyHash(tx.txHash, `tx-${idx}`)}
                    className="text-muted-foreground hover:text-foreground transition-colors"
                  >
                    {copied === `tx-${idx}` ? (
                      <Check className="h-3 w-3" />
                    ) : (
                      <Copy className="h-3 w-3" />
                    )}
                  </button>
                  <a
                    href={`${explorerUrl}/tx/${tx.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-muted-foreground hover:text-primary transition-colors"
                  >
                    <ExternalLink className="h-3 w-3" />
                  </a>
                </div>
              </div>
            </div>
            <div className="text-right">
              {tx.actualFee !== undefined ? (
                <span className="text-sm font-mono text-success">{tx.actualFee.toFixed(6)} STRK</span>
              ) : (
                <span className="text-sm font-mono text-muted-foreground">{formatGas(tx.gas)} gas</span>
              )}
            </div>
          </div>
        ))}
      </div>

      {/* Summary */}
      <div className="mt-6 pt-6 border-t border-border flex justify-between items-center">
        <div>
          <span className="text-sm text-muted-foreground">
            {verification.totalFee !== undefined ? "Total Cost (Real)" : "Total Gas (Est.)"}
          </span>
          <p className="text-xl font-mono font-bold">
            {verification.totalFee !== undefined 
              ? `${verification.totalFee.toFixed(6)} STRK`
              : verification.totalGas?.toLocaleString() ?? "—"}
          </p>
        </div>
        <div className="text-right">
          <span className="text-sm text-muted-foreground">Status</span>
          <p className="text-xl font-mono font-bold text-success">Verified ✓</p>
        </div>
      </div>
    </Card>
  );
}

export default BlockDetail;
