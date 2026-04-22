package io.github.pstanar.pstotp.core.api

import org.junit.Assert.assertEquals
import org.junit.Test

class ApiClientErrorMessageTest {

    @Test
    fun `JSON body with detail surfaces the detail verbatim`() {
        val body = """{"detail":"Password reset session is closed"}"""
        val msg = buildErrorMessage(400, "application/json", body)
        assertEquals("Password reset session is closed", msg)
    }

    @Test
    fun `JSON body without detail falls back to status code message`() {
        val msg = buildErrorMessage(500, "application/json", """{"traceId":"abc"}""")
        assertEquals("Server error (HTTP 500)", msg)
    }

    @Test
    fun `HTML body never leaks into the error message`() {
        // The whole point of this function: nginx's 404 HTML must not
        // become the user-facing error message.
        val nginxHtml = """
            <html>
            <head><title>404 Not Found</title></head>
            <body><center><h1>404 Not Found</h1></center></body>
            </html>
        """.trimIndent()
        val msg = buildErrorMessage(404, "text/html", nginxHtml)
        assertEquals("Not found (HTTP 404)", msg)
    }

    @Test
    fun `missing content-type still uses JSON when body looks like JSON`() {
        val msg = buildErrorMessage(400, null, """{"detail":"invalid email"}""")
        assertEquals("invalid email", msg)
    }

    @Test
    fun `empty body falls back to status code`() {
        assertEquals("Bad request (HTTP 400)", buildErrorMessage(400, null, null))
        assertEquals("Bad request (HTTP 400)", buildErrorMessage(400, "application/json", ""))
    }

    @Test
    fun `known status codes have dedicated messages`() {
        assertEquals("Bad request (HTTP 400)", buildErrorMessage(400, null, null))
        assertEquals("Access denied (HTTP 403)", buildErrorMessage(403, null, null))
        assertEquals("Not found (HTTP 404)", buildErrorMessage(404, null, null))
        assertEquals("Server error (HTTP 500)", buildErrorMessage(500, null, null))
        assertEquals("Service unavailable (HTTP 502)", buildErrorMessage(502, null, null))
        assertEquals("Service unavailable (HTTP 503)", buildErrorMessage(503, null, null))
        assertEquals("Server did not respond in time (HTTP 504)", buildErrorMessage(504, null, null))
    }

    @Test
    fun `unknown status code uses generic format`() {
        assertEquals("Server returned HTTP 418", buildErrorMessage(418, null, null))
    }

    @Test
    fun `malformed JSON body falls back to status code message`() {
        // Looks-like-JSON heuristic kicks in but parsing fails. We should not
        // return the malformed body — we should fall back to the status-code
        // message cleanly.
        val msg = buildErrorMessage(500, "application/json", "{this is not json")
        assertEquals("Server error (HTTP 500)", msg)
    }
}
