import { describe, it, expect } from "vitest";
import {
  tryParseGoogleAuthMigration,
  tryParseAegis,
  tryParse2Fas,
} from "@/features/vault/utils/external-imports";

// --- Tiny protobuf builder (mirror of the Android test helper) ------------

class ProtoBuilder {
  private parts: Uint8Array[] = [];

  varintField(field: number, value: number): this {
    this.writeTag(field, 0);
    this.writeVarint(BigInt(value));
    return this;
  }

  stringField(field: number, value: string): this {
    return this.bytesField(field, new TextEncoder().encode(value));
  }

  bytesField(field: number, value: Uint8Array): this {
    this.writeTag(field, 2);
    this.writeVarint(BigInt(value.length));
    this.parts.push(value);
    return this;
  }

  build(): Uint8Array {
    const total = this.parts.reduce((n, p) => n + p.length, 0);
    const out = new Uint8Array(total);
    let offset = 0;
    for (const p of this.parts) { out.set(p, offset); offset += p.length; }
    return out;
  }

  private writeTag(field: number, wire: number) {
    this.writeVarint(BigInt((field << 3) | wire));
  }

  private writeVarint(v: bigint) {
    const bytes: number[] = [];
    let value = v;
    while ((value & ~0x7fn) !== 0n) {
      bytes.push(Number((value & 0x7fn) | 0x80n));
      value >>= 7n;
    }
    bytes.push(Number(value));
    this.parts.push(new Uint8Array(bytes));
  }
}

function u8ToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

// Base32 decoder (for the test to produce expected `secret` values).
const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
function base32Decode(s: string): Uint8Array {
  const cleaned = s.replace(/=/g, "").toUpperCase();
  let bits = "";
  for (const c of cleaned) {
    const v = BASE32.indexOf(c);
    if (v < 0) throw new Error(`bad base32: ${c}`);
    bits += v.toString(2).padStart(5, "0");
  }
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) {
    bytes.push(parseInt(bits.slice(i, i + 8), 2));
  }
  return new Uint8Array(bytes);
}

// --- Google Authenticator -------------------------------------------------

describe("tryParseGoogleAuthMigration", () => {
  it("decodes two entries with different algorithms and digit counts", () => {
    const secret1 = base32Decode("JBSWY3DPEHPK3PXP");
    const secret2 = base32Decode("NBSWY3DPFQQHO33SNRSCC");

    const otp1 = new ProtoBuilder()
      .bytesField(1, secret1)
      .stringField(2, "alice@example.com")
      .stringField(3, "Example")
      .varintField(4, 1) // SHA1
      .varintField(5, 1) // SIX
      .varintField(6, 2) // TOTP
      .build();

    const otp2 = new ProtoBuilder()
      .bytesField(1, secret2)
      .stringField(2, "bob")
      .stringField(3, "")
      .varintField(4, 2) // SHA256
      .varintField(5, 2) // EIGHT
      .varintField(6, 2) // TOTP
      .build();

    const payload = new ProtoBuilder()
      .bytesField(1, otp1)
      .bytesField(1, otp2)
      .varintField(2, 1)
      .build();

    const uri = `otpauth-migration://offline?data=${encodeURIComponent(u8ToBase64(payload))}`;
    const entries = tryParseGoogleAuthMigration(uri);

    expect(entries).not.toBeNull();
    expect(entries).toHaveLength(2);
    expect(entries![0]).toMatchObject({
      issuer: "Example",
      accountName: "alice@example.com",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: "SHA1",
      digits: 6,
    });
    expect(entries![1]).toMatchObject({
      accountName: "bob",
      secret: "NBSWY3DPFQQHO33SNRSCC",
      algorithm: "SHA256",
      digits: 8,
    });
  });

  it("splits Issuer:account when the issuer field is empty", () => {
    const otp = new ProtoBuilder()
      .bytesField(1, base32Decode("JBSWY3DPEHPK3PXP"))
      .stringField(2, "GitHub:octocat")
      .stringField(3, "")
      .varintField(4, 1).varintField(5, 1).varintField(6, 2)
      .build();
    const payload = new ProtoBuilder().bytesField(1, otp).build();
    const uri = `otpauth-migration://offline?data=${encodeURIComponent(u8ToBase64(payload))}`;

    const entries = tryParseGoogleAuthMigration(uri);
    expect(entries).toHaveLength(1);
    expect(entries![0]).toMatchObject({ issuer: "GitHub", accountName: "octocat" });
  });

  it("strips redundant issuer prefix from name when it matches the issuer field", () => {
    const otp = new ProtoBuilder()
      .bytesField(1, base32Decode("JBSWY3DPEHPK3PXP"))
      .stringField(2, "GitHub:octocat") // redundant prefix
      .stringField(3, "GitHub")          // explicit issuer matches
      .varintField(4, 1).varintField(5, 1).varintField(6, 2)
      .build();
    const payload = new ProtoBuilder().bytesField(1, otp).build();
    const uri = `otpauth-migration://offline?data=${encodeURIComponent(u8ToBase64(payload))}`;

    const entries = tryParseGoogleAuthMigration(uri)!;
    expect(entries[0]).toMatchObject({ issuer: "GitHub", accountName: "octocat" });
  });

  it("keeps colons in account when the prefix doesn't match the issuer", () => {
    // Legit colon inside the account — don't misread it as "Issuer:account".
    const otp = new ProtoBuilder()
      .bytesField(1, base32Decode("JBSWY3DPEHPK3PXP"))
      .stringField(2, "work:alice")
      .stringField(3, "Company")
      .varintField(4, 1).varintField(5, 1).varintField(6, 2)
      .build();
    const payload = new ProtoBuilder().bytesField(1, otp).build();
    const uri = `otpauth-migration://offline?data=${encodeURIComponent(u8ToBase64(payload))}`;

    const entries = tryParseGoogleAuthMigration(uri)!;
    expect(entries[0]).toMatchObject({ issuer: "Company", accountName: "work:alice" });
  });

  it("filters out HOTP entries", () => {
    const otp = new ProtoBuilder()
      .bytesField(1, base32Decode("JBSWY3DPEHPK3PXP"))
      .stringField(2, "counter-based")
      .stringField(3, "Bank")
      .varintField(4, 1).varintField(5, 1)
      .varintField(6, 1) // HOTP
      .build();
    const payload = new ProtoBuilder().bytesField(1, otp).build();
    const uri = `otpauth-migration://offline?data=${encodeURIComponent(u8ToBase64(payload))}`;

    expect(tryParseGoogleAuthMigration(uri)).toEqual([]);
  });

  it("returns null for non-migration URIs", () => {
    expect(tryParseGoogleAuthMigration("otpauth://totp/foo?secret=JBSW")).toBeNull();
    expect(tryParseGoogleAuthMigration("https://example.com")).toBeNull();
  });
});

