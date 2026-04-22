package io.github.pstanar.pstotp.core.model

import io.github.pstanar.pstotp.core.crypto.Base32
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class ExternalImportsTest {

    // --- Google Authenticator ---------------------------------------------

    @Test
    fun `Google Auth migration payload decodes both entries`() {
        // Hand-built MigrationPayload:
        //   OtpParameters { secret=<raw>, name="alice@example.com", issuer="Example",
        //                   algorithm=SHA1, digits=SIX, type=TOTP }
        //   OtpParameters { secret=<raw>, name="bob", issuer="", algorithm=SHA256,
        //                   digits=EIGHT, type=TOTP }
        val secret1 = Base32.decode("JBSWY3DPEHPK3PXP")
        val secret2 = Base32.decode("NBSWY3DPFQQHO33SNRSCC")

        val otp1 = protoBuilder()
            .bytesField(1, secret1)
            .stringField(2, "alice@example.com")
            .stringField(3, "Example")
            .varintField(4, 1) // SHA1
            .varintField(5, 1) // SIX
            .varintField(6, 2) // TOTP
            .build()

        val otp2 = protoBuilder()
            .bytesField(1, secret2)
            .stringField(2, "bob")
            .stringField(3, "")
            .varintField(4, 2) // SHA256
            .varintField(5, 2) // EIGHT
            .varintField(6, 2) // TOTP
            .build()

        val payload = protoBuilder()
            .bytesField(1, otp1)
            .bytesField(1, otp2)
            .varintField(2, 1) // version
            .build()

        val uri = "otpauth-migration://offline?data=" +
            Base64.getEncoder().encodeToString(payload)

        val entries = ExternalImports.tryParseGoogleAuthMigration(uri)
        assertNotNull(entries)
        assertEquals(2, entries!!.size)

        assertEquals("Example", entries[0].issuer)
        assertEquals("alice@example.com", entries[0].accountName)
        assertEquals(Base32.encode(secret1), entries[0].secret)
        assertEquals("SHA1", entries[0].algorithm)
        assertEquals(6, entries[0].digits)

        assertEquals("bob", entries[1].accountName)
        assertEquals(Base32.encode(secret2), entries[1].secret)
        assertEquals("SHA256", entries[1].algorithm)
        assertEquals(8, entries[1].digits)
    }

    @Test
    fun `Google Auth migration splits Issuer_Account in name field`() {
        // Some exports put "Issuer:account" in name with empty issuer field.
        val secret = Base32.decode("JBSWY3DPEHPK3PXP")
        val otp = protoBuilder()
            .bytesField(1, secret)
            .stringField(2, "GitHub:octocat")
            .stringField(3, "")
            .varintField(4, 1)
            .varintField(5, 1)
            .varintField(6, 2)
            .build()
        val payload = protoBuilder().bytesField(1, otp).build()
        val uri = "otpauth-migration://offline?data=" +
            Base64.getEncoder().encodeToString(payload)

        val entries = ExternalImports.tryParseGoogleAuthMigration(uri)!!
        assertEquals(1, entries.size)
        assertEquals("GitHub", entries[0].issuer)
        assertEquals("octocat", entries[0].accountName)
    }

    @Test
    fun `Google Auth strips redundant issuer prefix from name when it matches`() {
        val otp = protoBuilder()
            .bytesField(1, Base32.decode("JBSWY3DPEHPK3PXP"))
            .stringField(2, "GitHub:octocat")  // redundant prefix
            .stringField(3, "GitHub")           // explicit issuer matches
            .varintField(4, 1).varintField(5, 1).varintField(6, 2)
            .build()
        val uri = buildMigrationUri(otp)

        val entries = ExternalImports.tryParseGoogleAuthMigration(uri)!!
        assertEquals("GitHub", entries[0].issuer)
        assertEquals("octocat", entries[0].accountName)
    }

    @Test
    fun `Google Auth keeps colons in account when prefix does not match issuer`() {
        // Legit colon inside the account — don't misread it as "Issuer:account".
        val otp = protoBuilder()
            .bytesField(1, Base32.decode("JBSWY3DPEHPK3PXP"))
            .stringField(2, "work:alice")
            .stringField(3, "Company")
            .varintField(4, 1).varintField(5, 1).varintField(6, 2)
            .build()
        val uri = buildMigrationUri(otp)

        val entries = ExternalImports.tryParseGoogleAuthMigration(uri)!!
        assertEquals("Company", entries[0].issuer)
        assertEquals("work:alice", entries[0].accountName)
    }

    @Test
    fun `Google Auth migration skips HOTP entries`() {
        val otp = protoBuilder()
            .bytesField(1, Base32.decode("JBSWY3DPEHPK3PXP"))
            .stringField(2, "counter-based")
            .stringField(3, "Bank")
            .varintField(4, 1)
            .varintField(5, 1)
            .varintField(6, 1) // HOTP — should be filtered out
            .build()
        val payload = protoBuilder().bytesField(1, otp).build()
        val uri = "otpauth-migration://offline?data=" +
            Base64.getEncoder().encodeToString(payload)

        val entries = ExternalImports.tryParseGoogleAuthMigration(uri)!!
        assertTrue(entries.isEmpty())
    }

    @Test
    fun `returns null for non-migration URIs`() {
        assertNull(ExternalImports.tryParseGoogleAuthMigration("otpauth://totp/foo?secret=JBSW"))
        assertNull(ExternalImports.tryParseGoogleAuthMigration("https://example.com"))
    }

    // --- Aegis -----------------------------------------------------------

    @Test
    fun `Aegis plain export parses`() {
        val json = JSONObject(
            """
            {
              "version": 1,
              "header": { "slots": null, "params": null },
              "db": {
                "version": 3,
                "entries": [
                  {
                    "type": "totp",
                    "name": "alice@example.com",
                    "issuer": "Example",
                    "info": {
                      "secret": "jbswy3dpehpk3pxp",
                      "algo": "sha1",
                      "digits": 6,
                      "period": 30
                    }
                  },
                  {
                    "type": "hotp",
                    "name": "counter",
                    "issuer": "Bank",
                    "info": { "secret": "NBSWY3DPFQQHO33SNRSCC", "algo": "SHA1", "digits": 6, "counter": 0 }
                  }
                ]
              }
            }
            """.trimIndent(),
        )
        val entries = ExternalImports.tryParseAegis(json)
        assertNotNull(entries)
        assertEquals(1, entries!!.size) // HOTP filtered
        assertEquals("Example", entries[0].issuer)
        assertEquals("alice@example.com", entries[0].accountName)
        assertEquals("JBSWY3DPEHPK3PXP", entries[0].secret) // normalised to upper
        assertEquals("SHA1", entries[0].algorithm)
    }

    @Test
    fun `Aegis rejects shape without header`() {
        val json = JSONObject(
            """{ "db": { "entries": [ { "type": "totp", "info": { "secret": "X" } } ] } }""",
        )
        assertNull(ExternalImports.tryParseAegis(json))
    }

    // --- 2FAS ------------------------------------------------------------

    @Test
    fun `2FAS export parses`() {
        val json = JSONObject(
            """
            {
              "schemaVersion": 4,
              "appVersionCode": 500000,
              "services": [
                {
                  "secret": "JBSWY3DPEHPK3PXP",
                  "name": "Example",
                  "otp": {
                    "account": "alice@example.com",
                    "issuer": "Example",
                    "digits": 6,
                    "period": 30,
                    "algorithm": "SHA1"
                  }
                }
              ]
            }
            """.trimIndent(),
        )
        val entries = ExternalImports.tryParse2Fas(json)
        assertNotNull(entries)
        assertEquals(1, entries!!.size)
        assertEquals("Example", entries[0].issuer)
        assertEquals("alice@example.com", entries[0].accountName)
        assertEquals("JBSWY3DPEHPK3PXP", entries[0].secret)
    }

    @Test
    fun `2FAS falls back to name when otp account is missing`() {
        val json = JSONObject(
            """
            {
              "schemaVersion": 3,
              "services": [ { "secret": "JBSWY3DPEHPK3PXP", "name": "Legacy Service" } ]
            }
            """.trimIndent(),
        )
        val entries = ExternalImports.tryParse2Fas(json)!!
        assertEquals(1, entries.size)
        assertEquals("Legacy Service", entries[0].issuer)
        assertEquals("Legacy Service", entries[0].accountName)
    }

    @Test
    fun `2FAS rejects shape without schemaVersion`() {
        val json = JSONObject("""{ "services": [ { "secret": "X" } ] }""")
        assertNull(ExternalImports.tryParse2Fas(json))
    }

    // --- Tiny protobuf builder used by the test ---------------------------

    private class ProtoBuilder {
        private val out = java.io.ByteArrayOutputStream()

        fun varintField(field: Int, value: Long): ProtoBuilder {
            writeTag(field, 0)
            writeVarint(value)
            return this
        }

        fun varintField(field: Int, value: Int) = varintField(field, value.toLong())

        fun stringField(field: Int, value: String): ProtoBuilder =
            bytesField(field, value.toByteArray(Charsets.UTF_8))

        fun bytesField(field: Int, value: ByteArray): ProtoBuilder {
            writeTag(field, 2)
            writeVarint(value.size.toLong())
            out.write(value)
            return this
        }

        fun build(): ByteArray = out.toByteArray()

        private fun writeTag(field: Int, wire: Int) = writeVarint(((field shl 3) or wire).toLong())

        private fun writeVarint(v: Long) {
            var value = v
            while (value and 0x7fL.inv() != 0L) {
                out.write(((value and 0x7fL) or 0x80L).toInt())
                value = value ushr 7
            }
            out.write(value.toInt())
        }
    }

    private fun protoBuilder() = ProtoBuilder()

    private fun buildMigrationUri(vararg otpParamsBytes: ByteArray): String {
        val payload = ProtoBuilder().apply {
            for (p in otpParamsBytes) bytesField(1, p)
        }.build()
        return "otpauth-migration://offline?data=" +
            Base64.getEncoder().encodeToString(payload)
    }
}
