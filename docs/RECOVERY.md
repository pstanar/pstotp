# PsTotp — Recovery

This document is for end users who can't reach their vault: lost
password, lost every device, lost both. PsTotp offers two different
paths, and picking the right one matters because they have different
prerequisites.

Read the first section to pick the right flow. Then follow the
matching walkthrough.

> **Admin-facing recovery-session handling** — how an admin cancels a
> stuck session, what to look for in the audit log, when to intervene —
> lives in [`docs/ADMIN.md`](ADMIN.md). This file is for the end user
> running the flow.

## Which flow do I want?

| Your situation | What you want | Why |
| --- | --- | --- |
| "I forgot my password but I'm still signed in on my phone / browser" | **Password reset** | The shortcut — your trusted device rewraps the vault key with the new password. Instant. |
| "I forgot my password and I'm not signed in anywhere" | **Password reset** via email verification | Server emails a verification code; you supply it + a new password. Requires at least one device with your vault still wrapped for it. |
| "I lost every device I was signed in on but I kept my recovery codes" | **Recovery codes** | The zero-knowledge last-resort path. There's a 24-hour hold period by design. |
| "I lost every device AND my recovery codes" | **Unrecoverable.** | By design. There is no admin escape hatch. See *Worst case* at the bottom. |

Short rule of thumb: **if you still remember your password on any
device, use password reset**. Recovery codes are for the day you wake
up and everything is gone.

## What recovery codes are

When you register, the client generates **eight one-time recovery
codes** and shows them to you exactly once. They look like this:

```
XP3Q7MRKD9
KJ8N2FHTZQ
R4CB6PMWVY
…
```

- 10 characters each, drawn from a 32-character alphabet that
  deliberately excludes I, O, 0, and 1 so there's no ambiguity when
  you read them back off a sticky note.
- Each is one-time use. Redeem it once and it's burnt — even if the
  recovery flow fails mid-way, consider it spent and use a fresh one
  on retry.
- Stored on the server only as **Argon2id hashes**. The server never
  holds the plaintext.
- Regenerable at any time from **Settings → Recovery Management** on
  any signed-in device. New codes invalidate all previous ones in one
  atomic operation — you can't have "half" old and "half" new.

**Where to keep them.** Not on a device that uses PsTotp. Common good
answers: a printout in a drawer; a password-manager that isn't used
for your authenticator (another reason PsTotp isn't a password
manager); a safety deposit box for high-stakes accounts. If you're
keeping the PDF / screenshot on the same phone that runs PsTotp,
you're not actually protected against the scenario these codes are
supposed to cover.

## Password reset

This is the flow you want when you forgot the password but **still
have at least one approved device**.

### From a device that's signed in

1. Go to **Settings → Account → Change Password**.
2. Enter the current password, new password, confirm new password.
3. Done. Other approved devices will accept the new password on their
   next login; access tokens stay valid on this device.

Under the hood: the client decrypts the vault key with the current
password, re-wraps it with a fresh password-derived key, and the
server rotates the password verifier. No admin involvement. No email
round-trip.

### From the sign-in screen (Forgot Password)

1. On the sign-in screen click **Forgot password?**.
2. Enter your email address. The server mails you a 6-digit code
   (valid 15 minutes; rate-limited).
3. Enter the code.
4. Enter a new password.
5. One of your other approved devices rewraps the vault key for the
   new password, transparent to you.

Prerequisites for this flow to finish:

- **Email delivery has to work.** On a production deployment, the
  admin configures SMTP. On a single-user zero-config deployment, the
  verification code is returned inline in the server response rather
  than emailed (the single-user has no one to email — they *are* the
  server).
- **At least one approved device** must still be online with the
  vault wrapped for password login. If you've lost every device, this
  path can't re-derive your vault key — go to recovery codes instead.

## Recovery codes (last-device recovery)

This is the flow for the day everything is gone and all you have is
one of those eight codes you (hopefully) wrote down.

### What will happen

You will go through five steps:

1. **Start.** Enter your email + one recovery code on the recovery
   page.
2. **Pass WebAuthn step-up, if applicable.** If you have any passkeys
   registered, the server requires a passkey assertion at this point
   before it will arm the session. This prevents a stolen recovery
   code alone from authorising vault-material release.
3. **Wait out the hold period.** Default is 24 hours. The server
   refuses to release vault material until that window expires. This
   exists so that if you're not the one running the flow, you
   (or an admin) have time to notice and cancel it.
4. **Come back and complete.** After the hold, set a new password
   and register the device you're on now.
5. **Save your new recovery codes.** The server mints fresh codes as
   part of completion and invalidates the one you just used. Write
   them down again.

