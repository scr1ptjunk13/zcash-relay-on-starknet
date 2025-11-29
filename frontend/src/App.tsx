import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { StarknetProvider } from "@/lib/starknet";
import { Navbar } from "./components/Navbar";
import Home from "./pages/Home";
import Blocks from "./pages/Blocks";
import BlockDetail from "./pages/BlockDetail";
import Verify from "./pages/Verify";
import Docs from "./pages/Docs";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <StarknetProvider>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Navbar />
          <Routes>
            <Route path="/" element={<Home />} />
            <Route path="/blocks" element={<Blocks />} />
            <Route path="/block/:hashOrHeight" element={<BlockDetail />} />
            <Route path="/verify" element={<Verify />} />
            <Route path="/docs" element={<Docs />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </StarknetProvider>
  </QueryClientProvider>
);

export default App;
