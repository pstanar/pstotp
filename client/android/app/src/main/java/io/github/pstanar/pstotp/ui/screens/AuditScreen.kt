package io.github.pstanar.pstotp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.pstanar.pstotp.core.api.AuditApi
import io.github.pstanar.pstotp.core.model.api.AuditEventDto
import io.github.pstanar.pstotp.ui.AuthViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AuditScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
) {
    var events by remember { mutableStateOf<List<AuditEventDto>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val auditApi = remember { AuditApi(authViewModel.apiClient) }

    LaunchedEffect(Unit) {
        try {
            events = auditApi.fetchEvents(100).events
        } catch (e: Exception) {
            error = e.message ?: "Failed to load audit events"
        } finally {
            loading = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Audit Log") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        if (loading) {
            Column(
                modifier = Modifier.padding(padding).padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator()
            }
        } else if (error != null) {
            Column(modifier = Modifier.padding(padding).padding(16.dp)) {
                Text(error!!, color = MaterialTheme.colorScheme.error)
            }
        } else if (events.isEmpty()) {
            Column(modifier = Modifier.padding(padding).padding(16.dp)) {
                Text("No audit events", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            LazyColumn(
                modifier = Modifier.padding(padding).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(events) { event ->
                    AuditEventCard(event)
                }
            }
        }
    }
}

@Composable
private fun AuditEventCard(event: AuditEventDto) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    formatEventType(event.eventType),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    formatTimestamp(event.createdAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            event.ipAddress?.let { ip ->
                Text(
                    ip,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun formatEventType(type: String): String {
    // Convert "LoginSuccess" → "Login Success", "DeviceApproved" → "Device Approved"
    return type.replace(Regex("([a-z])([A-Z])"), "$1 $2")
}

private fun formatTimestamp(iso: String): String {
    return try {
        val instant = java.time.Instant.parse(iso)
        val local = java.time.LocalDateTime.ofInstant(instant, java.time.ZoneId.systemDefault())
        val formatter = java.time.format.DateTimeFormatter.ofPattern("MMM d, HH:mm")
        local.format(formatter)
    } catch (_: Exception) {
        iso.take(16)
    }
}
