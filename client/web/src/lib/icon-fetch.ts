import { apiBaseUrl } from "@/lib/base-path";

const ICON_SIZE = 64;
const FETCH_TIMEOUT_MS = 5000;
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? apiBaseUrl;

export interface FetchedIcon {
  /** Resized 64×64 PNG data URL. */
  dataUrl: string;
  /**
   * Raw bytes as downloaded, before resizing. Used for a stable,
   * cross-device `sourceHash`. Null when the bytes couldn't be obtained
   * (e.g. a CORS-restricted origin that renders via <img> but blocks
   * fetch reads) — callers then fall back to hashing the resized data.
   */
  sourceBytes: Uint8Array | null;
}

export function isIconUrl(value: string | undefined | null): boolean {
  if (!value) return false;
  return value.startsWith("http://") || value.startsWith("https://");
}

/**
 * Downloads an icon from a URL and returns it as a 64×64 PNG data URL
 * plus the original bytes. Tries a direct browser fetch first (fast path —
 * works only when the remote origin sends CORS headers); on failure, falls
 * back to the authenticated server-side proxy at /icon-proxy which bypasses
 * browser CORS. Returns null on any error so callers can fall back to a
 * generated letter icon.
 */
export async function downloadIconAsDataUrl(url: string): Promise<FetchedIcon | null> {
  const fetched = (await tryFetchBytes(url)) ?? (await tryProxyBytes(url));
  if (!fetched) return null;
  // Carry the response MIME through — resizeImageBytesToDataUrl needs it for
  // formats the browser sniffs by type (notably SVG); a typeless blob won't
  // decode as SVG.
  const dataUrl = await resizeImageBytesToDataUrl(fetched.bytes, fetched.mime);
  if (!dataUrl) return null;
  return { dataUrl, sourceBytes: fetched.bytes };
}

interface FetchedBytes {
  bytes: Uint8Array;
  mime?: string;
}

function contentTypeOf(response: Response): string | undefined {
  const ct = response.headers.get("content-type");
  return ct ? ct.split(";")[0].trim() || undefined : undefined;
}

async function tryFetchBytes(url: string): Promise<FetchedBytes | null> {
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      const response = await fetch(url, { signal: controller.signal });
      if (!response.ok) return null;
      return { bytes: new Uint8Array(await response.arrayBuffer()), mime: contentTypeOf(response) };
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return null;
  }
}

async function tryProxyBytes(url: string): Promise<FetchedBytes | null> {
  try {
    const proxyUrl = `${API_BASE_URL}/icon-proxy?url=${encodeURIComponent(url)}`;
    const response = await fetch(proxyUrl, { credentials: "include" });
    if (!response.ok) return null;
    return { bytes: new Uint8Array(await response.arrayBuffer()), mime: contentTypeOf(response) };
  } catch {
    return null;
  }
}

/**
 * Decode arbitrary image bytes and re-encode as a centred 64×64 PNG data
 * URL. Shared by the upload, URL-fetch, and import (embedded icon) paths so
 * every icon is normalised identically. Returns null if the bytes don't
 * decode as an image.
 */
export async function resizeImageBytesToDataUrl(
  bytes: Uint8Array,
  mimeType?: string,
): Promise<string | null> {
  // The Blob's type matters for formats the browser sniffs by MIME (notably
  // SVG) — pass it through when the caller knows it (e.g. import icons).
  const blob = mimeType ? new Blob([bytes as BlobPart], { type: mimeType }) : new Blob([bytes as BlobPart]);
  const objectUrl = URL.createObjectURL(blob);
  try {
    const img = await loadImage(objectUrl);
    return imageToDataUrl(img);
  } catch {
    return null;
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const timer = setTimeout(() => reject(new Error("timeout")), FETCH_TIMEOUT_MS);
    img.onload = () => { clearTimeout(timer); resolve(img); };
    img.onerror = () => { clearTimeout(timer); reject(new Error("image load failed")); };
    img.src = src;
  });
}

function imageToDataUrl(img: HTMLImageElement): string {
  const canvas = document.createElement("canvas");
  canvas.width = ICON_SIZE;
  canvas.height = ICON_SIZE;
  const ctx = canvas.getContext("2d");
  // Unrecoverable environment failure — let resizeImageBytesToDataUrl's catch
  // turn it into a null result rather than threading null through here.
  if (!ctx) throw new Error("Canvas 2D context unavailable");

  const scale = Math.max(ICON_SIZE / img.width, ICON_SIZE / img.height);
  const w = img.width * scale;
  const h = img.height * scale;
  ctx.drawImage(img, (ICON_SIZE - w) / 2, (ICON_SIZE - h) / 2, w, h);

  return canvas.toDataURL("image/png");
}
