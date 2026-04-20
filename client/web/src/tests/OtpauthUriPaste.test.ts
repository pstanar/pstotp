import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";

describe("parseOtpauthUri", () => {
  it("parses a standard otpauth URI", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub",
    );
    expect(result.issuer).toBe("GitHub");
    expect(result.accountName).toBe("alice@example.com");
    expect(result.secret).toBe("JBSWY3DPEHPK3PXP");
    expect(result.algorithm).toBe("SHA1");
    expect(result.digits).toBe(6);
    expect(result.period).toBe(30);
  });

  it("extracts issuer from path when param is missing", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/AWS:admin?secret=JBSWY3DPEHPK3PXP",
    );
    expect(result.issuer).toBe("AWS");
    expect(result.accountName).toBe("admin");
  });

  it("uses issuer param over path prefix", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/OldName:alice?secret=JBSWY3DPEHPK3PXP&issuer=NewName",
    );
    expect(result.issuer).toBe("NewName");
  });

  it("handles custom algorithm, digits, and period", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/Test:user?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60",
    );
    expect(result.algorithm).toBe("SHA256");
    expect(result.digits).toBe(8);
    expect(result.period).toBe(60);
  });
});
