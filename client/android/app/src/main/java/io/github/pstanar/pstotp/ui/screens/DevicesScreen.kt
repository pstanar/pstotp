package io.github.pstanar.pstotp.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.api.DevicesApi
import io.github.pstanar.pstotp.core.crypto.Ecdh
import io.github.pstanar.pstotp.core.model.api.DeviceInfoDto
import io.github.pstanar.pstotp.core.model.api.Envelope
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.VaultViewModel
import java.util.Base64

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DevicesScreen(
    authViewModel: AuthViewModel,
    vaultViewModel: VaultViewModel,
    onBack: () -> Unit,
) {
    var devices by remember { mutableStateOf<List<DeviceInfoDto>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var actionInProgress by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val devicesApi = authViewModel.devicesApi

    LaunchedEffect(Unit) {
        try {
            devices = sortDevices(devicesApi.fetchDevices().devices)
        } catch (e: Exception) {
            error = e.message ?: "Failed to load devices"
        } finally {
            loading = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Devices") },
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
        } else {
            LazyColumn(
                modifier = Modifier.padding(padding).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(devices) { device ->
                    DeviceCard(
                        device = device,
                        actionInProgress = actionInProgress,
                        onApprove = {
                            scope.launch {
                                actionInProgress = true
                                try {
                                    val vaultKey = vaultViewModel.getVaultKey() ?: return@launch
                                    val pubKeyBytes = Base64.getDecoder().decode(device.devicePublicKey)
                                    val recipientPub = Ecdh.importPublicKey(pubKeyBytes)
                                    val envelope = Ecdh.packDeviceEnvelope(vaultKey, recipientPub)
                                    devicesApi.approveDevice(
                                        device.deviceId,
                                        device.approvalRequestId ?: device.deviceId,
                                        Envelope(envelope.ciphertext, envelope.nonce),
                                    )
                                    // Refresh list
                                    devices = sortDevices(devicesApi.fetchDevices().devices)
                                } catch (e: Exception) {
                                    error = "Approve failed: ${e.message}"
                                } finally {
                                    actionInProgress = false
                                }
                            }
                        },
                        onReject = {
                            scope.launch {
                                actionInProgress = true
                                try {
                                    devicesApi.rejectDevice(device.deviceId)
                                    devices = sortDevices(devicesApi.fetchDevices().devices)
                                } catch (e: Exception) {
                                    error = "Reject failed: ${e.message}"
                                } finally {
                                    actionInProgress = false
                                }
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun DeviceCard(
    device: DeviceInfoDto,
    actionInProgress: Boolean,
    onApprove: () -> Unit,
    onReject: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    if (device.platform == "android" || device.platform == "ios")
                        Icons.Default.PhoneAndroid else Icons.Default.Computer,
                    contentDescription = null,
                    modifier = Modifier.size(24.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(device.deviceName, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        device.status.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.bodySmall,
                        color = when (device.status) {
                            "approved" -> MaterialTheme.colorScheme.primary
                            "pending" -> MaterialTheme.colorScheme.tertiary
                            else -> MaterialTheme.colorScheme.error
                        },
                    )
                }
            }

            if (device.status == "pending") {
                Spacer(modifier = Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = onApprove, enabled = !actionInProgress) { Text("Approve") }
                    OutlinedButton(onClick = onReject, enabled = !actionInProgress) { Text("Reject") }
                }
            }
        }
    }
}

/**
 * Android shows all device states in one list (unlike web which buckets them).
 * Put pending devices first so their Approve/Reject buttons are immediately
 * visible, then approved (newest approval first), then revoked (newest
 * revocation first). ISO-8601 strings sort lexicographically in time order.
 */
private fun sortDevices(devices: List<DeviceInfoDto>): List<DeviceInfoDto> =
    devices.sortedWith(
        compareBy<DeviceInfoDto> {
            when (it.status) {
                "pending" -> 0
                "approved" -> 1
                else -> 2
            }
        }.thenByDescending { device ->
            when (device.status) {
                "revoked" -> device.revokedAt ?: device.approvedAt
                else -> device.approvedAt
            }
        }
    )
