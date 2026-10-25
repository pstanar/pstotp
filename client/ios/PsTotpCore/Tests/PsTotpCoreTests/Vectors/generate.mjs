// Generates crypto known-answer vectors for the Swift port from Node's built-in
// crypto (same primitives the web client uses via Web Crypto / hash-wasm).
// Usage: node generate.mjs > crypto-vectors.json
import { createHmac, hkdfSync, argon2Sync, createHash, createCipheriv } from "node:crypto";

const hex = (b) => Buffer.from(b).toString("hex");
const bytes = (n, f) => Buffer.from(Array.from({ length: n }, (_, i) => f(i)));

// HKDF-SHA256, empty salt, UTF-8 context string as info (matches web hkdfDerive).
const hkdf = (ikm, info, len = 32) =>
  Buffer.from(hkdfSync("sha256", ikm, Buffer.alloc(0), Buffer.from(info, "utf8"), len));

const ikm = bytes(32, (i) => i);
const authKey = bytes(32, (i) => i);
const contexts = [
  "auth-verifier-v1",
  "vault-password-envelope-v1",
  "totp-vault-recovery-unlock-v1",
  "device-envelope-v1",
];

const argon = (password, salt, memKb, t, p) =>
  Buffer.from(
    argon2Sync("argon2id", {
      message: Buffer.from(password, "utf8"),
      nonce: salt,
      memory: memKb,
      passes: t,
      parallelism: p,
      tagLength: 32,
    }),
  );

// RFC 4226/6238 reference HOTP using the same truncation as the apps.
const totp = (secretBytes, alg, digits, period, ts) => {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(ts / period)));
  const h = createHmac(alg, secretBytes).update(counter).digest();
  const o = h[h.length - 1] & 0x0f;
  const code =
    ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return String(code % 10 ** digits).padStart(digits, "0");
};
const ascii = (s) => Buffer.from(s, "ascii");
const rfc = {
  SHA1: ascii("12345678901234567890"),
  SHA256: ascii("12345678901234567890123456789012"),
  SHA512: ascii("1234567890123456789012345678901234567890123456789012345678901234"),
};
const times = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000];


// --- Export / import fixtures -------------------------------------------------
const exportEntries = [
  { issuer: "Example", accountName: "alice@example.com", secret: "JBSWY3DPEHPK3PXP", algorithm: "SHA1", digits: 6, period: 30 },
  { issuer: "Bank/Corp", accountName: "bob: work", secret: "NBSWY3DPFQQHO33SNRSCC", algorithm: "SHA256", digits: 8, period: 60, icon: "🏦" },
];
// pstotp-export: Argon2id(app params) -> HKDF("vault-password-envelope-v1") -> AES-256-GCM,
// ciphertext+tag and nonce base64'd separately (web client import-export format).
const exportPassword = "export pässword 🔐";
const exportSalt = bytes(16, (i) => 0xa0 + i);
const exportNonce = bytes(12, (i) => 0x30 + i);
const exportKey = hkdf(argon(exportPassword, exportSalt, 65536, 3, 4), "vault-password-envelope-v1");
const gcm = createCipheriv("aes-256-gcm", exportKey, exportNonce);
const exportCt = Buffer.concat([gcm.update(JSON.stringify(exportEntries), "utf8"), gcm.final(), gcm.getAuthTag()]);

// Google Authenticator migration payload (protobuf), with '+' / '=' percent-encoded like the real app.
const varint = (n) => { const o = []; while (n > 0x7f) { o.push((n & 0x7f) | 0x80); n >>>= 7; } o.push(n); return Buffer.from(o); };
const lenField = (f, buf) => Buffer.concat([varint((f << 3) | 2), varint(buf.length), buf]);
const intField = (f, v) => Buffer.concat([varint(f << 3), varint(v)]);
const otp = (secret, name, issuer, algo, digits) => Buffer.concat([
  lenField(1, secret), lenField(2, Buffer.from(name)), lenField(3, Buffer.from(issuer)),
  intField(4, algo), intField(5, digits), intField(6, 2)]);
const migration = Buffer.concat([
  lenField(1, otp(Buffer.from(base32decode("JBSWY3DPEHPK3PXP")), "alice@example.com", "Example", 1, 1)),
  lenField(1, otp(Buffer.from(base32decode("NBSWY3DPFQQHO33SNRSCC")), "bob", "", 2, 2)),
  intField(2, 1),
]);
const migrationUri = "otpauth-migration://offline?data=" + encodeURIComponent(migration.toString("base64"));

