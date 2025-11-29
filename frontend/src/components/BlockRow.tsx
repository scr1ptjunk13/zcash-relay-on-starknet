import { Link } from "react-router-dom";
import { ArrowRight, Copy, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useState } from "react";

interface BlockRowProps {
  height: number;
  hash: string;
  timestamp: string;
  status: "finalized" | "verified" | "pending";
}

const truncateHash = (hash: string) => {
  return `${hash.slice(0, 10)}...${hash.slice(-8)}`;
};

export const BlockRow = ({ height, hash, timestamp, status }: BlockRowProps) => {
  const [copied, setCopied] = useState(false);

  const copyHash = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    navigator.clipboard.writeText(hash);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <Link
      to={`/block/${hash}`}
      className="block p-4 border border-border/30 hover:border-border/50 transition-colors group bg-transparent"
    >
      <div className="grid grid-cols-12 gap-4 items-center">
        <div className="col-span-2">
          <span className="font-mono text-sm font-normal">{height.toLocaleString()}</span>
        </div>
        
        <div className="col-span-5 flex items-center gap-2">
          <span className="font-mono text-sm text-muted-foreground">{truncateHash(hash)}</span>
          <Button
            variant="ghost"
            size="sm"
            className="h-6 w-6 p-0 opacity-0 group-hover:opacity-100 transition-opacity hover:bg-transparent"
            onClick={copyHash}
          >
            {copied ? <Check className="h-3 w-3 text-muted-foreground" /> : <Copy className="h-3 w-3 text-muted-foreground/50" />}
          </Button>
        </div>

        <div className="col-span-3">
          <span className="text-sm text-muted-foreground">{timestamp}</span>
        </div>

        <div className="col-span-2 flex items-center justify-between">
          <span className={`text-xs ${status === 'finalized' ? 'text-success' : status === 'verified' ? 'text-primary' : 'text-muted-foreground'}`}>
            {status}
          </span>
          <ArrowRight className="w-4 h-4 text-muted-foreground/30" />
        </div>
      </div>
    </Link>
  );
};
