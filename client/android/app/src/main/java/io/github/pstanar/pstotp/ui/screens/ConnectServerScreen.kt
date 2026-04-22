package io.github.pstanar.pstotp.ui.screens

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.model.api.LoginEnvelopes
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.ConnectionState
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.util.CredentialManagerHelper
import io.github.pstanar.pstotp.util.PasskeyCancelledException

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConnectServerScreen(
    authViewModel: AuthViewModel,
    vaultViewModel: VaultViewModel,
    onConnected: () -> Unit,
    onRegister: (serverUrl: String) -> Unit,
    onRecover: (serverUrl: String) -> Unit,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var serverUrl by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    val connectionState by authViewModel.connectionState.collectAsStateWithLifecycle()
    val error by authViewModel.error.collectAsStateWithLifecycle()
    val connecting = connectionState == ConnectionState.Connecting

    // Passkey "need password" state
    var needPasswordEnvelopes by remember { mutableStateOf<LoginEnvelopes?>(null) }
    var needPasswordUserId by remember { mutableStateOf<String?>(null) }
    var needPasswordDeviceId by remember { mutableStateOf<String?>(null) }
    val needPassword = needPasswordEnvelopes != null

    // Passkey ceremony in progress
    var passkeyLoading by remember { mutableStateOf(false) }
    var passkeyError by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Connect to Server") },
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
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (needPassword) {
                // Passkey verified but need password for vault decryption
                Text(
                    "Passkey verified. Enter your password to unlock the vault.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(modifier = Modifier.height(4.dp))

                PasswordField(
                    value = password,
                    onValueChange = { password = it; authViewModel.clearError(); passkeyError = null },
                    label = "Password",
                    enabled = !connecting,
                    modifier = Modifier.fillMaxWidth(),
                )

                if (error != null) {
                    Text(
                        error!!,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Button(
                    onClick = {
                        authViewModel.passkeyUnlockWithPassword(
                            serverUrl = serverUrl.trim(),
                            email = email.trim(),
                            password = password,
                            envelopes = needPasswordEnvelopes!!,
                            userId = needPasswordUserId!!,
                            deviceId = needPasswordDeviceId!!,
                            unlockVault = { vaultKey -> vaultViewModel.unlockWithKey(vaultKey) },
                            onSuccess = {
                                authViewModel.syncNow()
                                onConnected()
                            },
                        )
                    },
                    enabled = !connecting && password.isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (connecting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Unlocking...")
                    } else {
                        Text("Unlock")
                    }
                }

                TextButton(
                    onClick = {
                        needPasswordEnvelopes = null
                        needPasswordUserId = null
                        needPasswordDeviceId = null
                        password = ""
                        authViewModel.clearError()
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Back to login")
                }
            } else {
                // Normal login form
                Text(
                    "Connect to a PsTotp server for multi-device sync.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(modifier = Modifier.height(4.dp))

                OutlinedTextField(
                    value = serverUrl,
                    onValueChange = { serverUrl = it; authViewModel.clearError(); passkeyError = null },
                    label = { Text("Server URL") },
                    placeholder = { Text("https://totp.example.com/api") },
                    singleLine = true,
                    enabled = !connecting && !passkeyLoading,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Uri,
                        imeAction = ImeAction.Next,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )

                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it; authViewModel.clearError(); passkeyError = null },
                    label = { Text("Email") },
                    singleLine = true,
                    enabled = !connecting && !passkeyLoading,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Next,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )

                PasswordField(
                    value = password,
                    onValueChange = { password = it; authViewModel.clearError(); passkeyError = null },
                    label = "Password",
                    enabled = !connecting && !passkeyLoading,
                    modifier = Modifier.fillMaxWidth(),
                )

                val displayError = error ?: passkeyError
                if (displayError != null) {
                    Text(
                        displayError,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Button(
                    onClick = {
                        val vaultKey = vaultViewModel.getVaultKey()
                        if (vaultKey == null) {
                            authViewModel.setError("Vault is locked. Unlock it first.")
                            return@Button
                        }
                        authViewModel.connect(
                            serverUrl = serverUrl.trim(),
                            email = email.trim(),
                            password = password,
                            vaultKey = vaultKey,
                            // When joining an existing account the server's
                            // key differs from the local setup key; adopt it
                            // so decryption of synced entries succeeds. Gating
                            // onSuccess on this lets AuthViewModel refuse to
                            // flip to Connected if the key doesn't decrypt.
                            unlockVault = { serverVaultKey -> vaultViewModel.unlockWithKey(serverVaultKey) },
                            onSuccess = {
                                authViewModel.syncNow()
                                onConnected()
                            },
                        )
                    },
                    enabled = !connecting && !passkeyLoading && serverUrl.isNotBlank() && email.isNotBlank() && password.isNotEmpty(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (connecting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Connecting...")
                    } else {
                        Text("Connect")
                    }
                }

                OutlinedButton(
                    onClick = {
                        passkeyLoading = true
                        authViewModel.clearError()
                        scope.launch {
                            try {
                                val webAuthnApi = authViewModel.webAuthnApi
                                authViewModel.apiClient.baseUrl = serverUrl.trim().trimEnd('/')
                                val begin = webAuthnApi.beginAssertion(email = email.trim())
                                val helper = CredentialManagerHelper(context as Activity)
                                val assertionJson = helper.getPasskey(begin.publicKeyOptionsJson)
                                passkeyLoading = false
                                authViewModel.passkeyLogin(
                                    serverUrl = serverUrl.trim(),
                                    email = email.trim(),
                                    ceremonyId = begin.ceremonyId,
                                    assertionResponseJson = assertionJson,
                                    unlockVault = { vaultKey -> vaultViewModel.unlockWithKey(vaultKey) },
                                    onSuccess = {
                                        authViewModel.syncNow()
                                        onConnected()
                                    },
                                    onNeedPassword = { envelopes, userId, deviceId ->
                                        needPasswordEnvelopes = envelopes
                                        needPasswordUserId = userId
                                        needPasswordDeviceId = deviceId
                                        password = ""
                                    },
                                )
                            } catch (e: PasskeyCancelledException) {
                                passkeyLoading = false
                            } catch (e: Exception) {
                                passkeyLoading = false
                                passkeyError = e.message ?: "Passkey login failed"
                            }
                        }
                    },
                    enabled = !connecting && !passkeyLoading && serverUrl.isNotBlank() && email.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (passkeyLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    Text("Sign in with passkey")
                }

                TextButton(
                    onClick = { if (serverUrl.isNotBlank()) onRegister(serverUrl.trim()) },
                    enabled = !connecting && !passkeyLoading && serverUrl.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Don't have an account? Create one")
                }

                TextButton(
                    onClick = { if (serverUrl.isNotBlank()) onRecover(serverUrl.trim()) },
                    enabled = !connecting && !passkeyLoading && serverUrl.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Lost access? Recover account")
                }

                if (connectionState == ConnectionState.PendingApproval) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "This device is pending approval. Open PsTotp on an already-approved device and approve this device in Settings > Devices.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
