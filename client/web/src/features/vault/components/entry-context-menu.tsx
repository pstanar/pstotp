import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { Copy, Key, QrCode, Pencil, Trash2 } from "lucide-react";

interface EntryContextMenuProps {
  x: number;
  y: number;
  onClose: () => void;
  onCopyCode: () => void;
  onCopySecret: () => void;
  onShowQr: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

export function EntryContextMenu({
  x,
  y,
  onClose,
  onCopyCode,
  onCopySecret,
  onShowQr,
  onEdit,
  onDelete,
}: EntryContextMenuProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("mousedown", handleClick);
    document.addEventListener("keydown", handleEsc);
    return () => {
      document.removeEventListener("mousedown", handleClick);
      document.removeEventListener("keydown", handleEsc);
    };
  }, [onClose]);

  // Position after mount via direct DOM manipulation
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const padding = 8;
    const vw = window.innerWidth;
    const vh = window.innerHeight;

    let left = x;
    let top = y;

    if (left + rect.width > vw - padding) left = x - rect.width;
    if (top + rect.height > vh - padding) top = y - rect.height;
    if (left < padding) left = padding;
    if (top < padding) top = padding;

    el.style.left = `${left}px`;
    el.style.top = `${top}px`;
    el.style.visibility = "visible";
  }, [x, y]);

  const items = [
    { label: "Copy Code", icon: Copy, action: onCopyCode },
    { label: "Copy Secret Key", icon: Key, action: onCopySecret },
    { label: "Show QR Code", icon: QrCode, action: onShowQr },
    { label: "Edit", icon: Pencil, action: onEdit },
  ];

  return createPortal(
    <div
      ref={ref}
      className="bg-popover text-popover-foreground border-border fixed z-50 w-[200px] max-w-[calc(100vw-16px)] rounded-lg border p-1 shadow-lg"
      style={{ left: -9999, top: -9999, visibility: "hidden" }}
    >
      {items.map((item) => (
        <button
          key={item.label}
          onClick={() => {
            item.action();
            onClose();
          }}
          className="hover:bg-accent flex w-full items-center gap-2 rounded-md px-3 py-2.5 text-sm"
        >
          <item.icon className="h-4 w-4" />
          {item.label}
        </button>
      ))}
      <div className="border-border my-1 border-t" />
      <button
        onClick={() => {
          onDelete();
          onClose();
        }}
        className="hover:bg-destructive/10 text-destructive flex w-full items-center gap-2 rounded-md px-3 py-2.5 text-sm"
      >
        <Trash2 className="h-4 w-4" />
        Delete
      </button>
    </div>,
    document.body,
  );
}