const salt16 = bytes(16, (i) => i + 1);
const out = {
  hkdf: [
    // RFC 5869 test case 3 (zero-length salt/info) cross-checks the empty-salt behaviour.
    { ikmHex: hex(Buffer.alloc(22, 0x0b)), info: "", length: 42, okmHex: hex(hkdf(Buffer.alloc(22, 0x0b), "", 42)) },
    ...contexts.map((c) => ({ ikmHex: hex(ikm), info: c, length: 32, okmHex: hex(hkdf(ikm, c)) })),
    { ikmHex: hex(ikm), info: "test", length: 64, okmHex: hex(hkdf(ikm, "test", 64)) },
  ],
  hmacSha256: [
    { keyHex: hex(bytes(32, () => 0x0b)), messageHex: hex(Buffer.from("test message")),
      macHex: hex(createHmac("sha256", bytes(32, () => 0x0b)).update("test message").digest()) },
  ],
  sha256: [
    { inputHex: "", digestHex: hex(createHash("sha256").update("").digest()) },
    { inputHex: hex(Buffer.from("abc")), digestHex: hex(createHash("sha256").update("abc").digest()) },
  ],
  argon2id: [
    // App parameters: 64 MiB, t=3, p=4, 32-byte output.
    { password: "correct horse battery staple", saltHex: hex(salt16), memoryKb: 65536, iterations: 3, parallelism: 4, hashHex: hex(argon("correct horse battery staple", salt16, 65536, 3, 4)) },
    { password: "pässwörd-日本語-🔑", saltHex: hex(salt16), memoryKb: 65536, iterations: 3, parallelism: 4, hashHex: hex(argon("pässwörd-日本語-🔑", salt16, 65536, 3, 4)) },
    // Non-default parameters, as a server may supply (Kotlin floors: 32 MiB, t>=2, p>=1).
    { password: "password", saltHex: hex(salt16), memoryKb: 32768, iterations: 2, parallelism: 1, hashHex: hex(argon("password", salt16, 32768, 2, 1)) },
  ],
  keyDerivation: (() => {
    const pw = "correct horse battery staple";
    const ak = argon(pw, salt16, 65536, 3, 4);
    return {
      password: pw,
      saltHex: hex(salt16),
      authKeyHex: hex(ak),
      verifierHex: hex(hkdf(ak, "auth-verifier-v1")),
      envelopeKeyHex: hex(hkdf(ak, "vault-password-envelope-v1")),
      recoveryUnlockKeyHex: hex(hkdf(ak, "totp-vault-recovery-unlock-v1")),
    };
  })(),
  totp: [
    ...Object.entries(rfc).flatMap(([alg, key]) =>
      times.map((ts) => ({
        secretBase32: base32(key),
        algorithm: alg,
        digits: 8,
        period: 30,
        timestamp: ts,
        code: totp(key, alg.toLowerCase(), 8, 30, ts),
      })),
    ),
    // The Kotlin test's pinned value.
    ...[[6, 1234567890], [8, 1234567890]].map(([d, ts]) => ({
      secretBase32: "JBSWY3DPEHPK3PXP", algorithm: "SHA1", digits: d, period: 30, timestamp: ts,
      code: totp(Buffer.from(base32decode("JBSWY3DPEHPK3PXP")), "sha1", d, 30, ts),
    })),
    // Non-30s period
    { secretBase32: base32(rfc.SHA1), algorithm: "SHA1", digits: 6, period: 60, timestamp: 1234567890,
      code: totp(rfc.SHA1, "sha1", 6, 60, 1234567890) },
  ],
  exportFixtures: {
    entries: exportEntries,
    password: exportPassword,
    encryptedExport: {
      version: 1, format: "pstotp-export",
      salt: exportSalt.toString("base64"),
      ciphertext: exportCt.toString("base64"),
      nonce: exportNonce.toString("base64"),
    },
    googleMigrationUri: migrationUri,
  },
  base32: [
    "", "f", "fo", "foo", "foob", "fooba", "foobar",
  ].map((s) => ({ inputHex: hex(Buffer.from(s)), encoded: base32(Buffer.from(s)) })),
};

function base32(buf) {
  const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0, val = 0, s = "";
  for (const b of buf) {
    val = (val << 8) | b; bits += 8;
    while (bits >= 5) { bits -= 5; s += A[(val >> bits) & 31]; val &= (1 << bits) - 1; }
  }
  if (bits > 0) s += A[(val << (5 - bits)) & 31];
  return s;
}
function base32decode(str) {
  const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0, val = 0; const out = [];
  for (const c of str) {
    val = (val << 5) | A.indexOf(c); bits += 5;
    if (bits >= 8) { bits -= 8; out.push((val >> bits) & 255); val &= (1 << bits) - 1; }
  }
  return out;
}

process.stdout.write(JSON.stringify(out, null, 2) + "\n");
