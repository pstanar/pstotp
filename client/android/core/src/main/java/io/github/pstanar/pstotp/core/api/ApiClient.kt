package io.github.pstanar.pstotp.core.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import io.github.pstanar.pstotp.core.model.api.RefreshResponse
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException

/**
 * HTTP client wrapping OkHttp with Bearer token management.
 *
 * - Injects Authorization header on authenticated requests
 * - On 401: acquires mutex, refreshes tokens, retries original request
 * - On refresh failure: throws SessionExpiredException
 */
class ApiClient(baseUrl: String) {

    /** Base URL without trailing slash (e.g., "https://totp.example.com/api"). */
    var baseUrl: String = baseUrl.trimEnd('/')

    var accessToken: String? = null
    var refreshToken: String? = null

    /** Called after token refresh so callers can persist new tokens to SecureStore. */
    var onTokensRefreshed: ((access: String, refresh: String) -> Unit)? = null

    private val refreshMutex = Mutex()

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    fun setTokens(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }

    fun clearTokens() {
        accessToken = null
        refreshToken = null
    }

    fun hasTokens(): Boolean = accessToken != null && refreshToken != null

    // --- HTTP methods ---

    suspend fun <T> get(endpoint: String, parser: (JSONObject) -> T): T =
        executeWithAuth("GET", endpoint, body = null, parser = parser)

    suspend fun <T> post(endpoint: String, body: JSONObject?, parser: (JSONObject) -> T): T =
        executeWithAuth("POST", endpoint, body, parser)

    suspend fun <T> put(endpoint: String, body: JSONObject?, parser: (JSONObject) -> T): T =
        executeWithAuth("PUT", endpoint, body, parser)

    suspend fun delete(endpoint: String) {
        executeWithAuth<Unit>("DELETE", endpoint, body = null) { }
    }

    /** POST without auth (for login challenge, register, etc.). */
    suspend fun <T> postPublic(endpoint: String, body: JSONObject?, parser: (JSONObject) -> T): T =
        execute("POST", endpoint, body, addAuth = false, parser = parser)

    // --- Internal ---

    private suspend fun <T> executeWithAuth(
        method: String,
        endpoint: String,
        body: JSONObject?,
        parser: (JSONObject) -> T,
    ): T {
        return try {
            execute(method, endpoint, body, addAuth = true, parser = parser)
        } catch (e: ApiException) {
            if (e.statusCode == 401) {
                refreshTokens()
                execute(method, endpoint, body, addAuth = true, parser = parser)
            } else {
                throw e
            }
        }
    }

    private suspend fun refreshTokens() {
        refreshMutex.withLock {
            val rt = refreshToken ?: throw SessionExpiredException()
            val refreshBody = JSONObject().put("refreshToken", rt)
            try {
                val response = execute("POST", "/auth/refresh", refreshBody, addAuth = false) {
                    RefreshResponse.fromJson(it)
                }
                accessToken = response.accessToken
                refreshToken = response.refreshToken
                if (response.accessToken != null && response.refreshToken != null) {
                    onTokensRefreshed?.invoke(response.accessToken, response.refreshToken)
                }
            } catch (e: NetworkException) {
                // Server unreachable — tokens may still be valid. Don't
                // destroy the session; let the caller surface a network
                // error and let the user retry once connectivity is back.
                throw e
            } catch (_: Exception) {
                clearTokens()
                throw SessionExpiredException()
            }
        }
    }

    private suspend fun <T> execute(
        method: String,
        endpoint: String,
        body: JSONObject?,
        addAuth: Boolean,
        parser: (JSONObject) -> T,
    ): T = withContext(Dispatchers.IO) {
        val url = "$baseUrl$endpoint"

        val requestBody = body?.toString()?.toRequestBody(jsonMediaType)

        val request = Request.Builder()
            .url(url)
            .apply {
                when (method) {
                    "GET" -> get()
                    "POST" -> post(requestBody ?: "".toRequestBody(jsonMediaType))
                    "PUT" -> put(requestBody ?: "".toRequestBody(jsonMediaType))
                    "DELETE" -> delete(requestBody)
                }
                if (addAuth) {
                    accessToken?.let { header("Authorization", "Bearer $it") }
                }
            }
            .build()

        val response = try {
            client.newCall(request).execute()
        } catch (e: IOException) {
            throw NetworkException(friendlyNetworkMessage(e), e)
        }
        val responseBody = response.body?.string()

        if (!response.isSuccessful) {
            val message = errorMessage(response, responseBody)
            when (response.code) {
                401 -> throw ApiException(401, message)
                409 -> throw ConflictException(message)
                else -> throw ApiException(response.code, message)
            }
        }

        if (responseBody.isNullOrBlank()) {
            parser(JSONObject())
        } else {
            parser(JSONObject(responseBody))
        }
    }

    private fun errorMessage(response: Response, body: String?): String =
        buildErrorMessage(response.code, response.body?.contentType()?.subtype, body)

    private fun friendlyNetworkMessage(e: IOException): String = when (e) {
        is UnknownHostException -> "Server not found. Check the URL and your connection."
        is SocketTimeoutException -> "Server did not respond in time."
        is ConnectException -> "Could not reach the server."
        is SSLException -> "Secure connection failed (TLS/certificate issue)."
        else -> e.message?.takeIf { it.isNotBlank() } ?: "Network error"
    }
}

/**
 * Build a user-facing error message for a non-success response. Parses the
 * JSON `detail` field when the body is JSON; otherwise produces a status-
 * code-based message. Never returns raw body text — prevents reverse-proxy
 * HTML error pages from leaking into the UI. Top-level so it's unit-testable
 * without spinning up OkHttp.
 */
internal fun buildErrorMessage(statusCode: Int, contentTypeSubtype: String?, body: String?): String {
    val looksLikeJson = contentTypeSubtype?.contains("json", ignoreCase = true) == true ||
        body?.trimStart()?.startsWith("{") == true
    if (looksLikeJson && !body.isNullOrBlank()) {
        runCatching {
            val detail = JSONObject(body).optString("detail").takeIf { it.isNotBlank() }
            if (detail != null) return detail
        }
    }
    return when (statusCode) {
        400 -> "Bad request (HTTP 400)"
        403 -> "Access denied (HTTP 403)"
        404 -> "Not found (HTTP 404)"
        500 -> "Server error (HTTP 500)"
        502, 503 -> "Service unavailable (HTTP $statusCode)"
        504 -> "Server did not respond in time (HTTP 504)"
        else -> "Server returned HTTP $statusCode"
    }
}
