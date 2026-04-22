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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.model.api.Envelope
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.util.CredentialManagerHelper
import io.github.pstanar.pstotp.util.PasskeyCancelledException

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoveryScreen(
    authViewModel: AuthViewModel,
    serverUrl: String,
    onRecovered: (vaultKey: ByteArray) -> Unit,
    onBack: () -> Unit,
) {
    // Remember the server-returned vault key so we can hand it off to
    // VaultViewModel.unlockWithKey via onRecovered once the user clicks
    // through the new-recovery-codes screen.
    var recoveredVaultKey by remember { mutableStateOf<ByteArray?>(null) }
    val context = LocalContext.current
    // 0=input, 1=processing, 2=pending (hold), 3=completing, 4=done (show codes), 5=webauthn step-up
    var step by remember { mutableIntStateOf(0) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var recoveryCode by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var sessionId by remember { mutableStateOf<String?>(null) }
    var releaseTime by remember { mutableStateOf<String?>(null) }
    var recoveryEnvelope by remember { mutableStateOf<Envelope?>(null) }
    var replacementDeviceId by remember { mutableStateOf<String?>(null) }
    var newRecoveryCodes by remember { mutableStateOf<List<String>>(emptyList()) }
    var hadPendingPhase by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val vmError by authViewModel.error.collectAsStateWithLifecycle()

    // Observe ViewModel errors (e.g. from completeRecovery) and surface them
    LaunchedEffect(vmError) {
        if (vmError != null && step == 3) {
            error = vmError
            // If we came from the pending path, go back to pending (Check Again still works).
            // If immediate-ready, go to input (session may still be usable via Check Again from pending).
            step = if (hadPendingPhase) 2 else 0
            authViewModel.clearError()
        }
    }

    /** Handle recovery material status — dispatches to the right step. */
    suspend fun handleMaterialStatus(status: String, matReleaseTime: String?, matEnvelope: Envelope?, matDeviceId: String?) {
        when (status) {
            "ready" -> {
                recoveryEnvelope = matEnvelope
                replacementDeviceId = matDeviceId
                step = 3
                completeRecoveryFlow(
                    authViewModel, serverUrl, email.trim(), password,
                    sessionId!!, recoveryEnvelope!!, replacementDeviceId!!,
                    onCodes = { codes, vaultKey ->
                        newRecoveryCodes = codes
                        recoveredVaultKey = vaultKey
                        step = 4
                    },
                    onError = { msg -> error = msg; step = if (hadPendingPhase) 2 else 0 },
                )
            }
            "pending" -> {
                releaseTime = matReleaseTime
                hadPendingPhase = true
                step = 2
            }
            "webauthn_required" -> {
                step = 5 // WebAuthn step-up
            }
            else -> {
                error = "Unexpected status: $status"
                step = 0
            }
        }
    }

    /** Perform WebAuthn step-up and retry material fetch. */
    fun performWebAuthnStepUp() {
        error = null
        scope.launch {
            try {
                val webAuthnApi = authViewModel.webAuthnApi
                authViewModel.apiClient.baseUrl = serverUrl.trimEnd('/')
                val begin = webAuthnApi.beginAssertion(recoverySessionId = sessionId!!)
                val helper = CredentialManagerHelper(context as Activity)
                val assertionJson = helper.getPasskey(begin.publicKeyOptionsJson)
                authViewModel.authService.recoveryWebAuthnStepUp(serverUrl, begin.ceremonyId, assertionJson)

                // Retry material fetch
                step = 1
                val material = authViewModel.authService.getRecoveryMaterial(serverUrl, sessionId!!)
                handleMaterialStatus(material.status, material.releaseEarliestAt, material.recoveryEnvelope, material.replacementDeviceId)
            } catch (e: PasskeyCancelledException) {
                step = 0
                error = "WebAuthn verification cancelled. You can try again."
            } catch (e: Exception) {
                step = 0
                error = e.message ?: "WebAuthn verification failed"
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Account Recovery") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            when (step) {
                0 -> {
                    // Input step
                    Text(
                        "Enter your email, password, and one of your recovery codes to regain access.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    Spacer(modifier = Modifier.height(4.dp))

                    OutlinedTextField(
                        value = email, onValueChange = { email = it; error = null },
                        label = { Text("Email") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
                        modifier = Modifier.fillMaxWidth(),
                    )
                    PasswordField(
                        value = password,
                        onValueChange = { password = it; error = null },
                        label = "Password",
                        imeAction = ImeAction.Next,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = recoveryCode, onValueChange = { recoveryCode = it; error = null },
                        label = { Text("Recovery Code") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        modifier = Modifier.fillMaxWidth(),
                    )

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Button(
                        onClick = {
                            step = 1; error = null
                            scope.launch {
                                try {
                                    // Redeem recovery code
                                    val result = authViewModel.authService.redeemRecoveryCode(
                                        serverUrl, email.trim(), password, recoveryCode.trim(),
                                    )
                                    sessionId = result.recoverySessionId

                                    // If WebAuthn is required, handle before checking material
                                    if (result.requiresWebAuthn) {
                                        step = 5
                                        return@launch
                                    }

                                    // Try to get material immediately
                                    val material = authViewModel.authService.getRecoveryMaterial(
                                        serverUrl, result.recoverySessionId,
                                    )

                                    handleMaterialStatus(material.status, material.releaseEarliestAt, material.recoveryEnvelope, material.replacementDeviceId)
                                } catch (e: Exception) {
                                    error = e.message ?: "Recovery failed"
                                    step = 0
                                }
                            }
                        },
                        enabled = email.isNotBlank() && password.isNotEmpty() && recoveryCode.isNotBlank(),
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Recover Account") }
                }

                1 -> {
                    // Processing
                    Text("Verifying credentials and recovery code...", style = MaterialTheme.typography.bodyMedium)
                    Spacer(modifier = Modifier.height(16.dp))
                    CircularProgressIndicator()
                }

                2 -> {
                    // Pending — hold period
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Recovery Hold Period", style = MaterialTheme.typography.titleMedium)
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "For security, recovery material will be available after:",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                releaseTime ?: "Unknown",
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                            )
                        }
                    }

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Button(
                        onClick = {
                            error = null
                            scope.launch {
                                try {
                                    val material = authViewModel.authService.getRecoveryMaterial(
                                        serverUrl, sessionId!!,
                                    )
                                    handleMaterialStatus(material.status, material.releaseEarliestAt, material.recoveryEnvelope, material.replacementDeviceId)
                                } catch (e: Exception) {
                                    error = e.message ?: "Check failed"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Check Again") }

                    OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                        Text("Cancel")
                    }
                }

                3 -> {
                    // Completing
                    Text("Recovering account...", style = MaterialTheme.typography.bodyMedium)
                    Spacer(modifier = Modifier.height(16.dp))
                    CircularProgressIndicator()
                }

                4 -> {
                    // Done — show new recovery codes
                    Text("Account Recovered", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Save your new recovery codes. The old codes are no longer valid.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(12.dp))

                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        newRecoveryCodes.forEachIndexed { index, code ->
                            Text(
                                "${index + 1}. $code",
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "These codes will not be shown again.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )

                    Spacer(modifier = Modifier.height(24.dp))
                    Button(
                        onClick = { recoveredVaultKey?.let { onRecovered(it) } },
                        enabled = recoveredVaultKey != null,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("I've Saved My Codes")
                    }
                }

                5 -> {
                    // WebAuthn step-up required
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text("Passkey Verification Required", style = MaterialTheme.typography.titleMedium)
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                "Your account requires passkey verification to complete recovery. Tap below to verify with your passkey.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Button(
                        onClick = { performWebAuthnStepUp() },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Verify with Passkey") }

                    OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                        Text("Cancel")
                    }
                }
            }
        }
    }
}

private fun completeRecoveryFlow(
    authViewModel: AuthViewModel,
    serverUrl: String,
    email: String,
    password: String,
    sessionId: String,
    envelope: Envelope,
    replacementDeviceId: String,
    onCodes: (List<String>, ByteArray) -> Unit,
    @Suppress("UNUSED_PARAMETER") onError: (String) -> Unit,
) {
    // Use ViewModel method so observable auth state (connectionState, serverUrl, email) is updated
    authViewModel.completeRecovery(
        serverUrl, email, password, sessionId, envelope, replacementDeviceId,
        onApproved = { vaultKey ->
            onCodes(authViewModel.recoveryCodes.value, vaultKey)
        },
    )
    // Error is surfaced via authViewModel.error which the screen observes
}
