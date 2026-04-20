import { useState, useEffect, useCallback } from "react";
import { Check, X, AlertTriangle, Info } from "lucide-react";
import { ToastContext } from "@/hooks/use-toast";

type ToastType = "success" | "error" | "info";

interface Toast {
  id: number;
  message: string;
  type: ToastType;
}

let nextId = 0;

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const addToast = useCallback((message: string, type: ToastType = "success") => {
    const id = nextId++;
    setToasts((prev) => [...prev, { id, message, type }]);
  }, []);

  const removeToast = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  return (
    <ToastContext value={{ toast: addToast }}>
      {children}
      <div className="fixed bottom-4 right-4 z-[70] flex flex-col gap-2">
        {toasts.map((t) => (
          <ToastItem key={t.id} toast={t} onDismiss={() => removeToast(t.id)} />
        ))}
      </div>
    </ToastContext>
  );
}

const DURATION_BY_TYPE: Record<ToastType, number> = {
  success: 3000,
  info: 4000,
  error: 6000,
};

function ToastItem({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  useEffect(() => {
    const timer = setTimeout(onDismiss, DURATION_BY_TYPE[toast.type]);
    return () => clearTimeout(timer);
  }, [onDismiss, toast.type]);

  const Icon = toast.type === "success" ? Check : toast.type === "error" ? AlertTriangle : Info;
  const colors = toast.type === "success"
    ? "border-green-500/30 bg-green-500/10 text-green-700 dark:text-green-400"
    : toast.type === "error"
      ? "border-destructive/30 bg-destructive/10 text-destructive"
      : "border-border bg-card text-foreground";

  return (
    <div className={`flex items-center gap-2 rounded-lg border px-4 py-2.5 text-sm shadow-lg animate-in slide-in-from-right-5 fade-in duration-200 ${colors}`}>
      <Icon className="h-4 w-4 shrink-0" />
      <span>{toast.message}</span>
      <button onClick={onDismiss} className="ml-2 shrink-0 opacity-60 hover:opacity-100">
        <X className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}
