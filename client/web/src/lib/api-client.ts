import { useAuthStore } from "@/stores/useAuthStore";
import { apiBaseUrl } from "@/lib/base-path";

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? apiBaseUrl;

export class ApiError extends Error {
  public status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

/** Network-layer failure (server unreachable, DNS, TLS) — no HTTP status. */
export class NetworkError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NetworkError";
  }
}

function createApiUrl(endpoint: string): string {
  return `${API_BASE_URL}${endpoint}`;
}

let refreshPromise: Promise<void> | null = null;

async function doFetch(
  endpoint: string,
  method: string,
  body?: unknown,
  headers?: Record<string, string>,
): Promise<Response> {
  try {
    return await fetch(createApiUrl(endpoint), {
      method,
      headers: {
        "Content-Type": "application/json",
        ...headers,
      },
      body: body ? JSON.stringify(body) : undefined,
      credentials: "include",
    });
  } catch {
    // fetch() throws TypeError("Failed to fetch") on DNS failure, connection
    // refused, CORS rejection, etc. The underlying cause isn't available.
    throw new NetworkError("Could not reach the server.");
  }
}

/**
 * Build a user-facing error message from a non-success response. Parses the
 * server's JSON `detail` field only when the body is actually JSON; otherwise
 * returns a status-code-based message. Never returns raw body text —
 * prevents reverse-proxy HTML error pages from leaking into the UI.
 */
async function errorMessage(response: Response): Promise<string> {
  const contentType = response.headers.get("content-type") ?? "";
  const body = await response.text();
  if (contentType.includes("json") || body.trimStart().startsWith("{")) {
    try {
      const parsed = JSON.parse(body) as { detail?: unknown };
      if (typeof parsed.detail === "string" && parsed.detail.trim()) {
        return parsed.detail;
      }
    } catch {
      // Fall through to status-code message.
    }
  }
  switch (response.status) {
    case 400: return "Bad request (HTTP 400)";
    case 403: return "Access denied (HTTP 403)";
    case 404: return "Not found (HTTP 404)";
    case 500: return "Server error (HTTP 500)";
    case 502:
    case 503: return `Service unavailable (HTTP ${response.status})`;
    case 504: return "Server did not respond in time (HTTP 504)";
    default: return `Server returned HTTP ${response.status}`;
  }
}

async function handleResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    throw new ApiError(response.status, await errorMessage(response));
  }

  if (response.status === 204 || response.headers.get("content-length") === "0") {
    return undefined as T;
  }

  return response.json() as Promise<T>;
}

const AUTH_ENDPOINTS = ["/auth/login", "/auth/login/complete", "/auth/register", "/auth/refresh", "/auth/logout"];

function isAuthEndpoint(endpoint: string): boolean {
  return AUTH_ENDPOINTS.some((path) => endpoint.startsWith(path));
}

async function request<T>(
  endpoint: string,
  method: string,
  body?: unknown,
  headers?: Record<string, string>,
): Promise<T> {
  const response = await doFetch(endpoint, method, body, headers);

  if (response.status === 401 && !isAuthEndpoint(endpoint)) {
    // Coalesce concurrent refresh attempts into a single request
    if (!refreshPromise) {
      refreshPromise = doFetch("/auth/refresh", "POST", {})
        .then((r) => {
          if (!r.ok) throw new ApiError(r.status, "Token refresh failed");
        })
        .finally(() => {
          refreshPromise = null;
        });
    }

    try {
      await refreshPromise;
    } catch (err) {
      // A network failure during refresh doesn't mean the session expired —
      // the server was just unreachable. Keep the tokens so the user can
      // retry once connectivity returns, and surface the network error.
      if (err instanceof NetworkError) throw err;
      useAuthStore.getState().logout();
      throw new ApiError(401, "Session expired");
    }

    // Retry original request with fresh cookies
    const retryResponse = await doFetch(endpoint, method, body, headers);
    return handleResponse<T>(retryResponse);
  }

  return handleResponse<T>(response);
}

export const apiClient = {
  request,
  get: <T>(endpoint: string, headers?: Record<string, string>) =>
    request<T>(endpoint, "GET", undefined, headers),
  post: <T>(endpoint: string, body?: unknown, headers?: Record<string, string>) =>
    request<T>(endpoint, "POST", body, headers),
  put: <T>(endpoint: string, body?: unknown, headers?: Record<string, string>) =>
    request<T>(endpoint, "PUT", body, headers),
  delete: <T>(endpoint: string, headers?: Record<string, string>) =>
    request<T>(endpoint, "DELETE", undefined, headers),
  logout: async () => {
    try {
      await doFetch("/auth/logout", "POST", {});
    } catch {
      // Best-effort: clear client state even if server call fails
    }
  },

  /** POST JSON, return raw Response (for blob downloads). */
  postRaw: (endpoint: string, body?: unknown): Promise<Response> =>
    doFetch(endpoint, "POST", body),

  /** POST FormData (for file uploads). */
  postForm: async <T>(endpoint: string, formData: FormData): Promise<T> => {
    const response = await fetch(createApiUrl(endpoint), {
      method: "POST",
      credentials: "include",
      body: formData,
    });
    return handleResponse<T>(response);
  },
};
