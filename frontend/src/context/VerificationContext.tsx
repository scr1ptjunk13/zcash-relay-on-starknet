import { createContext, useContext, useState, useEffect, useRef, ReactNode } from "react";

const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:3001";
// Convert http(s) to ws(s) properly
const WS_URL = BACKEND_URL.replace(/^https:/, 'wss:').replace(/^http:/, 'ws:');

// Strip ANSI color codes from terminal output
const stripAnsi = (str: string) => str.replace(/\x1b\[[0-9;]*m/g, '');

export interface LogLine {
  timestamp: string;
  text: string;
  type: "info" | "success" | "error" | "tx" | "header" | "dim";
}

interface VerificationState {
  isVerifying: boolean;
  logs: LogLine[];
  currentStep: number;       // Current step within current block (0-11)
  totalSteps: number;        // Total steps across ALL blocks
  completedSteps: number;    // Cumulative completed steps
  status: "idle" | "running" | "success" | "error";
  targetHeight: number | null;
  startHeight: number | null;  // Chain height when we started
  currentBlock: number | null;
  blocksToVerify: number;      // Total blocks to verify
  blocksCompleted: number;     // Blocks completed so far
}

interface VerificationContextType extends VerificationState {
  startVerification: (height: number) => Promise<void>;
  clearLogs: () => void;
}

const VerificationContext = createContext<VerificationContextType | null>(null);

export function useVerification() {
  const ctx = useContext(VerificationContext);
  if (!ctx) throw new Error("useVerification must be used within VerificationProvider");
  return ctx;
}

const getTimestamp = () => {
  const now = new Date();
  return now.toLocaleTimeString('en-US', { 
    hour12: false, 
    hour: '2-digit', 
    minute: '2-digit', 
    second: '2-digit' 
  });
};

export function VerificationProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<VerificationState>({
    isVerifying: false,
    logs: [],
    currentStep: 0,
    totalSteps: 11,
    completedSteps: 0,
    status: "idle",
    targetHeight: null,
    startHeight: null,
    currentBlock: null,
    blocksToVerify: 1,
    blocksCompleted: 0,
  });

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectRef = useRef<NodeJS.Timeout | null>(null);

  const addLog = (text: string, type: LogLine["type"] = "info") => {
    setState(prev => ({
      ...prev,
      logs: [...prev.logs, { timestamp: getTimestamp(), text, type }]
    }));
  };

  const connectWebSocket = () => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      console.log("[WS] Connected");
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        
        if (data.type === "progress") {
          const output = stripAnsi(data.output);
          
          // Parse chain height and blocks to verify from "[INFO] Relaying blocks X to Y (N blocks)"
          const relayingMatch = output.match(/Relaying blocks (\d+) to (\d+) \((\d+) blocks?\)/);
          if (relayingMatch) {
            const startBlock = parseInt(relayingMatch[1]);
            const numBlocks = parseInt(relayingMatch[3]);
            setState(prev => ({
              ...prev,
              startHeight: startBlock - 1,
              blocksToVerify: numBlocks,
              totalSteps: numBlocks * 11,
            }));
          }
          
          // Parse the output to determine log type
          let logType: LogLine["type"] = "info";
          
          // Check for block header first (e.g., "Block 9" at the start of a new block)
          const blockHeaderMatch = output.match(/^Block (\d+)$/);
          if (blockHeaderMatch) {
            logType = "header";
            const blockNum = parseInt(blockHeaderMatch[1]);
            setState(prev => ({ ...prev, currentBlock: blockNum }));
          } else if (output.includes("[TX")) {
            logType = "tx";
            // Update current step and cumulative progress
            setState(prev => {
              const newStep = data.step;
              const completedSteps = (prev.blocksCompleted * 11) + newStep;
              return { ...prev, currentStep: newStep, completedSteps };
            });
          } else if (output.includes("[DONE]")) {
            logType = "success";
            // A block was completed - increment blocksCompleted
            setState(prev => ({
              ...prev,
              blocksCompleted: prev.blocksCompleted + 1,
              completedSteps: (prev.blocksCompleted + 1) * 11,
            }));
          } else if (output.includes("[ERROR]") || output.includes("failed")) {
            logType = "error";
          } else if (output.includes("ZCASH RELAY") || output.includes("Target:") || output.includes("Contract:")) {
            logType = "header";
          } else if (output.includes("[FETCH]") || output.includes("[CHECK]") || output.includes("[INFO]")) {
            logType = "info";
          } else if (output.includes("[SKIP]")) {
            logType = "success";
          } else if (output.startsWith("─") || output.trim() === "") {
            logType = "dim";
          } else if (output.includes("SUCCESS") || output.includes("Total time:")) {
            logType = "success";
          }
          
          addLog(output, logType);
        } else if (data.type === "complete") {
          if (data.success) {
            addLog(`✓ Block ${data.height} verified successfully`, "success");
          } else {
            addLog(`✗ Block ${data.height} verification failed`, "error");
            setState(prev => ({ ...prev, isVerifying: false, status: "error" }));
          }
          // Check if this is the final target block
          setState(prev => {
            if (data.height === prev.targetHeight) {
              return { ...prev, isVerifying: false, status: data.success ? "success" : "error" };
            }
            return prev;
          });
        }
      } catch (err) {
        console.error("[WS] Parse error:", err);
      }
    };

    ws.onclose = () => {
      console.log("[WS] Disconnected");
      // Reconnect after delay if still verifying
      if (state.isVerifying) {
        reconnectRef.current = setTimeout(connectWebSocket, 2000);
      }
    };

    ws.onerror = () => {
      console.error("[WS] Connection error");
    };
  };

  // Connect WebSocket on mount
  useEffect(() => {
    connectWebSocket();
    return () => {
      wsRef.current?.close();
      if (reconnectRef.current) clearTimeout(reconnectRef.current);
    };
  }, []);

  // Reconnect if verifying and WS disconnects
  useEffect(() => {
    if (state.isVerifying && wsRef.current?.readyState !== WebSocket.OPEN) {
      connectWebSocket();
    }
  }, [state.isVerifying]);

  const startVerification = async (height: number) => {
    setState(prev => ({
      ...prev,
      isVerifying: true,
      status: "running",
      currentStep: 0,
      completedSteps: 0,
      totalSteps: 11, // Will be updated when we get the relay info
      logs: [],
      targetHeight: height,
      startHeight: null,
      currentBlock: null,
      blocksToVerify: 1,
      blocksCompleted: 0,
    }));

    // Ensure WebSocket is connected
    connectWebSocket();

    try {
      const res = await fetch(`${BACKEND_URL}/api/verify/${height}`, {
        method: "POST",
      });
      
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to start verification");
      }
      
      addLog("Verification started via backend", "success");
      addLog("Waiting for transactions...", "dim");
    } catch (err) {
      addLog(`${err instanceof Error ? err.message : "Connection failed"}`, "error");
      addLog("Make sure backend is running: cd backend && npm start", "dim");
      setState(prev => ({ ...prev, isVerifying: false, status: "error" }));
    }
  };

  const clearLogs = () => {
    setState(prev => ({
      ...prev,
      logs: [],
      status: "idle",
      currentStep: 0,
      completedSteps: 0,
      totalSteps: 11,
      targetHeight: null,
      startHeight: null,
      currentBlock: null,
      blocksToVerify: 1,
      blocksCompleted: 0,
    }));
  };

  return (
    <VerificationContext.Provider value={{ ...state, startVerification, clearLogs }}>
      {children}
    </VerificationContext.Provider>
  );
}
