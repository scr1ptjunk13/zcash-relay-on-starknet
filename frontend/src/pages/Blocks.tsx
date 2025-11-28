import { useState } from "react";
import { Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { BlockRow } from "@/components/BlockRow";
import { useNavigate } from "react-router-dom";

const Blocks = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const navigate = useNavigate();

  // Mock data
  const blocks = Array.from({ length: 20 }, (_, i) => ({
    height: 2847123 - i,
    hash: `0x${Math.random().toString(16).slice(2)}${Math.random().toString(16).slice(2)}${Math.random().toString(16).slice(2)}`,
    timestamp: `${Math.floor(Math.random() * 60)} min ago`,
    status: (i % 3 === 0 ? "confirming" : "finalized") as "confirming" | "finalized",
  }));

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/block/${searchQuery}`);
    }
  };

  return (
    <div className="min-h-screen py-12 px-4">
      <div className="container mx-auto">
        <div className="mb-8">
          <h1 className="text-4xl font-display font-bold mb-2">Block Explorer</h1>
          <p className="text-muted-foreground">
            Browse all verified Zcash blocks on Starknet
          </p>
        </div>

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
          {blocks.map((block) => (
            <BlockRow key={block.height} {...block} />
          ))}
        </div>

        {/* Pagination */}
        <div className="mt-8 flex items-center justify-between">
          <p className="text-sm text-muted-foreground">Showing 1-20 of 147 blocks</p>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled>
              Previous
            </Button>
            <Button variant="outline" size="sm">
              Next
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Blocks;