### Running it

1. On the sign-in screen, click **Forgot password?** → **I have a
   recovery code**. Or go directly to `https://<your-host>/recovery`.
2. Enter your email address and one recovery code. Click **Start
   recovery**.
3. If the code is valid, you'll see **"Recovery session started. Your
   vault will be available in 24 hours."** and a timestamp for when
   the material can be released. Write that timestamp down.
4. If the server requires WebAuthn step-up (you had passkeys
   registered before losing your devices, and you still have one of
   those passkeys available — e.g. a YubiKey — or access to one of
   the platform authenticators you registered), complete the passkey
   prompt now. The session's hold timer is already running; step-up
   just clears the WebAuthn gate.
5. **Close the browser and wait.** You can re-check status any time
   by coming back to the recovery page with the same email. The
   server will tell you either "still in hold period — available
   after X" or "ready".
6. Once the hold passes, come back. Enter the same email and
   recovery code. You'll be prompted to set a new password and the
   server will register the device you're using now.
7. On completion you'll see **eight new recovery codes.** Write them
   down immediately. The old code you just used is burnt, and if you
   had seven other codes from before, those are burnt too.

### Rate limits

You can start at most **3 recovery attempts per email per hour**.
Past that the endpoint returns HTTP 429 and you wait. This is a
brute-force defence on the recovery-code space.

### "It's been 24 hours and still pending"

Double-check the release timestamp the server gave you at step 3 — if
the admin has configured a longer `Recovery:HoldPeriodHours`, the
wait is longer than 24h. If you're past the release timestamp and the
server still reports pending, contact the admin; the audit log will
show whether your session was cancelled.

### If you started the flow by mistake

The session is not self-cancelling. Either:

- Wait for it to expire on its own.
- Start the flow again with a different (fresh) code — each new
  redemption creates a new session.
- Ask the admin to cancel it from the Admin UI.

The session doesn't compromise anything just by existing — it only
releases material after the hold passes, and only to a caller who
finishes all steps. But if you know someone else started it, cancel
it anyway and investigate.

## WebAuthn step-up

If you had passkeys registered before losing your devices, the server
requires a passkey assertion to arm the recovery session. This
matters when:

- You used a **roaming authenticator** (YubiKey, cross-device passkey
  from a password manager) — you still have it, even though you lost
  the phone / laptop, so step-up works.
- You used **platform passkeys** bound to specific devices that you
  no longer have — step-up can't clear, and recovery is effectively
  unreachable.

The step-up requirement is a safety feature: a recovery code alone
isn't enough to release vault material when you opted into the
stronger authenticator. If you originally registered a roaming
authenticator, keep it with your recovery codes; the two together
are the recovery kit.

## Post-recovery checklist

After a successful recovery, do this in order:

1. **Write down the new recovery codes.** All eight. Don't skip
   because you're relieved.
2. **Revoke the lost devices.** Go to **Settings → Devices** and
   click through to revoke any entries that correspond to devices you
   no longer have. This doesn't affect your vault — it just tells the
   server the listed devices should no longer be allowed to sync even
   if they turn up later.
3. **Decide about passkeys.** Any passkeys on lost devices should be
   revoked from **Settings → Passkeys**. If the passkey was on a
   roaming authenticator you still hold, it's still valid and worth
   keeping.
4. **Check the audit log.** **Settings → Audit** shows
   `recovery_code_redeemed` and `recovery_completed` events for the
   flow you just finished, plus a new-device login. Confirm they
   match what you did.

## Worst case: no codes, no devices

There's no way out. This is not a limitation we can paper over — the
server stores only ciphertext, and the ciphertext can only be
decrypted by someone holding either a password-wrapped envelope, a
device-wrapped envelope, or a recovery-code-wrapped envelope. Without
any of those, the vault's contents are information-theoretically lost.

No admin can help. Any backdoor would be a zero-knowledge violation
and would make PsTotp pointless.

Practical advice: when you **re-create your vault from scratch**, plan
around not hitting this again.

- Register at least two devices and keep both signed in.
- Put your recovery codes somewhere that isn't any of your PsTotp
  devices.
- If your threat model justifies it, register a roaming hardware
  authenticator (YubiKey) — it's the most survivable form factor.

## See also

- [`docs/ADMIN.md`](ADMIN.md) — admin-facing handling of recovery
  sessions (canceling, audit-trail interpretation).
- [`docs/TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — symptom lookup for
  "recovery code rejected", "session expired mid-flow", "after
  recovery, other devices can't decrypt".
- [`SECURITY.md`](../SECURITY.md) — threat model and why the worst
  case exists.
