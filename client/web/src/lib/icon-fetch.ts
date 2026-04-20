import { apiBaseUrl } from "@/lib/base-path";

const ICON_SIZE = 64;
const FETCH_TIMEOUT_MS = 5000;
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? apiBaseUrl;

export function isIconUrl(value: string | undefined | null): boolean {
  if (!value) return false;
  return value.startsWith("http://") || value.startsWith("https://");
}

/**
 * Downloads an icon from a URL and returns it as a 64x64 PNG data URL.
 * Tries a direct browser fetch first (fast path — works only when the remote
 * origin sends CORS headers); on failure, falls back to the authenticated
 * server-side proxy at /icon-proxy which bypasses browser CORS. Returns null
 * on any error so callers can fall back to a generated letter icon.
 */
export async function downloadIconAsDataUrl(url: string): Promise<string | null> {
  return (await tryDirect(url)) ?? (await tryServerProxy(url));
}

async function tryDirect(url: string): Promise<string | null> {
  try {
    const img = await loadImage(url, /* crossOrigin */ true);
    return imageToDataUrl(img);
  } catch {
    return null;
  }
}

async function tryServerProxy(url: string): Promise<string | null> {
  let objectUrl: string | null = null;
  try {
    const proxyUrl = `${API_BASE_URL}/icon-proxy?url=${encodeURIComponent(url)}`;
    const response = await fetch(proxyUrl, { credentials: "include" });
    if (!response.ok) return null;
    const blob = await response.blob();
    objectUrl = URL.createObjectURL(blob);
    const img = await loadImage(objectUrl, /* crossOrigin */ false);
    return imageToDataUrl(img);
  } catch {
    return null;
  } finally {
    if (objectUrl !== null) URL.revokeObjectURL(objectUrl);
  }
}

function loadImage(src: string, crossOrigin: boolean): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    if (crossOrigin) img.crossOrigin = "anonymous";
    const timer = setTimeout(() => reject(new Error("timeout")), FETCH_TIMEOUT_MS);
    img.onload = () => { clearTimeout(timer); resolve(img); };
    img.onerror = () => { clearTimeout(timer); reject(new Error("image load failed")); };
    img.src = src;
  });
}

function imageToDataUrl(img: HTMLImageElement): string | null {
  const canvas = document.createElement("canvas");
  canvas.width = ICON_SIZE;
  canvas.height = ICON_SIZE;
  const ctx = canvas.getContext("2d");
  if (!ctx) return null;

  const scale = Math.max(ICON_SIZE / img.width, ICON_SIZE / img.height);
  const w = img.width * scale;
  const h = img.height * scale;
  ctx.drawImage(img, (ICON_SIZE - w) / 2, (ICON_SIZE - h) / 2, w, h);

  return canvas.toDataURL("image/png");
}
