import { useState, useEffect, useRef } from "react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { AlertCircle, CheckCircle2, Loader2, XCircle } from "lucide-react";

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:3001";
// WebSocket uses same server, just different protocol
const WS_URL = BACKEND_URL.replace(/^http/, 'ws');

// Strip ANSI color codes from terminal output
const stripAnsi = (str: string) => str.replace(/\x1b\[[0-9;]*m/g, '');

interface LogLine {
  text: string;
  type: "info" | "success" | "error" | "tx";
}

const Verify = () => {
  const [blockHeight, setBlockHeight] = useState("");
  const [isVerifying, setIsVerifying] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);
  const [currentStep, setCurrentStep] = useState(0);
  const [status, setStatus] = useState<"idle" | "running" | "success" | "error">("idle");
  const logsEndRef = useRef<HTMLDivElement>(null);
  const wsRef = useRef<WebSocket | null>(null);

  // Auto-scroll logs
  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

  // WebSocket connection
  useEffect(() => {
    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      console.log("[WS] Connected");
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        
        if (data.type === "progress") {
          setCurrentStep(data.step);
          addLog(stripAnsi(data.output), "tx");
        } else if (data.type === "complete") {
          if (data.success) {
            addLog(`\n✓ Block ${data.height} verified successfully!`, "success");
            setStatus("success");
          } else {
            addLog(`\n✗ Block ${data.height} verification failed`, "error");
            setStatus("error");
          }
          setIsVerifying(false);
        }
      } catch (err) {
        console.error("[WS] Parse error:", err);
      }
    };

    ws.onerror = () => {
      addLog("WebSocket connection error - is backend running?", "error");
    };

    return () => {
      ws.close();
    };
  }, []);

  const addLog = (text: string, type: LogLine["type"] = "info") => {
    setLogs((prev) => [...prev, { text, type }]);
  };

  const handleVerify = async () => {
    const height = parseInt(blockHeight);
    if (isNaN(height) || height < 0) {
      addLog("Invalid block height", "error");
      return;
    }

    setIsVerifying(true);
    setStatus("running");
    setCurrentStep(0);
    setLogs([]);

    addLog(`Block ${height}`, "info");
    addLog("─────────────────────────────────────", "info");
    addLog("[FETCH] Starting verification...", "info");

    try {
      const res = await fetch(`${BACKEND_URL}/api/verify/${height}`, {
        method: "POST",
      });
      
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to start verification");
      }
      
      addLog("[FETCH] Verification started via backend", "success");
      addLog("[FETCH] Waiting for transactions...\n", "info");
    } catch (err) {
      addLog(`[ERROR] ${err instanceof Error ? err.message : "Connection failed"}`, "error");
      addLog("\nMake sure backend is running: cd backend && npm start", "info");
      setIsVerifying(false);
      setStatus("error");
    }
  };

  const getLogColor = (type: LogLine["type"]) => {
    switch (type) {
      case "success": return "text-green-400";
      case "error": return "text-red-400";
      case "tx": return "text-cyan-400";
      default: return "text-gray-300";
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
                placeholder="e.g., 4"
                value={blockHeight}
                onChange={(e) => setBlockHeight(e.target.value)}
                className="bg-background border-border"
                disabled={isVerifying}
              />
            </div>

            <Button
              onClick={handleVerify}
              disabled={!blockHeight || isVerifying}
              className="w-full"
            >
              {isVerifying ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Verifying... ({currentStep}/11)
                </>
              ) : (
                "Start Verification"
              )}
            </Button>
          </div>
        </Card>

        {/* Terminal Output */}
        {logs.length > 0 && (
          <Card className="p-4 bg-black/90 border-border mb-6 font-mono text-sm">
            <div className="flex items-center gap-2 mb-3 pb-2 border-b border-gray-700">
              <div className="w-3 h-3 rounded-full bg-red-500" />
              <div className="w-3 h-3 rounded-full bg-yellow-500" />
              <div className="w-3 h-3 rounded-full bg-green-500" />
              <span className="text-gray-400 text-xs ml-2">Verification Log</span>
              {status === "running" && <Loader2 className="w-3 h-3 animate-spin text-cyan-400 ml-auto" />}
              {status === "success" && <CheckCircle2 className="w-4 h-4 text-green-400 ml-auto" />}
              {status === "error" && <XCircle className="w-4 h-4 text-red-400 ml-auto" />}
            </div>
            <div className="max-h-96 overflow-y-auto space-y-1">
              {logs.map((log, i) => (
                <div key={i} className={getLogColor(log.type)}>
                  {log.text}
                </div>
              ))}
              <div ref={logsEndRef} />
            </div>
          </Card>
        )}

        {/* Progress indicator */}
        {isVerifying && (
          <Card className="p-4 bg-card border-border mb-6">
            <div className="flex justify-between text-sm mb-2">
              <span>Progress</span>
              <span>{currentStep}/11 transactions</span>
            </div>
            <div className="w-full bg-muted rounded-full h-2">
              <div 
                className="bg-primary h-2 rounded-full transition-all duration-300"
                style={{ width: `${(currentStep / 11) * 100}%` }}
              />
            </div>
          </Card>
        )}

        <div className="bg-muted/30 border border-border rounded-lg p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-primary mt-0.5" />
          <div>
            <p className="font-medium mb-1">Verification Process</p>
            <p className="text-sm text-muted-foreground">
              Verifying a block requires 11 transactions and costs approximately 40 STRK on testnet. 
              The process takes ~5 minutes. Make sure the backend is running.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Verify;
