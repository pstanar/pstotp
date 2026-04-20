import { describe, it, expect } from "vitest";
import { guidToBytes } from "@/lib/crypto";

describe("guidToBytes", () => {
  it("converts a GUID to .NET mixed-endian byte array", () => {
    // .NET: new Guid("01020304-0506-0708-090a-0b0c0d0e0f10").ToByteArray()
    // = [04,03,02,01, 06,05, 08,07, 09,0a, 0b,0c,0d,0e,0f,10]
    const bytes = guidToBytes("01020304-0506-0708-090a-0b0c0d0e0f10");
    expect(Array.from(bytes)).toEqual([
      0x04, 0x03, 0x02, 0x01, // first 4 bytes LE
      0x06, 0x05,             // next 2 bytes LE
      0x08, 0x07,             // next 2 bytes LE
      0x09, 0x0a,             // next 2 bytes BE
      0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, // last 6 bytes BE
    ]);
  });

  it("converts a zero GUID", () => {
    const bytes = guidToBytes("00000000-0000-0000-0000-000000000000");
    expect(Array.from(bytes)).toEqual(new Array(16).fill(0));
  });

  it("converts a real-world GUID", () => {
    // .NET: new Guid("a1b2c3d4-e5f6-7890-abcd-ef0123456789").ToByteArray()
    // = [d4,c3,b2,a1, f6,e5, 90,78, ab,cd, ef,01,23,45,67,89]
    const bytes = guidToBytes("a1b2c3d4-e5f6-7890-abcd-ef0123456789");
    expect(Array.from(bytes)).toEqual([
      0xd4, 0xc3, 0xb2, 0xa1,
      0xf6, 0xe5,
      0x90, 0x78,
      0xab, 0xcd,
      0xef, 0x01, 0x23, 0x45, 0x67, 0x89,
    ]);
  });

  it("throws for invalid GUID", () => {
    expect(() => guidToBytes("not-a-guid")).toThrow("Invalid GUID");
  });

  it("produces exactly 16 bytes", () => {
    const bytes = guidToBytes("550e8400-e29b-41d4-a716-446655440000");
    expect(bytes.length).toBe(16);
  });
});
