import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";
import { buildOtpauthUri } from "@/features/vault/utils/otpauth-uri";

describe("otpauth URI roundtrip", () => {
  it("roundtrips a standard entry", () => {
    const entry = {
      issuer: "GitHub",
      accountName: "alice@example.com",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    };

    const uri = buildOtpauthUri(entry);
    const parsed = parseOtpauthUri(uri);

    expect(parsed.issuer).toBe(entry.issuer);
    expect(parsed.accountName).toBe(entry.accountName);
    expect(parsed.secret).toBe(entry.secret);
    expect(parsed.algorithm).toBe(entry.algorithm);
    expect(parsed.digits).toBe(entry.digits);
    expect(parsed.period).toBe(entry.period);
  });

  it("roundtrips with non-default algorithm and digits", () => {
    const entry = {
      issuer: "Bank",
      accountName: "user123",
      secret: "ABCDEFGHIJKLMNOP",
      algorithm: "SHA256",
      digits: 8,
      period: 60,
    };

    const uri = buildOtpauthUri(entry);
    const parsed = parseOtpauthUri(uri);

    expect(parsed.algorithm).toBe("SHA256");
    expect(parsed.digits).toBe(8);
    expect(parsed.period).toBe(60);
  });

  it("handles special characters in issuer and account", () => {
    const entry = {
      issuer: "My Company & Co.",
      accountName: "user+tag@example.com",
      secret: "JBSWY3DPEHPK3PXP",
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    };

    const uri = buildOtpauthUri(entry);
    const parsed = parseOtpauthUri(uri);

    expect(parsed.issuer).toBe(entry.issuer);
    expect(parsed.accountName).toBe(entry.accountName);
  });

  it("always includes algorithm/digits/period in URI", () => {
    const entry = {
      issuer: "Test",
      accountName: "user",
      secret: "ABC",
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    };

    const uri = buildOtpauthUri(entry);

    expect(uri).toContain("algorithm=SHA1");
    expect(uri).toContain("digits=6");
    expect(uri).toContain("period=30");
    expect(uri).toContain("secret=ABC");
    expect(uri).toContain("issuer=Test");
  });
});
