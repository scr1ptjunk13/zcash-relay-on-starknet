import { Card } from "@/components/ui/card";
import { ExternalLink } from "lucide-react";

const Docs = () => {
  return (
    <div className="min-h-screen py-12 px-4">
      <div className="container mx-auto max-w-4xl">
        <div className="mb-8">
          <h1 className="text-4xl font-display font-bold mb-2">Documentation</h1>
          <p className="text-muted-foreground">
            Learn how to integrate and use the Zcash Relay
          </p>
        </div>

        <div className="space-y-8">
          {/* Overview */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4">Overview</h2>
            <div className="space-y-4 text-muted-foreground">
              <p>
                Zcash Relay is the first trustless bridge between Zcash and Starknet, 
                using on-chain Equihash proof-of-work verification.
              </p>
              <p>
                Unlike traditional relayers that require trusted signers, our implementation 
                verifies every block's proof-of-work directly on Starknet, ensuring complete 
                trustlessness and censorship resistance.
              </p>
            </div>
          </Card>

          {/* How It Works */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4">How It Works</h2>
            <div className="space-y-4 text-muted-foreground">
              <p>The verification process consists of 19 on-chain transactions:</p>
              <ol className="list-decimal list-inside space-y-2 ml-4">
                <li>Initialize verification with block header</li>
                <li>Verify 16 batches of Equihash solution elements</li>
                <li>Construct and validate the Merkle tree</li>
                <li>Finalize and add to canonical chain</li>
              </ol>
              <p>
                This incremental approach allows us to verify complex cryptographic proofs 
                while staying within Starknet's gas limits.
              </p>
            </div>
          </Card>

          {/* Contract Addresses */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4">Contract Addresses</h2>
            <div className="space-y-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Sepolia Testnet</p>
                <div className="flex items-center gap-2">
                  <code className="font-mono text-sm bg-muted px-3 py-1 rounded">
                    0x...coming soon
                  </code>
                  <a
                    href="https://sepolia.starkscan.co"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-primary hover:text-primary/80"
                  >
                    <ExternalLink className="w-4 h-4" />
                  </a>
                </div>
              </div>
              <div>
                <p className="text-sm text-muted-foreground mb-1">Starknet Mainnet</p>
                <code className="font-mono text-sm bg-muted px-3 py-1 rounded text-muted-foreground">
                  Coming soon
                </code>
              </div>
            </div>
          </Card>

          {/* Integration Guide */}
          <Card className="p-6 bg-card border-border">
            <h2 className="text-2xl font-semibold mb-4">Integration Guide</h2>
            <div className="space-y-4">
              <div>
                <h3 className="font-semibold mb-2">Check if Block is Verified</h3>
                <pre className="bg-muted p-4 rounded-lg overflow-x-auto">
                  <code className="font-mono text-sm">{`const height = relay.get_block_height(blockHash);
const isFinalized = relay.is_block_finalized(blockHash);`}</code>
                </pre>
              </div>
              <div>
                <h3 className="font-semibold mb-2">Get Chain Height</h3>
                <pre className="bg-muted p-4 rounded-lg overflow-x-auto">
                  <code className="font-mono text-sm">{`const currentHeight = relay.get_chain_height();`}</code>
                </pre>
              </div>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
};

export default Docs;
