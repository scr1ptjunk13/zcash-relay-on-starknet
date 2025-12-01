import { Link } from "react-router-dom";

export const Navbar = () => {
  return (
    <nav className="border-b border-border/30 bg-background sticky top-0 z-50">
      <div className="container mx-auto px-4 h-14 flex items-center justify-between">
        <Link to="/" className="flex items-center gap-2">
          <img src="/logo.png" alt="ZULU" className="w-8 h-8" />
          <div className="flex flex-col">
            <span className="font-bold text-base tracking-wide">Z.U.L.U.</span>
          </div>
        </Link>

        <div className="hidden md:flex items-center gap-6">
          <Link to="/" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
            Home
          </Link>
          <Link to="/verify" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
            Verify
          </Link>
          <Link to="/bridge" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
            Bridge
          </Link>
          <Link to="/blocks" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
            Blocks
          </Link>
          <Link to="/docs" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
            Docs
          </Link>
        </div>

        <div className="flex items-center gap-4">
          <div className="hidden md:flex items-center gap-2 text-xs text-muted-foreground">
            <div className="w-1.5 h-1.5 rounded-full bg-success" />
            Sepolia
          </div>
        </div>
      </div>
    </nav>
  );
};
