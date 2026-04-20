import { useEffect } from "react";
import { apiBaseUrl } from "@/lib/base-path";

const CLOSING_URL = (import.meta.env.VITE_API_BASE_URL ?? apiBaseUrl) + "/system/closing";

/**
 * Sends a deferred-shutdown signal to the server when the browser tab is closed.
 * The server waits 5 seconds before acting — if the page reloads (refresh), incoming
 * requests automatically cancel the pending shutdown.
 */
export function useShutdownOnClose() {
  useEffect(() => {
    const handlePageHide = () => {
      navigator.sendBeacon(CLOSING_URL);
    };
    window.addEventListener("pagehide", handlePageHide);
    return () => window.removeEventListener("pagehide", handlePageHide);
  }, []);
}
