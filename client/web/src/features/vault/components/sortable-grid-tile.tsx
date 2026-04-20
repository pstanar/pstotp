import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { TotpGridTile } from "./totp-grid-tile";
import type { VaultEntry } from "@/types/vault-types";

interface SortableGridTileProps {
  entry: VaultEntry;
  selected: boolean;
  dragEnabled: boolean;
  onSelect: () => void;
  onContextMenu: (e: React.MouseEvent) => void;
}

export function SortableGridTile({ entry, selected, dragEnabled, onSelect, onContextMenu }: SortableGridTileProps) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: entry.id });

  const style = {
    transform: CSS.Translate.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
    zIndex: isDragging ? 10 : undefined,
  };

  const dragProps = dragEnabled ? { ...attributes, ...listeners } : {};

  return (
    <div ref={setNodeRef} style={style} {...dragProps}>
      <TotpGridTile
        entry={entry}
        selected={selected}
        onSelect={onSelect}
        onContextMenu={onContextMenu}
      />
    </div>
  );
}
