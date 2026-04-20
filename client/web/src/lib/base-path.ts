/**
 * The base path under which the app is served (e.g. "" when at root,
 * "/totp" when behind a reverse proxy at example.com/totp).
 *
 * Populated at runtime by a script tag in index.html that ASP.NET
 * substitutes before serving. In dev mode (Vite serving index.html
 * directly) the placeholder is left intact and the helper in
 * index.html falls back to "".
 */
declare global {
  interface Window {
    __PSTOTP_BASE__?: string;
  }
}

/** Base path with no trailing slash. Empty string when served at root. */
export const basePath: string = (() => {
  const value = window.__PSTOTP_BASE__ ?? "";
  return value.replace(/\/+$/, "");
})();

/** Base URL for all API calls, e.g. "/api" or "/totp/api". */
export const apiBaseUrl: string = `${basePath}/api`;

/** Resolves a path under the app's base, e.g. "favicon.svg" -> "/totp/favicon.svg". */
export function withBasePath(path: string): string {
  if (path.startsWith("http://") || path.startsWith("https://")) return path;
  const normalized = path.startsWith("/") ? path : `/${path}`;
  return `${basePath}${normalized}`;
}
