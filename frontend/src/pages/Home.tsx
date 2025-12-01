import { Button } from "@/components/ui/button";
import { StatCard } from "@/components/StatCard";
import { BlockRow } from "@/components/BlockRow";
import { ArrowRight, Activity, Database, Zap, DollarSign, AlertCircle, Shield, ArrowLeftRight } from "lucide-react";
import { Link } from "react-router-dom";
import { useFormattedStats } from "@/hooks/useRelayStats";
import { useRecentBlocks } from "@/hooks/useRelayContract";
import { useStarknet, formatTimeAgo } from "@/lib/starknet";
import { Alert, AlertDescription } from "@/components/ui/alert";

const Home = () => {
  const { isConfigured } = useStarknet();
  const { stats, isLoading: statsLoading } = useFormattedStats();
  const { data: recentBlocks, isLoading: blocksLoading } = useRecentBlocks(5);

  const statCards = [
    { label: "Current Height", value: stats.currentHeight, icon: Activity },
    { label: "Blocks Verified", value: stats.blocksVerified, icon: Database },
    { label: "Total PoW", value: stats.totalPow, icon: Zap },
    { label: "Avg Cost", value: stats.avgCost, icon: DollarSign },
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
          <div className="flex items-center justify-center gap-3">
            <Link to="/verify">
              <Button variant="default" size="sm" className="gap-2">
                <Shield className="w-3 h-3" />
                Verify Block
              </Button>
            </Link>
            <Link to="/bridge">
              <Button variant="outline" size="sm" className="gap-2">
                <ArrowLeftRight className="w-3 h-3" />
                Bridge Assets
              </Button>
            </Link>
          </div>
        </div>
      </section>

      {/* Contract Not Configured Warning */}
      {!isConfigured && (
        <section className="px-4 pb-4">
          <div className="container mx-auto max-w-5xl">
            <Alert variant="default" className="border-yellow-500/50 bg-yellow-500/10">
              <AlertCircle className="h-4 w-4 text-yellow-500" />
              <AlertDescription className="text-yellow-200">
                Contract not configured. Set <code className="bg-muted px-1 rounded">VITE_RELAY_CONTRACT_ADDRESS</code> in your environment to connect to a deployed relay.
              </AlertDescription>
            </Alert>
          </div>
        </section>
      )}

      {/* Stats Section */}
      <section className="py-12 px-4">
        <div className="container mx-auto">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {statCards.map((stat) => (
              <StatCard
                key={stat.label}
                label={stat.label}
                value={statsLoading ? "..." : stat.value}
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
            {blocksLoading ? (
              <div className="text-center py-8 text-muted-foreground">
                Loading blocks...
              </div>
            ) : !recentBlocks || recentBlocks.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground">
                {isConfigured ? "No verified blocks yet" : "Connect contract to view blocks"}
              </div>
            ) : (
              recentBlocks.map((block) => (
                <BlockRow
                  key={block.height}
                  height={block.height}
                  hash={block.hash}
                  timestamp={block.registrationTimestamp ? formatTimeAgo(block.registrationTimestamp) : "—"}
                  status={block.status}
                />
              ))
            )}
          </div>
        </div>
      </section>

    </div>
  );
};

export default Home;
