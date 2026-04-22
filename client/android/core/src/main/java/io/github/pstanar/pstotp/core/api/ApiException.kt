package io.github.pstanar.pstotp.core.api

/** HTTP error from the server with status code and optional body. */
open class ApiException(
    val statusCode: Int,
    override val message: String,
) : Exception(message)

/** 401 Unauthorized — token expired and refresh failed. */
class SessionExpiredException : ApiException(401, "Session expired — please log in again")

/** 409 Conflict — version mismatch on vault entry upsert. */
class ConflictException(message: String = "Version conflict") : ApiException(409, message)

/**
 * Network-layer failure (host unreachable, timeout, TLS error, etc.) — no
 * HTTP status code because the server was never reached. Message is already
 * user-friendly.
 */
class NetworkException(message: String, cause: Throwable? = null) : Exception(message, cause)
