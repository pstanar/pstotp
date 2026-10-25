package io.github.pstanar.pstotp.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Covers the label rules in isolation. [OtpauthUri.parse] itself needs android.net.Uri and so
 * can't run as a pure-JVM test; these cases mirror the web (OtpauthParserColonInAccount) and iOS
 * (OtpauthUriTests) suites.
 */
class OtpauthUriLabelTest {

    private fun resolve(label: String, issuer: String?) = OtpauthUri.resolveLabel(label, issuer)

    @Test
    fun `colon in account name survives when issuer is a query param`() {
        assertEquals("Corp" to "bob: work", resolve("bob: work", "Corp"))
        assertEquals("Corp" to "a:b:c", resolve("a:b:c", "Corp"))
        assertEquals("Corp" to "https://example.com:8080", resolve("https://example.com:8080", "Corp"))
        assertEquals("Corp" to ":leading", resolve(":leading", "Corp"))
        assertEquals("Corp" to "trailing:", resolve("trailing:", "Corp"))
    }

    @Test
    fun `redundant issuer prefix is stripped case-insensitively`() {
        assertEquals("Corp" to "bob", resolve("Corp:bob", "Corp"))
        assertEquals("Corp" to "bob", resolve("corp:bob", "Corp"))
        assertEquals("Corp" to "bob", resolve("Corp: bob", "Corp"))
    }

    @Test
    fun `whole label is kept when prefix is not the issuer`() {
        assertEquals("New" to "Old:alice", resolve("Old:alice", "New"))
    }

    @Test
    fun `first colon splits Issuer_Account when there is no issuer param`() {
        assertEquals("GitHub" to "octocat", resolve("GitHub:octocat", null))
        assertEquals("GitHub" to "octocat:x", resolve("GitHub: octocat:x", null))
        assertEquals("" to "octocat", resolve("octocat", null))
    }

    @Test
    fun `blank issuer param is treated as absent`() {
        assertEquals("GitHub" to "octocat", resolve("GitHub:octocat", ""))
        assertEquals("GitHub" to "octocat", resolve("GitHub:octocat", "  "))
    }
}
