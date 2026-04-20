import { describe, it, expect } from "vitest";
import { parseOtpauthUri } from "@/features/vault/utils/totp";

describe("WebQrImageUpload", () => {
  it("parseOtpauthUri accepts valid TOTP URI from decoded QR image", () => {
    // Simulates what happens after jsQR decodes a QR image:
    // the decoded string is passed to parseOtpauthUri
    const decodedFromImage = "otpauth://totp/Amazon:user@example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=Amazon";

    const result = parseOtpauthUri(decodedFromImage);

    expect(result.issuer).toBe("Amazon");
    expect(result.accountName).toBe("user@example.com");
    expect(result.secret).toBe("HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ");
    expect(result.algorithm).toBe("SHA1"); // default
    expect(result.digits).toBe(6); // default
    expect(result.period).toBe(30); // default
  });

  it("rejects QR image that decodes to non-otpauth content", () => {
    // If a QR image contains a URL or random text, it should be rejected
    expect(() => parseOtpauthUri("https://example.com/login")).toThrow();
    expect(() => parseOtpauthUri("")).toThrow();
  });

  it("handles URI with URL-encoded characters from QR image", () => {
    // QR codes may encode special characters
    const uri = "otpauth://totp/My%20Service:user%2Btag%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=My%20Service";

    const result = parseOtpauthUri(uri);

    expect(result.issuer).toBe("My Service");
    expect(result.accountName).toBe("user+tag@example.com");
    expect(result.secret).toBe("JBSWY3DPEHPK3PXP");
  });
});
