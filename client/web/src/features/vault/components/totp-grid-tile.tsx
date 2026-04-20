import { EntryIcon } from "./entry-icon";
import { CountdownRing } from "./countdown-ring";
import { MoreVertical } from "lucide-react";
import type { VaultEntry } from "@/types/vault-types";

interface TotpGridTileProps {
  entry: VaultEntry;
  selected: boolean;
  onSelect: () => void;
  onContextMenu: (e: React.MouseEvent) => void;
}

export function TotpGridTile({ entry, selected, onSelect, onContextMenu }: TotpGridTileProps) {
  return (
    <div
      onClick={onSelect}
      onContextMenu={onContextMenu}
      className={`group relative flex cursor-pointer flex-col items-center gap-1.5 rounded-lg p-3 text-center select-none ${
        selected ? "bg-accent" : "hover:bg-accent/50"
      }`}
    >
      {/* Three-dot menu (visible on hover) */}
      <button
        onClick={(e) => {
          e.stopPropagation();
          onContextMenu(e);
        }}
        className="absolute top-1 right-1 rounded p-0.5 opacity-0 group-hover:opacity-100 text-muted-foreground hover:text-foreground"
        title="More actions"
      >
        <MoreVertical className="h-3.5 w-3.5" />
      </button>

      <CountdownRing period={entry.period} size={56} radius={24}>
        <EntryIcon icon={entry.icon} issuer={entry.issuer} />
      </CountdownRing>

      <span className="text-xs font-medium truncate w-full">{entry.issuer}</span>
    </div>
  );
}
