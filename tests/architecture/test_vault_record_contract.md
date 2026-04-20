# Vault Record Contract Validation

## Checks

### Payload structure
- [ ] `entryPayload` is a single AEAD blob containing `nonce || ciphertext || auth_tag`
- [ ] Plaintext contains all required fields: `issuer`, `accountName`, `secret`, `algorithm`, `digits`, `period`
- [ ] Default values applied correctly: algorithm=SHA1, digits=6, period=30

### Encryption
- [ ] AES-256-GCM with 12-byte nonce, or XChaCha20-Poly1305 with 24-byte nonce
- [ ] Nonce is unique per encryption operation (never reused with the same key)
- [ ] Entry ID is bound as associated data in AEAD
- [ ] Encrypted payload round-trips correctly: encrypt → store → fetch → decrypt → original plaintext

### Versioning
- [ ] `entryVersion` starts at 1 on creation
- [ ] Server increments version on each accepted write
- [ ] Server rejects writes with stale version (optimistic concurrency)
- [ ] Soft-deleted entries retain version and participate in ordering

### Wire format
- [ ] All binary values encoded as base64url in JSON
- [ ] Timestamps in ISO-8601 UTC
- [ ] `deletedAt` is null for active entries, ISO-8601 for soft-deleted

### Validation
- [ ] `issuer` and `accountName` reject empty strings
- [ ] `secret` rejects invalid base32
- [ ] `algorithm` rejects values other than SHA1, SHA256, SHA512
- [ ] `digits` rejects values other than 6 or 8
- [ ] `period` rejects zero or negative values
