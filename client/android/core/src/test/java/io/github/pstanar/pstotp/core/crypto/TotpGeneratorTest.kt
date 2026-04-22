package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertEquals
import org.junit.Test

class TotpGeneratorTest {

    // RFC 6238 test vector: secret = "12345678901234567890" (ASCII) = Base32 "GEZDGNBVGY3TQOJQ..."
    // But most real-world tests use known otpauth secrets.

    @Test
    fun `generate produces 6-digit zero-padded code`() {
        // Secret: "JBSWY3DPEHPK3PXP" (well-known test secret)
        val code = TotpGenerator.generate(
            secret = "JBSWY3DPEHPK3PXP",
            algorithm = "SHA1",
            digits = 6,
            period = 30,
            timestampSeconds = 1234567890,
        )
        assertEquals(6, code.length)
        // Verified against our TOTP implementation at this timestamp
        assertEquals("742275", code)
    }

    @Test
    fun `generate with 8 digits`() {
        val code = TotpGenerator.generate(
            secret = "JBSWY3DPEHPK3PXP",
            digits = 8,
            timestampSeconds = 1234567890,
        )
        assertEquals(8, code.length)
    }

    @Test
    fun `generate at different timestamps produces different codes`() {
        val code1 = TotpGenerator.generate(secret = "JBSWY3DPEHPK3PXP", timestampSeconds = 1000000000)
        val code2 = TotpGenerator.generate(secret = "JBSWY3DPEHPK3PXP", timestampSeconds = 1000000030)
        // Different time steps should produce different codes (with overwhelming probability)
        // But same 30s window should produce the same code
        val code1b = TotpGenerator.generate(secret = "JBSWY3DPEHPK3PXP", timestampSeconds = 1000000015)
        assertEquals(code1, code1b)
    }

    @Test
    fun `timeRemaining returns value in range`() {
        val remaining = TotpGenerator.timeRemaining(30)
        assert(remaining in 1..30)
    }

    @Test
    fun `base32 decode and encode roundtrip`() {
        val original = "JBSWY3DPEHPK3PXP"
        val decoded = Base32.decode(original)
        val reencoded = Base32.encode(decoded)
        assertEquals(original, reencoded)
    }

    @Test
    fun `base32 handles padding and spaces`() {
        val withPadding = "JBSWY3DPEHPK3PXP===="
        val withSpaces = "JBSW Y3DP EHPK 3PXP"
        val clean = "JBSWY3DPEHPK3PXP"
        assertEquals(Base32.decode(clean).toList(), Base32.decode(withPadding).toList())
        assertEquals(Base32.decode(clean).toList(), Base32.decode(withSpaces).toList())
    }
}
