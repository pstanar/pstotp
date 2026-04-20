import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";

describe("parseOtpauthUri - non-standard parameters", () => {
  it("ignores unknown parameters", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP&color=blue&custom=123",
    );
    expect(result.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(result.issuer).toBe("GitHub");
  });

  it("rejects unsupported algorithm", () => {
    expect(() =>
      parseOtpauthUri(
        "otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&algorithm=MD5",
      ),
    ).toThrow("Unsupported algorithm");
  });

  it("rejects unsupported digits value", () => {
    expect(() =>
      parseOtpauthUri(
        "otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&digits=2",
      ),
    ).toThrow("Unsupported digits");
  });

  it("rejects invalid period", () => {
    expect(() =>
      parseOtpauthUri(
        "otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&period=0",
      ),
    ).toThrow("Invalid period");
  });
});
