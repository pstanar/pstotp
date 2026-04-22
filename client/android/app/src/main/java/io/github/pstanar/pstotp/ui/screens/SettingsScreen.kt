package io.github.pstanar.pstotp.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.fragment.app.FragmentActivity
import io.github.pstanar.pstotp.core.model.LockTimeout
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.ConnectionState
import io.github.pstanar.pstotp.ui.SyncState
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.util.BiometricHelper

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    viewModel: VaultViewModel? = null,
    authViewModel: AuthViewModel? = null,
    onConnectServer: () -> Unit = {},
    onDevices: () -> Unit = {},
    onChangePassword: () -> Unit = {},
    onAuditLog: () -> Unit = {},
    onRegenerateCodes: () -> Unit = {},
    onPasskeys: () -> Unit = {},
) {
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
        ) {
            // Appearance
            Text("Appearance", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))
            if (viewModel != null && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                val useSystemColors by viewModel.useSystemColors.collectAsStateWithLifecycle()
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Use system colors", style = MaterialTheme.typography.bodyMedium)
                        Text("Match your wallpaper (Material You)",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(
                        checked = useSystemColors,
                        onCheckedChange = { viewModel.setUseSystemColors(it) },
                    )
                }
            } else {
                Text("Using PsTotp brand colors",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }

            // Security
            if (viewModel != null) {
                Spacer(modifier = Modifier.height(24.dp))
                HorizontalDivider()
                Spacer(modifier = Modifier.height(24.dp))

                Text("Security", style = MaterialTheme.typography.titleMedium)
                Spacer(modifier = Modifier.height(8.dp))

                if (BiometricHelper.isAvailable(context)) {
                    val biometricEnabled by viewModel.isBiometricEnabled.collectAsStateWithLifecycle()
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Biometric unlock", style = MaterialTheme.typography.bodyMedium)
                            Text("Unlock vault with fingerprint or face",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Switch(
                            checked = biometricEnabled,
                            onCheckedChange = { enabled ->
                                if (enabled) {
                                    val cipher = viewModel.getEnableBiometricCipher() ?: return@Switch
                                    if (context is FragmentActivity) {
                                        BiometricHelper.authenticate(
                                            activity = context,
                                            cipher = cipher,
                                            onSuccess = { authenticatedCipher ->
                                                viewModel.completeBiometricEnrollment(authenticatedCipher)
                                            },
                                            onError = { /* User cancelled */ },
                                        )
                                    }
                                } else {
                                    viewModel.disableBiometric()
                                }
                            },
                        )
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                }

                // Auto-lock timeout
                val lockTimeoutMs by viewModel.lockTimeoutMs.collectAsStateWithLifecycle()
                val currentTimeout = LockTimeout.fromMillis(lockTimeoutMs)
                var lockMenuOpen by remember { mutableStateOf(false) }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Auto-lock", style = MaterialTheme.typography.bodyMedium)
                        Text("Lock the vault after this long in the background",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Box {
                        TextButton(onClick = { lockMenuOpen = true }) {
                            Text(currentTimeout.label)
                        }
                        DropdownMenu(
                            expanded = lockMenuOpen,
                            onDismissRequest = { lockMenuOpen = false },
                        ) {
                            LockTimeout.entries.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(option.label) },
                                    onClick = {
                                        viewModel.setLockTimeout(option)
                                        lockMenuOpen = false
                                    },
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(24.dp))

            // Import & Export
            SettingsImportExport(viewModel)

            Spacer(modifier = Modifier.height(24.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(24.dp))

            Text("Server Sync", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))
            if (authViewModel != null) {
                val connState by authViewModel.connectionState.collectAsStateWithLifecycle()
                val lastSync by authViewModel.lastSyncAt.collectAsStateWithLifecycle()
                val serverUrl by authViewModel.serverUrl.collectAsStateWithLifecycle()
                val syncState by authViewModel.syncState.collectAsStateWithLifecycle()
                val isSyncing = syncState is SyncState.Syncing

                if (connState == ConnectionState.Connected) {
                    Text(serverUrl,
                        style = MaterialTheme.typography.bodyMedium)
                    if (lastSync != null) {
                        Text("Last sync: $lastSync",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    (syncState as? SyncState.Error)?.let { err ->
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            err.message,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { authViewModel.syncNow() }, enabled = !isSyncing) {
                            if (isSyncing) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                    color = MaterialTheme.colorScheme.onPrimary,
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                            }
                            Text(if (isSyncing) "Syncing..." else "Sync Now")
                        }
                        OutlinedButton(onClick = onDevices) { Text("Devices") }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = onAuditLog) { Text("Audit Log") }
                        OutlinedButton(onClick = onChangePassword) { Text("Change Password") }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = onPasskeys) { Text("Passkeys") }
                        OutlinedButton(onClick = onRegenerateCodes) { Text("Recovery Codes") }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { authViewModel.disconnect() }) { Text("Disconnect") }
                    }
                } else {
                    Text(
                        "Connect to a PsTotp server for multi-device sync.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Button(onClick = onConnectServer) { Text("Connect to Server") }
                }
            } else {
                Text(
                    "Connect to a PsTotp server for multi-device sync.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
            HorizontalDivider()
            Spacer(modifier = Modifier.height(24.dp))

            // About
            Text("About", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))
            val versionName = remember(context) {
                runCatching {
                    context.packageManager.getPackageInfo(context.packageName, 0).versionName
                }.getOrNull() ?: "unknown"
            }
            Text(
                "PsTotp v$versionName",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                "TOTP authenticator with encrypted multi-device sync",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
