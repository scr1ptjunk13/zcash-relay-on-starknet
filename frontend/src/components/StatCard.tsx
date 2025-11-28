import { LucideIcon } from "lucide-react";
import { Card } from "@/components/ui/card";

interface StatCardProps {
  label: string;
  value: string | number;
  icon?: LucideIcon;
  trend?: {
    value: string;
    positive: boolean;
  };
  chart?: React.ReactNode;
}

export const StatCard = ({ label, value, icon: Icon, trend, chart }: StatCardProps) => {
  return (
    <Card className="p-5 bg-transparent border-border/30">
      <div className="flex items-start justify-between mb-3">
        <div className="flex-1">
          <p className="text-xs text-muted-foreground mb-2">{label}</p>
          <p className="text-2xl font-mono font-normal tabular-nums">{value}</p>
        </div>
        {Icon && (
          <Icon className="w-4 h-4 text-muted-foreground/30" />
        )}
      </div>
      
      <div className="flex items-center justify-between">
        {trend && (
          <span className={`text-xs font-normal ${trend.positive ? 'text-success' : 'text-destructive'}`}>
            {trend.positive ? '+' : ''}{trend.value}
          </span>
        )}
        {chart && <div className="flex-1 h-6">{chart}</div>}
      </div>
    </Card>
  );
};
