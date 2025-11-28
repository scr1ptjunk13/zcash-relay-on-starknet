import { Button } from "@/components/ui/button";
import { StatCard } from "@/components/StatCard";
import { BlockRow } from "@/components/BlockRow";
import { ArrowRight, Activity, Database, Zap, DollarSign } from "lucide-react";
import { Link } from "react-router-dom";

const Home = () => {
  // Mock data - in real app, fetch from contract
  const stats = [
    { label: "Current Height", value: "2,847,123", icon: Activity },
    { label: "Blocks Verified", value: "147", icon: Database },
    { label: "Total PoW", value: "4.2M", icon: Zap },
    { label: "Avg Cost", value: "0.003 ETH", icon: DollarSign },
  ];

  const recentBlocks = [
    { height: 2847123, hash: "0x1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b", timestamp: "2 min ago", status: "finalized" as const },
    { height: 2847122, hash: "0x2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c", timestamp: "5 min ago", status: "finalized" as const },
    { height: 2847121, hash: "0x3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d", timestamp: "8 min ago", status: "confirming" as const },
    { height: 2847120, hash: "0x4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e", timestamp: "11 min ago", status: "finalized" as const },
    { height: 2847119, hash: "0x5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f", timestamp: "14 min ago", status: "finalized" as const },
  ];

  return (
    <div className="min-h-screen">
      {/* Hero Section */}
      <section className="py-12 px-4">
        <div className="container mx-auto max-w-5xl text-center">
          <h1 className="text-3xl md:text-4xl font-normal mb-3 text-foreground">
            Trustless Zcash Verification on Starknet
          </h1>
          <p className="text-sm text-muted-foreground mb-6 max-w-2xl mx-auto">
            The first on-chain Equihash PoW verification. No trusted relayers. Pure cryptography.
          </p>
          <Link to="/blocks">
            <Button variant="outline" size="sm" className="gap-2">
              Explore Blocks <ArrowRight className="w-3 h-3" />
            </Button>
          </Link>
        </div>
      </section>

      {/* Stats Section */}
      <section className="py-12 px-4">
        <div className="container mx-auto">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {stats.map((stat) => (
              <StatCard
                key={stat.label}
                label={stat.label}
                value={stat.value}
                icon={stat.icon}
              />
            ))}
          </div>
        </div>
      </section>

      {/* Recent Activity */}
      <section className="py-8 px-4">
        <div className="container mx-auto">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-normal">Recent Activity</h2>
            <Link to="/blocks">
              <Button variant="ghost" size="sm" className="gap-2 text-muted-foreground hover:text-foreground">
                View All <ArrowRight className="w-3 h-3" />
              </Button>
            </Link>
          </div>
          
          <div className="space-y-2">
            {recentBlocks.map((block) => (
              <BlockRow key={block.height} {...block} />
            ))}
          </div>
        </div>
      </section>

    </div>
  );
};

export default Home;
