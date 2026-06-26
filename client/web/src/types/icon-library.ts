/**
 * One custom icon in the user's library. `data` is a data-URL PNG
 * (the same format `VaultEntryPlaintext.icon` accepts), already
 * normalised to 64×64 at upload time.
 */
export interface LibraryIcon {
  id: string;          // client-generated UUID
  label: string;       // user-facing; defaults to filename
  data: string;        // "data:image/png;base64,…"
  createdAt: string;   // ISO-8601 UTC
  // De-duplication fingerprints. Both optional for back-compat: legacy
  // blobs predate them, and cross-client reads must tolerate their
  // absence. `dataHash` is always computable from `data` (backfilled on
  // load); `sourceHash` is only known when the original pre-resize bytes
  // were in hand (uploads, URL fetches, embedded import icons) — absent
  // for legacy icons. Dedup matches if EITHER hash matches.
  dataHash?: string;   // SHA-256 hex of `data`
  sourceHash?: string; // SHA-256 hex of the raw source bytes, pre-resize
}

/**
 * The decrypted library. `version` is the blob-format version (bump
 * when the JSON shape changes); the server's monotonic version is
 * tracked separately in the store.
 */
export interface IconLibraryBlob {
  version: 1;
  icons: LibraryIcon[];
}

/**
 * Hard caps. Two gates, because icon count is only a proxy for the real
 * constraint — the server rejects any encrypted blob over 2 MB
 * (VaultIconLibraryEndpoints.MaxEncryptedPayloadBytes). Typical 64×64
 * PNG logos are small, but worst-case icons can blow the byte budget
 * before the count cap. Callers must check both and fail gracefully
 * rather than letting the server 400 mid-write.
 */
export const MAX_LIBRARY_ICONS = 100;
export const MAX_LIBRARY_BYTES = 2 * 1024 * 1024;