// --- Aegis ----------------------------------------------------------------

describe("tryParseAegis", () => {
  it("parses a plain export", () => {
    const json = {
      version: 1,
      header: { slots: null, params: null },
      db: {
        version: 3,
        entries: [
          {
            type: "totp",
            name: "alice@example.com",
            issuer: "Example",
            info: {
              secret: "jbswy3dpehpk3pxp",
              algo: "sha1",
              digits: 6,
              period: 30,
            },
          },
          {
            type: "hotp",
            name: "counter",
            issuer: "Bank",
            info: { secret: "X", algo: "SHA1", digits: 6, counter: 0 },
          },
        ],
      },
    };
    const entries = tryParseAegis(json);
    expect(entries).not.toBeNull();
    expect(entries).toHaveLength(1); // HOTP filtered
    expect(entries![0]).toMatchObject({
      issuer: "Example",
      accountName: "alice@example.com",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    });
  });

  it("rejects shapes without header", () => {
    const json = { db: { entries: [{ type: "totp", info: { secret: "X" } }] } };
    expect(tryParseAegis(json)).toBeNull();
  });
});

// --- 2FAS -----------------------------------------------------------------

describe("tryParse2Fas", () => {
  it("parses an export with otp subobject", () => {
    const json = {
      schemaVersion: 4,
      appVersionCode: 500000,
      services: [
        {
          secret: "JBSWY3DPEHPK3PXP",
          name: "Example",
          otp: {
            account: "alice@example.com",
            issuer: "Example",
            digits: 6,
            period: 30,
            algorithm: "SHA1",
          },
        },
      ],
    };
    const entries = tryParse2Fas(json);
    expect(entries).toHaveLength(1);
    expect(entries![0]).toMatchObject({
      issuer: "Example",
      accountName: "alice@example.com",
      secret: "JBSWY3DPEHPK3PXP",
    });
  });

  it("falls back to name when otp.account is missing", () => {
    const json = {
      schemaVersion: 3,
      services: [{ secret: "JBSWY3DPEHPK3PXP", name: "Legacy Service" }],
    };
    const entries = tryParse2Fas(json);
    expect(entries).toHaveLength(1);
    expect(entries![0]).toMatchObject({
      issuer: "Legacy Service",
      accountName: "Legacy Service",
    });
  });

  it("rejects shapes without schemaVersion", () => {
    const json = { services: [{ secret: "X" }] };
    expect(tryParse2Fas(json)).toBeNull();
  });
});
