# Threat Model Coverage Validation

## T1: Stolen password

- [ ] Password-only login from a new device creates a `pending` device, not `approved`
- [ ] Pending device cannot fetch vault entries or device envelope
- [ ] Approval requires step-up auth on an existing approved device
- [ ] Failed login attempts are rate-limited (5 per 15 min per account)
- [ ] Failed login attempts are recorded as audit events
- [ ] Successful login from new device triggers notification to existing devices

## T2: Stolen unlocked device

- [ ] Web auto-lock clears decrypted vault from memory after inactivity timeout
- [ ] Locked state prevents TOTP code display and copy
- [ ] Device approval requires step-up re-authentication
- [ ] Password change requires step-up re-authentication
- [ ] Recovery operations require step-up re-authentication

## T3: Stolen encrypted server database

- [ ] No plaintext TOTP secrets exist in any database table
- [ ] No plaintext VaultKey exists in any database table
- [ ] No plaintext password exists in any database table
- [ ] Password verifier and password envelope key use different HKDF context strings
- [ ] Cracking the password verifier does not yield the envelope key
- [ ] Recovery codes stored as slow hashes only
- [ ] Issuer and account names are inside encrypted vault entry payloads, not in separate columns

## T4: Malicious email/account recovery attempt

- [ ] Email alone is never sufficient to release recovery material
- [ ] Recovery requires: valid recovery code + password + optional WebAuthn
- [ ] Recovery hold period (24–48h) enforced before material release
- [ ] Recovery session can be cancelled from any trusted device during hold
- [ ] All recovery attempts generate audit events and notifications
- [ ] Recovery code redemption is rate-limited (3 per hour)

## T5: Replay or tampering during sync

- [ ] All API endpoints require HTTPS
- [ ] Login challenge nonce is single-use
- [ ] Tampered AEAD ciphertext fails client-side authentication tag verification
- [ ] Stale `entryVersion` writes are rejected by the server
- [ ] Refresh token rotation revokes previous token
- [ ] JWT access tokens have short expiry (15 min)
