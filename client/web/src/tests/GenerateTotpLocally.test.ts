import { describe, it, expect } from "vitest";
import { generateTotp } from "@/features/vault/utils/totp";

// RFC 6238 test secrets in base32:
// SHA1:   "12345678901234567890"           (20 bytes)
const SHA1_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
// SHA256: "12345678901234567890123456789012" (32 bytes)
const SHA256_SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA";
// SHA512: "1234567890123456789012345678901234567890123456789012345678901234" (64 bytes)
const SHA512_SECRET =
  "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" +
  "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA";

describe("generateTotp", () => {
  it("generates a 6-digit code by default", () => {
    const code = generateTotp(SHA1_SECRET, "SHA1", 6, 30);
    expect(code).toHaveLength(6);
    expect(/^\d{6}$/.test(code)).toBe(true);
  });

  it("generates an 8-digit code when requested", () => {
    const code = generateTotp(SHA1_SECRET, "SHA1", 8, 30);
    expect(code).toHaveLength(8);
    expect(/^\d{8}$/.test(code)).toBe(true);
  });

  it("generates different codes for different time steps", () => {
    const secret = "JBSWY3DPEHPK3PXP";
    const code1 = generateTotp(secret, "SHA1", 6, 30, 1000000);
    const code2 = generateTotp(secret, "SHA1", 6, 30, 1000030);
    expect(code1).not.toBe(code2);
  });

  it("generates same code within the same time step", () => {
    const secret = "JBSWY3DPEHPK3PXP";
    const code1 = generateTotp(secret, "SHA1", 6, 30, 1000000);
    const code2 = generateTotp(secret, "SHA1", 6, 30, 1000015);
    expect(code1).toBe(code2);
  });

  // RFC 6238 Appendix B test vectors (8-digit, 30-second period)
  // Time = 59 → counter = 1
  it("SHA1   t=59 → 94287082", () => {
    expect(generateTotp(SHA1_SECRET, "SHA1", 8, 30, 59)).toBe("94287082");
  });

  it("SHA256 t=59 → 46119246", () => {
    expect(generateTotp(SHA256_SECRET, "SHA256", 8, 30, 59)).toBe("46119246");
  });

  it("SHA512 t=59 → 90693936", () => {
    expect(generateTotp(SHA512_SECRET, "SHA512", 8, 30, 59)).toBe("90693936");
  });

  // Time = 1111111109 → counter = 37037036
  it("SHA1   t=1111111109 → 07081804", () => {
    expect(generateTotp(SHA1_SECRET, "SHA1", 8, 30, 1111111109)).toBe("07081804");
  });

  it("SHA256 t=1111111109 → 68084774", () => {
    expect(generateTotp(SHA256_SECRET, "SHA256", 8, 30, 1111111109)).toBe("68084774");
  });

  it("SHA512 t=1111111109 → 25091201", () => {
    expect(generateTotp(SHA512_SECRET, "SHA512", 8, 30, 1111111109)).toBe("25091201");
  });

  // Time = 1234567890 → counter = 41152263
  it("SHA1   t=1234567890 → 89005924", () => {
    expect(generateTotp(SHA1_SECRET, "SHA1", 8, 30, 1234567890)).toBe("89005924");
  });

  it("SHA256 t=1234567890 → 91819424", () => {
    expect(generateTotp(SHA256_SECRET, "SHA256", 8, 30, 1234567890)).toBe("91819424");
  });

  it("SHA512 t=1234567890 → 93441116", () => {
    expect(generateTotp(SHA512_SECRET, "SHA512", 8, 30, 1234567890)).toBe("93441116");
  });
});
