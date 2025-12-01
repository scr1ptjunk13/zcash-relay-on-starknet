import { useState, useEffect, useRef } from "react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { AlertCircle, CheckCircle2, Loader2, XCircle, Terminal } from "lucide-react";
import { useVerification, LogLine } from "@/context/VerificationContext";

const Verify = () => {
  const [blockHeight, setBlockHeight] = useState("");
  const logsEndRef = useRef<HTMLDivElement>(null);
  
  const {
    isVerifying,
    logs,
    currentStep,
    totalSteps,
    completedSteps,
    status,
    currentBlock,
    targetHeight,
    blocksToVerify,
    blocksCompleted,
    startVerification,
    clearLogs,
  } = useVerification();

  // Auto-scroll logs
  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

  const handleVerify = async () => {
    const height = parseInt(blockHeight);
    if (isNaN(height) || height < 0) {
      return;
    }
    await startVerification(height);
  };

  const getLogColor = (type: LogLine["type"]) => {
    switch (type) {
      case "success": return "text-green-400";
      case "error": return "text-red-400";
      case "tx": return "text-yellow-300";
      case "header": return "text-green-500 font-bold";
      case "dim": return "text-gray-500";
      default: return "text-gray-300";
    }
  };

  const getStatusIcon = (type: LogLine["type"]) => {
    switch (type) {
      case "success": return "●";
      case "error": return "●";
      case "tx": return "○";
      case "header": return "●";
      default: return "○";
    }
  };

  const getStatusColor = (type: LogLine["type"]) => {
    switch (type) {
      case "success": return "text-green-500";
      case "error": return "text-red-500";
      case "tx": return "text-yellow-500";
      case "header": return "text-green-500";
      default: return "text-gray-600";
    }
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
                placeholder="e.g., 5"
                value={blockHeight}
                onChange={(e) => setBlockHeight(e.target.value)}
                className="bg-background border-border"
                disabled={isVerifying}
              />
            </div>

            <div className="flex gap-2">
              <Button
                onClick={handleVerify}
                disabled={!blockHeight || isVerifying}
                className="flex-1"
              >
                {isVerifying ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    {blocksToVerify > 1 
                      ? `Verifying Block ${currentBlock || "..."}... (${completedSteps}/${totalSteps})`
                      : `Verifying... (${currentStep}/11)`
                    }
                  </>
                ) : (
                  "Start Verification"
                )}
              </Button>
              {logs.length > 0 && !isVerifying && (
                <Button variant="outline" onClick={clearLogs}>
                  Clear
                </Button>
              )}
            </div>
          </div>
        </Card>

        {/* Terminal Output - Render style */}
        {logs.length > 0 && (
          <Card className="bg-[#0d1117] border-[#30363d] mb-6 overflow-hidden">
            {/* Header */}
            <div className="flex items-center justify-between px-4 py-2 border-b border-[#30363d] bg-[#161b22]">
              <div className="flex items-center gap-2">
                <Terminal className="w-4 h-4 text-gray-400" />
                <span className="text-sm text-gray-400 font-medium">
                  Verification Log
                  {currentBlock && isVerifying && (
                    <span className="text-gray-500"> — Block {currentBlock}</span>
                  )}
                </span>
              </div>
              <div className="flex items-center gap-2">
                {status === "running" && (
                  <span className="flex items-center gap-1.5 text-xs text-yellow-400">
                    <span className="w-2 h-2  bg-yellow-400 animate-pulse" />
                    Running
                  </span>
                )}
                {status === "success" && (
                  <span className="flex items-center gap-1.5 text-xs text-green-400">
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    Complete
                  </span>
                )}
                {status === "error" && (
                  <span className="flex items-center gap-1.5 text-xs text-red-400">
                    <XCircle className="w-3.5 h-3.5" />
                    Failed
                  </span>
                )}
              </div>
            </div>
            
            {/* Log content */}
            <div className="max-h-[500px] overflow-y-auto font-mono text-[13px] leading-relaxed">
              {logs.map((log, i) => (
                <div 
                  key={i} 
                  className="flex items-start hover:bg-[#161b22] px-4 py-0.5 group"
                >
                  <span className="text-gray-600 w-20 flex-shrink-0 select-none">
                    {log.timestamp}
                  </span>
                  <span className={`${getStatusColor(log.type)} w-4 flex-shrink-0 select-none`}>
                    {getStatusIcon(log.type)}
                  </span>
                  <span className={`${getLogColor(log.type)} flex-1 break-all`}>
                    {log.text}
                  </span>
                </div>
              ))}
              <div ref={logsEndRef} className="h-2" />
            </div>
          </Card>
        )}

        {/* Progress indicator */}
        {isVerifying && (
          <Card className="p-4 bg-card border-border mb-6">
            <div className="flex justify-between text-sm mb-2">
              <span className="text-muted-foreground">
                {blocksToVerify > 1 ? (
                  <>Block {currentBlock || "..."} of {blocksToVerify} ({blocksCompleted} completed)</>
                ) : (
                  currentBlock ? `Block ${currentBlock}` : "Progress"
                )}
              </span>
              <span className="font-mono">
                {blocksToVerify > 1 ? (
                  <>{completedSteps}/{totalSteps} transactions</>
                ) : (
                  <>{currentStep}/11 transactions</>
                )}
              </span>
            </div>
            <div className="w-full bg-muted  h-2">
              <div 
                className="bg-green-500 h-2  transition-all duration-300"
                style={{ width: `${blocksToVerify > 1 ? (completedSteps / totalSteps) * 100 : (currentStep / 11) * 100}%` }}
              />
            </div>
          </Card>
        )}

        <div className="bg-muted/30 border border-border  p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-primary mt-0.5" />
          <div>
            <p className="font-medium mb-1">Verification Process</p>
            <p className="text-sm text-muted-foreground">
              Verifying a block requires 11 transactions and costs approximately 15 STRK on testnet. 
              The process takes ~3 minutes per block. If the target height is ahead of the current chain height,
              all intermediate blocks will be verified first.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Verify;
