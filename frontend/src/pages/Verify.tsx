import { useState } from "react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { AlertCircle } from "lucide-react";

const Verify = () => {
  const [blockHeight, setBlockHeight] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  const handleFetch = () => {
    setIsLoading(true);
    // Simulate API call
    setTimeout(() => {
      setIsLoading(false);
    }, 1000);
  };

  return (
    <div className="min-h-screen py-12 px-4">
      <div className="container mx-auto max-w-3xl">
        <div className="mb-8">
          <h1 className="text-4xl font-display font-bold mb-2">Verify Block</h1>
          <p className="text-muted-foreground">
            Submit a Zcash block for on-chain verification
          </p>
        </div>

        <Card className="p-6 bg-card border-border mb-6">
          <h2 className="text-xl font-semibold mb-6">Enter Block Height</h2>
          
          <div className="space-y-4">
            <div>
              <label className="text-sm text-muted-foreground mb-2 block">
                Block Height
              </label>
              <Input
                type="number"
                placeholder="e.g., 2847123"
                value={blockHeight}
                onChange={(e) => setBlockHeight(e.target.value)}
                className="bg-background border-border"
              />
            </div>

            <Button
              onClick={handleFetch}
              disabled={!blockHeight || isLoading}
              className="w-full"
            >
              {isLoading ? "Fetching..." : "Fetch from Zcash"}
            </Button>
          </div>
        </Card>

        <div className="bg-muted/30 border border-border rounded-lg p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-primary mt-0.5" />
          <div>
            <p className="font-medium mb-1">Verification Process</p>
            <p className="text-sm text-muted-foreground">
              Verifying a block requires 19 transactions and costs approximately 0.003 ETH. 
              The process is incremental to fit within Starknet gas limits.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Verify;
