import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";
import { buildOtpauthUri } from "@/features/vault/utils/otpauth-uri";

describe("WebQrEnrollment", () => {
  it("parses a scanned otpauth URI into vault entry fields", () => {
    const uri = "otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30";

    const parsed = parseOtpauthUri(uri);

    expect(parsed.issuer).toBe("GitHub");
    expect(parsed.accountName).toBe("alice@example.com");
    expect(parsed.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(parsed.algorithm).toBe("SHA1");
    expect(parsed.digits).toBe(6);
    expect(parsed.period).toBe(30);
  });

  it("scanned entry can be reconstructed back to valid otpauth URI", () => {
    const original = {
      issuer: "Google",
      accountName: "user@gmail.com",
      secret: "ABCDEFGHIJKLMNOP",
      algorithm: "SHA1",
      digits: 6,
      period: 30,
    };

    const uri = buildOtpauthUri(original);
    const roundtripped = parseOtpauthUri(uri);

    expect(roundtripped.issuer).toBe(original.issuer);
    expect(roundtripped.accountName).toBe(original.accountName);
    expect(roundtripped.secret).toBe(original.secret);
  });

  it("rejects invalid QR content that is not an otpauth URI", () => {
    expect(() => parseOtpauthUri("https://example.com")).toThrow();
    expect(() => parseOtpauthUri("not a uri at all")).toThrow();
    expect(() => parseOtpauthUri("otpauth://hotp/Test?secret=ABC")).toThrow("Only TOTP");
  });
});
