import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical } from "lucide-react";
import { TotpCard } from "./totp-card";
import type { VaultEntry } from "@/types/vault-types";

interface SortableCardProps {
  entry: VaultEntry;
  dragEnabled: boolean;
  onEdit: () => void;
  onDelete: () => void;
}

export function SortableCard({ entry, dragEnabled, onEdit, onDelete }: SortableCardProps) {
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

  return (
    <div ref={setNodeRef} style={style} className="flex items-center gap-1">
      {dragEnabled && (
        <button
          {...attributes}
          {...listeners}
          className="text-muted-foreground hover:text-foreground shrink-0 cursor-grab touch-none rounded p-1 active:cursor-grabbing"
          tabIndex={0}
          aria-label="Drag to reorder"
        >
          <GripVertical className="h-4 w-4" />
        </button>
      )}
      <div className="flex-1 min-w-0">
        <TotpCard entry={entry} onEdit={onEdit} onDelete={onDelete} />
      </div>
    </div>
  );
}
