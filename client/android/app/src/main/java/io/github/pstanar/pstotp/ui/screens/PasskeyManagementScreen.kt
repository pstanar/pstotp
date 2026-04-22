package io.github.pstanar.pstotp.ui.screens

import android.app.Activity
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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Key
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.model.api.WebAuthnCredentialInfo
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.util.CredentialManagerHelper
import io.github.pstanar.pstotp.util.PasskeyCancelledException

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PasskeyManagementScreen(
    authViewModel: AuthViewModel,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val activity = context as Activity
    val scope = rememberCoroutineScope()
    val webAuthnApi = authViewModel.webAuthnApi

    var credentials by remember { mutableStateOf<List<WebAuthnCredentialInfo>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var registering by remember { mutableStateOf(false) }

    // Rename dialog state
    var renameTarget by remember { mutableStateOf<WebAuthnCredentialInfo?>(null) }
    var renameName by remember { mutableStateOf("") }

    // Revoke confirmation state
    var revokeTarget by remember { mutableStateOf<WebAuthnCredentialInfo?>(null) }

    // Name-your-passkey dialog (after Credential Manager succeeds)
    var pendingCeremonyId by remember { mutableStateOf<String?>(null) }
    var pendingAttestationJson by remember { mutableStateOf<String?>(null) }
    var friendlyName by remember { mutableStateOf("") }

    fun refresh() {
        scope.launch {
            try {
                credentials = webAuthnApi.listCredentials()
                error = null
            } catch (e: Exception) {
                error = e.message ?: "Failed to load passkeys"
            } finally {
                loading = false
            }
        }
    }

    LaunchedEffect(Unit) { refresh() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Passkeys") },
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
                .padding(16.dp),
        ) {
            Text(
                "Passkeys let you sign in without a password using your fingerprint or screen lock.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(12.dp))

            Button(
                onClick = {
                    registering = true
                    error = null
                    scope.launch {
                        try {
                            val begin = webAuthnApi.beginRegistration()
                            val helper = CredentialManagerHelper(activity)
                            val attestationJson = helper.createPasskey(begin.publicKeyOptionsJson)
                            // Show name dialog
                            pendingCeremonyId = begin.ceremonyId
                            pendingAttestationJson = attestationJson
                            friendlyName = "Android passkey"
                        } catch (e: PasskeyCancelledException) {
                            // User cancelled — silent
                        } catch (e: Exception) {
                            error = e.message ?: "Passkey registration failed"
                        } finally {
                            registering = false
                        }
                    }
                },
                enabled = !registering && !loading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (registering) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Add Passkey")
                }
            }

            if (error != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }

            Spacer(modifier = Modifier.height(16.dp))

            if (loading) {
                CircularProgressIndicator()
            } else if (credentials.isEmpty()) {
                Text(
                    "No passkeys registered yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(credentials, key = { it.id }) { credential ->
                        PasskeyCard(
                            credential = credential,
                            onRename = {
                                renameTarget = credential
                                renameName = credential.friendlyName ?: ""
                            },
                            onRevoke = { revokeTarget = credential },
                        )
                    }
                }
            }
        }
    }

    // Name-your-passkey dialog (post-registration)
    if (pendingCeremonyId != null) {
        AlertDialog(
            onDismissRequest = { pendingCeremonyId = null; pendingAttestationJson = null },
            title = { Text("Name Your Passkey") },
            text = {
                OutlinedTextField(
                    value = friendlyName,
                    onValueChange = { friendlyName = it },
                    label = { Text("Passkey name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    enabled = friendlyName.isNotBlank(),
                    onClick = {
                        val cId = pendingCeremonyId!!
                        val aJson = pendingAttestationJson!!
                        val name = friendlyName.trim()
                        pendingCeremonyId = null
                        pendingAttestationJson = null
                        scope.launch {
                            try {
                                webAuthnApi.completeRegistration(cId, name, aJson)
                                refresh()
                            } catch (e: Exception) {
                                error = e.message ?: "Failed to save passkey"
                            }
                        }
                    },
                ) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { pendingCeremonyId = null; pendingAttestationJson = null }) {
                    Text("Cancel")
                }
            },
        )
    }

    // Rename dialog
    if (renameTarget != null) {
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("Rename Passkey") },
            text = {
                OutlinedTextField(
                    value = renameName,
                    onValueChange = { renameName = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    enabled = renameName.isNotBlank(),
                    onClick = {
                        val id = renameTarget!!.id
                        val name = renameName.trim()
                        renameTarget = null
                        scope.launch {
                            try {
                                webAuthnApi.renameCredential(id, name)
                                refresh()
                            } catch (e: Exception) {
                                error = e.message ?: "Rename failed"
                            }
                        }
                    },
                ) { Text("Rename") }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) { Text("Cancel") }
            },
        )
    }

    // Revoke confirmation dialog
    if (revokeTarget != null) {
        AlertDialog(
            onDismissRequest = { revokeTarget = null },
            title = { Text("Revoke Passkey") },
            text = {
                Text("Revoke \"${revokeTarget!!.friendlyName ?: "Unnamed passkey"}\"? You won't be able to sign in with it anymore.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val id = revokeTarget!!.id
                        revokeTarget = null
                        scope.launch {
                            try {
                                webAuthnApi.revokeCredential(id)
                                refresh()
                            } catch (e: Exception) {
                                error = e.message ?: "Revoke failed"
                            }
                        }
                    },
                ) { Text("Revoke", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = {
                TextButton(onClick = { revokeTarget = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun PasskeyCard(
    credential: WebAuthnCredentialInfo,
    onRename: () -> Unit,
    onRevoke: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Key,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 12.dp),
            ) {
                Text(
                    credential.friendlyName ?: "Unnamed passkey",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    buildString {
                        append("Created ${credential.createdAt.take(10)}")
                        credential.lastUsedAt?.let { append(" \u00B7 Used ${it.take(10)}") }
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            IconButton(onClick = onRename) {
                Icon(Icons.Default.Edit, contentDescription = "Rename", modifier = Modifier.size(20.dp))
            }
            IconButton(onClick = onRevoke) {
                Icon(
                    Icons.Default.Delete, contentDescription = "Revoke",
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}
