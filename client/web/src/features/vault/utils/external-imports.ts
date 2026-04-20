import type { VaultEntryPlaintext } from "@/types/vault-types";

/**
 * Parsers for third-party TOTP export formats, mirroring the Android
 * implementation in core/model/ExternalImports.kt. Each `tryParseX`
 * returns null when the content doesn't look like the given format so
 * the caller can probe them in turn.
 *
 * Supported:
 *   - otpauth-migration:// URIs (Google Authenticator export)
 *   - Aegis plain (unencrypted) JSON
 *   - 2FAS JSON
 */

const BASE32_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32Encode(bytes: Uint8Array): string {
  if (bytes.length === 0) return "";
  let bits = "";
  for (const b of bytes) {
    bits += b.toString(2).padStart(8, "0");
  }
  // Right-pad to a multiple of 5 so every 5-bit group is a full index.
  while (bits.length % 5 !== 0) bits += "0";
  let out = "";
  for (let i = 0; i < bits.length; i += 5) {
    out += BASE32_CHARS[parseInt(bits.slice(i, i + 5), 2)];
  }
  return out;
}

// --- Google Authenticator -------------------------------------------------

export function tryParseGoogleAuthMigration(content: string): VaultEntryPlaintext[] | null {
  const line = content.trim();
  if (!line.startsWith("otpauth-migration://")) return null;

  const url = new URL(line);
  const dataParam = url.searchParams.get("data");
  if (!dataParam) return null;

  const bytes = base64Decode(dataParam);
  return parseMigrationPayload(bytes);
}

function base64Decode(b64: string): Uint8Array {
  // atob expects standard base64. URLSearchParams already decoded any URL-
  // escaping, but we still handle URL-safe variants defensively.
  const normalised = b64.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalised);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function parseMigrationPayload(bytes: Uint8Array): VaultEntryPlaintext[] {
  const r = new ProtoReader(bytes);
  const out: VaultEntryPlaintext[] = [];
  while (!r.eof()) {
    const { field, wire } = r.readTag();
    if (field === 1 && wire === WIRE_LEN) {
      const entry = parseOtpParameters(r.readLengthDelimited());
      if (entry) out.push(entry);
    } else {
      r.skipField(wire);
    }
  }
  return out;
}

function parseOtpParameters(bytes: Uint8Array): VaultEntryPlaintext | null {
  const r = new ProtoReader(bytes);
  let secret = new Uint8Array(0);
  let name = "";
  let issuer = "";
  let algo = 1;
  let digits = 1;
  let type = 2;
  while (!r.eof()) {
    const { field, wire } = r.readTag();
    switch (field) {
      case 1: secret = r.readLengthDelimited(); break;
      case 2: name = new TextDecoder().decode(r.readLengthDelimited()); break;
      case 3: issuer = new TextDecoder().decode(r.readLengthDelimited()); break;
      case 4: algo = Number(r.readVarint()); break;
      case 5: digits = Number(r.readVarint()); break;
      case 6: type = Number(r.readVarint()); break;
      default: r.skipField(wire);
    }
  }
  if (type !== 2) return null; // HOTP — we only import TOTP
  const algorithmName = algo === 2 ? "SHA256" : algo === 3 ? "SHA512" : "SHA1";
  const digitCount = digits === 2 ? 8 : 6;
  const { resolvedIssuer, resolvedAccount } = resolveIssuerAndAccount(issuer, name);
  return {
    issuer: resolvedIssuer || "Unknown",
    accountName: resolvedAccount || resolvedIssuer || "Account",
    secret: base32Encode(secret),
    algorithm: algorithmName,
    digits: digitCount,
    period: 30,
  };
}

/**
 * Google Authenticator is inconsistent about what it puts in the `name`
 * field when `issuer` is also populated: sometimes just the account,
 * sometimes "Issuer:account" duplicated. Rule here:
 *   - no colon in name                 → use name as-is
 *   - issuer blank + colon in name     → split "Issuer:account"
 *   - issuer matches prefix before ':' → strip the redundant prefix
 *   - otherwise                        → the colon is part of the
 *                                        account itself, leave name alone
 */
function resolveIssuerAndAccount(
  issuer: string,
  name: string,
): { resolvedIssuer: string; resolvedAccount: string } {
  const colonIndex = name.indexOf(":");
  if (colonIndex < 0) return { resolvedIssuer: issuer, resolvedAccount: name };
  const before = name.slice(0, colonIndex).trim();
  const after = name.slice(colonIndex + 1).trim();
  if (!issuer) return { resolvedIssuer: before, resolvedAccount: after };
  if (before.toLowerCase() === issuer.toLowerCase()) {
    return { resolvedIssuer: issuer, resolvedAccount: after };
  }
  return { resolvedIssuer: issuer, resolvedAccount: name };
}

