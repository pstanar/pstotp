import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";

describe("parseOtpauthUri - missing fields", () => {
  it("throws on missing secret", () => {
    expect(() =>
      parseOtpauthUri("otpauth://totp/GitHub:alice?issuer=GitHub"),
    ).toThrow("Missing required parameter: secret");
  });

  it("throws on invalid protocol", () => {
    expect(() =>
      parseOtpauthUri("https://totp/GitHub:alice?secret=JBSWY3DPEHPK3PXP"),
    ).toThrow("Invalid protocol");
  });

  it("throws on non-TOTP type", () => {
    expect(() =>
      parseOtpauthUri("otpauth://hotp/GitHub:alice?secret=JBSWY3DPEHPK3PXP"),
    ).toThrow("Only TOTP type is supported");
  });
});
