import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";

describe("parseOtpauthUri - URL-encoded values", () => {
  it("decodes URL-encoded issuer and account name", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/My%20Company:alice%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=My%20Company",
    );
    expect(result.issuer).toBe("My Company");
    expect(result.accountName).toBe("alice@example.com");
  });

  it("handles plus signs in account name", () => {
    const result = parseOtpauthUri(
      "otpauth://totp/Service:user%2Bsuffix%40example.com?secret=JBSWY3DPEHPK3PXP",
    );
    expect(result.accountName).toBe("user+suffix@example.com");
  });
});
