import { useState } from "react";
import { Search, AlertCircle } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { BlockRow } from "@/components/BlockRow";
import { useNavigate } from "react-router-dom";
import { useRecentBlocks, useChainHeight } from "@/hooks/useRelayContract";
import { useStarknet, formatTimeAgo } from "@/lib/starknet";
import { Alert, AlertDescription } from "@/components/ui/alert";

const BLOCKS_PER_PAGE = 20;

const Blocks = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const [page, setPage] = useState(0);
  const navigate = useNavigate();
  
  const { isConfigured } = useStarknet();
  const { data: chainHeight } = useChainHeight();
  const { data: blocks, isLoading } = useRecentBlocks(BLOCKS_PER_PAGE);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/block/${searchQuery}`);
    }
  };

  const totalBlocks = chainHeight || 0;
  const startBlock = page * BLOCKS_PER_PAGE + 1;
  const endBlock = Math.min(startBlock + BLOCKS_PER_PAGE - 1, totalBlocks);
  const hasNextPage = endBlock < totalBlocks;
  const hasPrevPage = page > 0;

  return (
    <div className="min-h-screen py-12 px-4">
      <div className="container mx-auto">
        <div className="mb-8">
          <h1 className="text-4xl font-display font-bold mb-2">Block Explorer</h1>
          <p className="text-muted-foreground">
            Browse all verified Zcash blocks on Starknet
          </p>
        </div>

        {/* Contract Not Configured Warning */}
        {!isConfigured && (
          <Alert variant="default" className="mb-6 border-yellow-500/50 bg-yellow-500/10">
            <AlertCircle className="h-4 w-4 text-yellow-500" />
            <AlertDescription className="text-yellow-200">
              Contract not configured. Set <code className="bg-muted px-1 rounded">VITE_RELAY_CONTRACT_ADDRESS</code> to view blocks.
            </AlertDescription>
          </Alert>
        )}

        {/* Search Bar */}
        <form onSubmit={handleSearch} className="mb-8">
          <div className="relative max-w-2xl">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-5 h-5 text-muted-foreground" />
            <Input
              type="text"
              placeholder="Search by block height or hash..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10 h-12 bg-card border-border"
            />
          </div>
        </form>

        {/* Table Header */}
        <div className="grid grid-cols-12 gap-4 px-4 py-3 border-b border-border mb-4">
          <div className="col-span-2 text-sm font-medium text-muted-foreground">Height</div>
          <div className="col-span-5 text-sm font-medium text-muted-foreground">Hash</div>
          <div className="col-span-3 text-sm font-medium text-muted-foreground">Verified At</div>
          <div className="col-span-2 text-sm font-medium text-muted-foreground">Status</div>
        </div>

        {/* Blocks List */}
        <div className="space-y-3">
          {isLoading ? (
            <div className="text-center py-12 text-muted-foreground">
              Loading blocks...
            </div>
          ) : !blocks || blocks.length === 0 ? (
            <div className="text-center py-12 text-muted-foreground">
              {isConfigured ? "No verified blocks yet" : "Connect contract to view blocks"}
            </div>
          ) : (
            blocks.map((block) => (
              <BlockRow
                key={block.height}
                height={block.height}
                hash={block.hash}
                timestamp={formatTimeAgo(block.timestamp)}
                status={block.status}
              />
            ))
          )}
        </div>

        {/* Pagination */}
        {blocks && blocks.length > 0 && (
          <div className="mt-8 flex items-center justify-between">
            <p className="text-sm text-muted-foreground">
              Showing {startBlock}-{endBlock} of {totalBlocks.toLocaleString()} blocks
            </p>
            <div className="flex gap-2">
              <Button
                variant="outline"
                size="sm"
                disabled={!hasPrevPage}
                onClick={() => setPage((p) => p - 1)}
              >
                Previous
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={!hasNextPage}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default Blocks;