// --- Aegis (plain / unencrypted) ------------------------------------------

export function tryParseAegis(json: unknown): VaultEntryPlaintext[] | null {
  if (!isRecord(json)) return null;
  const db = json.db;
  if (!isRecord(db) || !Array.isArray(db.entries)) return null;
  // Require the top-level "header" too so we don't claim any JSON that
  // coincidentally has db.entries.
  if (!("header" in json)) return null;

  const out: VaultEntryPlaintext[] = [];
  for (const e of db.entries) {
    if (!isRecord(e)) continue;
    if (e.type !== "totp") continue;
    const info = e.info;
    if (!isRecord(info)) continue;
    const secret = typeof info.secret === "string" ? info.secret : null;
    if (!secret) continue;
    out.push({
      issuer: (typeof e.issuer === "string" && e.issuer) || "Unknown",
      accountName: (typeof e.name === "string" && e.name) || "Account",
      secret: secret.toUpperCase(),
      algorithm: String(info.algo ?? "SHA1").toUpperCase(),
      digits: typeof info.digits === "number" ? info.digits : 6,
      period: typeof info.period === "number" ? info.period : 30,
    });
  }
  return out.length > 0 ? out : null;
}

// --- 2FAS -----------------------------------------------------------------

export function tryParse2Fas(json: unknown): VaultEntryPlaintext[] | null {
  if (!isRecord(json)) return null;
  if (!Array.isArray(json.services)) return null;
  // schemaVersion is 2FAS's anchor — prevents claiming any JSON that
  // happens to have a "services" array.
  if (!("schemaVersion" in json)) return null;

  const out: VaultEntryPlaintext[] = [];
  for (const svc of json.services) {
    if (!isRecord(svc)) continue;
    const secret = typeof svc.secret === "string" ? svc.secret : null;
    if (!secret) continue;
    const otp = isRecord(svc.otp) ? svc.otp : {};
    const issuer = (typeof otp.issuer === "string" && otp.issuer)
      || (typeof svc.name === "string" ? svc.name : "")
      || "Unknown";
    const account = (typeof otp.account === "string" && otp.account)
      || (typeof svc.name === "string" ? svc.name : "")
      || issuer;
    out.push({
      issuer,
      accountName: account,
      secret: secret.toUpperCase(),
      algorithm: String(otp.algorithm ?? "SHA1").toUpperCase(),
      digits: typeof otp.digits === "number" ? otp.digits : 6,
      period: typeof otp.period === "number" ? otp.period : 30,
    });
  }
  return out.length > 0 ? out : null;
}

// --- Minimal protobuf reader ---------------------------------------------

const WIRE_VARINT = 0;
const WIRE_LEN = 2;

class ProtoReader {
  // Explicit field declarations (not parameter properties) — the project
  // has erasableSyntaxOnly enabled, which forbids TS-only parameter-property
  // shorthand that requires emit transformation.
  private pos = 0;
  private readonly buf: Uint8Array;

  constructor(buf: Uint8Array) {
    this.buf = buf;
  }

  eof(): boolean {
    return this.pos >= this.buf.length;
  }

  readTag(): { field: number; wire: number } {
    const tag = Number(this.readVarint());
    return { field: tag >>> 3, wire: tag & 0x7 };
  }

  readVarint(): bigint {
    let result = 0n;
    let shift = 0n;
    while (true) {
      if (this.pos >= this.buf.length) throw new Error("truncated varint");
      const b = this.buf[this.pos++];
      result |= BigInt(b & 0x7f) << shift;
      if ((b & 0x80) === 0) return result;
      shift += 7n;
      if (shift > 63n) throw new Error("varint too long");
    }
  }

  // Return type is inferred as Uint8Array<ArrayBuffer> — TS 5.7+ makes
  // bare `Uint8Array` in a signature default to Uint8Array<ArrayBufferLike>,
  // which then won't assign back to a fresh Uint8Array<ArrayBuffer> variable.
  // Allocating a new one and letting TS infer keeps the narrower type.
  readLengthDelimited() {
    const len = Number(this.readVarint());
    if (len < 0 || this.pos + len > this.buf.length) {
      throw new Error("bad length-delimited");
    }
    const out = new Uint8Array(len);
    out.set(this.buf.subarray(this.pos, this.pos + len));
    this.pos += len;
    return out;
  }

  skipField(wire: number): void {
    switch (wire) {
      case WIRE_VARINT: this.readVarint(); break;
      case 1: this.skipBytes(8); break;       // fixed64
      case WIRE_LEN: this.readLengthDelimited(); break;
      case 5: this.skipBytes(4); break;       // fixed32
      default: throw new Error(`unsupported wire type ${wire}`);
    }
  }

  private skipBytes(n: number): void {
    if (this.pos + n > this.buf.length) throw new Error("truncated fixed-width field");
    this.pos += n;
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}
