export interface VaultEntryPlaintext {
  issuer: string;
  accountName: string;
  secret: string;
  algorithm: string;
  digits: number;
  period: number;
  icon?: string; // emoji character or "data:image/..." base64 data URL
}

export interface VaultEntry extends VaultEntryPlaintext {
  id: string;
  version: number;
}
