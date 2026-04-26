import type { VaultEntryPlaintext } from "@/types/vault-types";

export function buildOtpauthUri(entry: VaultEntryPlaintext): string {
  // Fall back to the issuer when the account is blank — `otpauth://totp/?…`
  // with an empty path segment isn't accepted by every importer, and the
  // account is now genuinely optional from the user's POV.
  const label = encodeURIComponent(entry.accountName || entry.issuer || "Account");

  const params = new URLSearchParams();
  params.set("secret", entry.secret);
  if (entry.issuer) params.set("issuer", entry.issuer);
  params.set("algorithm", entry.algorithm || "SHA1");
  params.set("digits", String(entry.digits || 6));
  params.set("period", String(entry.period || 30));

  return `otpauth://totp/${label}?${params.toString()}`;
}
