import { createContext, useContext } from "react";

export interface ToastContextValue {
  toast: (message: string, type?: "success" | "error" | "info") => void;
}

export const ToastContext = createContext<ToastContextValue>({ toast: () => {} });

export function useToast(): ToastContextValue {
  return useContext(ToastContext);
}
