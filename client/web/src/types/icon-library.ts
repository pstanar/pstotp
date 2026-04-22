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

/** Hard cap — matches the server's size expectation. */
export const MAX_LIBRARY_ICONS = 100;
