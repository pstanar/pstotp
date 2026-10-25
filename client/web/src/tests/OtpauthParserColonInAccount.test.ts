import { describe, it, expect } from "vitest";
import { parseOtpauthUri, resolveOtpauthLabel } from "@/features/vault/utils/totp";
import { buildOtpauthUri } from "@/features/vault/utils/otpauth-uri";

const SECRET = "JBSWY3DPEHPK3PXP";
const entry = (issuer: string, accountName: string) => ({
  issuer,
  accountName,
  secret: SECRET,
  algorithm: "SHA1",
  digits: 6,
  period: 30,
});

describe("otpauth label handling - colon in account name", () => {
  it("keeps a colon that belongs to the account name when issuer is a query param", () => {
    const parsed = parseOtpauthUri(buildOtpauthUri(entry("Corp", "bob: work")));
    expect(parsed.issuer).toBe("Corp");
    expect(parsed.accountName).toBe("bob: work");
  });

  it("roundtrips account names containing colons", () => {
    for (const account of ["bob: work", "a:b:c", "https://example.com:8080", ":leading", "trailing:"]) {
      const parsed = parseOtpauthUri(buildOtpauthUri(entry("Corp", account)));
      expect(parsed.issuer).toBe("Corp");
      expect(parsed.accountName).toBe(account);
    }
  });

  it("still strips a redundant issuer prefix (literal or encoded colon, any case)", () => {
    for (const label of ["Corp:bob", "Corp%3Abob", "corp:bob", "Corp: bob"]) {
      const parsed = parseOtpauthUri(`otpauth://totp/${label}?secret=${SECRET}&issuer=Corp`);
      expect(parsed.issuer).toBe("Corp");
      expect(parsed.accountName).toBe("bob");
    }
  });

  it("keeps the whole label when its prefix is not the issuer", () => {
    const parsed = parseOtpauthUri(`otpauth://totp/Old:alice?secret=${SECRET}&issuer=New`);
    expect(parsed.issuer).toBe("New");
    expect(parsed.accountName).toBe("Old:alice");
  });

  it("splits Issuer:Account on the first colon when there is no issuer param", () => {
    expect(resolveOtpauthLabel("GitHub:octocat", null)).toEqual({ issuer: "GitHub", accountName: "octocat" });
    expect(resolveOtpauthLabel("GitHub: octocat:x", null)).toEqual({ issuer: "GitHub", accountName: "octocat:x" });
    expect(resolveOtpauthLabel("octocat", null)).toEqual({ issuer: "", accountName: "octocat" });
  });

  it("treats a blank issuer param as absent", () => {
    expect(resolveOtpauthLabel("GitHub:octocat", "")).toEqual({ issuer: "GitHub", accountName: "octocat" });
    expect(resolveOtpauthLabel("GitHub:octocat", "  ")).toEqual({ issuer: "GitHub", accountName: "octocat" });
  });
});
