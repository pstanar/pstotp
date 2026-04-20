import { useEffect, useRef } from "react";
import { X } from "lucide-react";
import { cn } from "@/lib/css-utils";

interface DialogProps {
  open: boolean;
  onClose: () => void;
  title?: string;
  className?: string;
  children: React.ReactNode;
}

export function Dialog({ open, onClose, title, className, children }: DialogProps) {
  const contentRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handleEsc);
    return () => document.removeEventListener("keydown", handleEsc);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-[2px] animate-in fade-in duration-150"
      onClick={(e) => {
        if (contentRef.current && !contentRef.current.contains(e.target as Node)) {
          onClose();
        }
      }}
    >
      <div
        ref={contentRef}
        className={cn(
          "bg-background mx-4 w-full max-w-md rounded-lg border shadow-xl",
          "animate-in zoom-in-95 slide-in-from-bottom-2 duration-200",
          className,
        )}
      >
        {title && (
          <div className="flex items-center justify-between border-b px-4 py-3 sm:px-6 sm:py-4">
            <h2 className="text-lg font-semibold">{title}</h2>
            <button
              onClick={onClose}
              className="text-muted-foreground hover:text-foreground -mr-1 rounded-md p-2 transition-colors"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        )}
        <div className={title ? "px-4 py-3 sm:px-6 sm:py-4" : "p-4 sm:p-6"}>
          {children}
        </div>
      </div>
    </div>
  );
}
