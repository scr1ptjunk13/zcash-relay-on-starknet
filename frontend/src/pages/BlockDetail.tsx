import { useParams, Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { ArrowLeft, Copy, Check, AlertCircle } from "lucide-react";
import { useState } from "react";
import { useBlock, useChainHeight } from "@/hooks/useRelayContract";
import { useStarknet, formatPow } from "@/lib/starknet";
import { Alert, AlertDescription } from "@/components/ui/alert";

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

        {/* Explorer Link */}
        <Card className="p-6 bg-card border-border">
          <h2 className="text-xl font-semibold mb-4">External Links</h2>
          <div className="flex gap-4">
            <a
              href={`${explorerUrl}/contract/${block.hash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-primary hover:text-primary/80 text-sm underline"
            >
              View on Starkscan →
            </a>
          </div>
        </Card>
      </div>
    </div>
  );
};

export default BlockDetail;
