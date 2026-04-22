package io.github.pstanar.pstotp.core.api

import io.github.pstanar.pstotp.core.model.api.AuditEventListResponse

/** Audit event API endpoints (authenticated). */
class AuditApi(private val client: ApiClient) {

    suspend fun fetchEvents(limit: Int = 50): AuditEventListResponse =
        client.get("/security/audit-events?limit=$limit") { AuditEventListResponse.fromJson(it) }
}
