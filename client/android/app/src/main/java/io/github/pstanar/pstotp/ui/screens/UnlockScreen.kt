package io.github.pstanar.pstotp.ui.screens

import android.app.Activity
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Key
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.Alignment
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.R
import androidx.fragment.app.FragmentActivity
import io.github.pstanar.pstotp.core.model.api.LoginEnvelopes
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.ConnectionState
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.util.BiometricHelper
import io.github.pstanar.pstotp.util.CredentialManagerHelper
import io.github.pstanar.pstotp.util.PasskeyCancelledException

@Composable
fun UnlockScreen(
    viewModel: VaultViewModel,
    authViewModel: AuthViewModel? = null,
    onUnlocked: () -> Unit,
) {
    var password by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var passkeyLoading by remember { mutableStateOf(false) }
    val error by viewModel.error.collectAsStateWithLifecycle()
    val authError by (authViewModel?.error?.collectAsStateWithLifecycle() ?: remember { mutableStateOf(null) })
    val biometricEnabled by viewModel.isBiometricEnabled.collectAsStateWithLifecycle()
    val focusRequester = remember { FocusRequester() }
    val scope = rememberCoroutineScope()

    // When a passkey assertion succeeds but the server can only return a
    // password envelope (no device envelope yet for this device), we stash
    // the envelopes so the user can finish unlocking by entering their
    // password below. The Unlock button then routes to
    // passkeyUnlockWithPassword instead of the local unlock path.
    var needPasswordEnvelopes by remember { mutableStateOf<LoginEnvelopes?>(null) }
    var needPasswordUserId by remember { mutableStateOf<String?>(null) }
    var needPasswordDeviceId by remember { mutableStateOf<String?>(null) }
    val passkeyNeedsPassword = needPasswordEnvelopes != null

    // Show the passkey option only when the app has previously connected to a
    // server and we have the stored URL + email to drive a WebAuthn assertion.
    val connectionState by (authViewModel?.connectionState?.collectAsStateWithLifecycle()
        ?: remember { mutableStateOf(ConnectionState.Disconnected) })
    val serverUrl by (authViewModel?.serverUrl?.collectAsStateWithLifecycle()
        ?: remember { mutableStateOf("") })
    val email by (authViewModel?.email?.collectAsStateWithLifecycle()
        ?: remember { mutableStateOf("") })
    val showPasskey = authViewModel != null
        && connectionState == ConnectionState.Connected
        && serverUrl.isNotBlank() && email.isNotBlank()

    // Refocus password field on error
    LaunchedEffect(error) {
        if (error != null) {
            focusRequester.requestFocus()
        }
    }
    val context = LocalContext.current
    val biometricAvailable = remember { BiometricHelper.isAvailable(context) }
    val showBiometric = biometricAvailable && biometricEnabled

    // Live clock — updates each second
    var now by remember { mutableStateOf(java.time.LocalTime.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = java.time.LocalTime.now()
            kotlinx.coroutines.delay(1000L - (System.currentTimeMillis() % 1000))
        }
    }
    val hourAngle = (now.hour % 12) * 30f + now.minute * 0.5f
    val minuteAngle = now.minute * 6f + now.second * 0.1f
    val secondAngle = now.second * 6f - 135f

    // Auto-prompt biometric on first display if enrolled
    LaunchedEffect(showBiometric) {
        if (showBiometric && context is FragmentActivity) {
            val cipher = viewModel.getBiometricDecryptCipher() ?: return@LaunchedEffect
            BiometricHelper.authenticate(
                activity = context,
                cipher = cipher,
                onSuccess = { authenticatedCipher ->
                    viewModel.unlockWithBiometric(authenticatedCipher, onSuccess = onUnlocked)
                },
                onError = { /* User chose password instead */ },
            )
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(modifier = Modifier.size(96.dp)) {
            Image(
                painter = painterResource(R.drawable.ic_login_face),
                contentDescription = "PsTotp",
                modifier = Modifier.size(96.dp),
            )
            Image(
                painter = painterResource(R.drawable.ic_login_hand_hour),
                contentDescription = null,
                modifier = Modifier.size(96.dp).rotate(hourAngle),
            )
            Image(
                painter = painterResource(R.drawable.ic_login_hand_minute),
                contentDescription = null,
                modifier = Modifier.size(96.dp).rotate(minuteAngle),
            )
            Image(
                painter = painterResource(R.drawable.ic_login_key),
                contentDescription = null,
                modifier = Modifier.size(96.dp).rotate(secondAngle),
            )
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "PsTotp",
            style = MaterialTheme.typography.headlineLarge,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = if (passkeyNeedsPassword)
                "Passkey verified. Enter your password to finish unlocking."
            else
                "Enter your password to unlock",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(32.dp))

        val submitPassword: () -> Unit = submit@{
            if (password.isEmpty() || loading) return@submit
            loading = true
            if (passkeyNeedsPassword && authViewModel != null) {
                authViewModel.passkeyUnlockWithPassword(
                    serverUrl = serverUrl,
                    email = email,
                    password = password,
                    envelopes = needPasswordEnvelopes!!,
                    userId = needPasswordUserId!!,
                    deviceId = needPasswordDeviceId!!,
                    unlockVault = { vaultKey -> viewModel.unlockWithKey(vaultKey) },
                    onSuccess = {
                        needPasswordEnvelopes = null
                        needPasswordUserId = null
                        needPasswordDeviceId = null
                        authViewModel.syncNow()
                        onUnlocked()
                    },
                    onComplete = { loading = false },
                )
            } else {
                viewModel.unlock(
                    password = password,
                    onSuccess = onUnlocked,
                    onComplete = { loading = false },
                )
            }
        }

        PasswordField(
            value = password,
            onValueChange = {
                password = it
                viewModel.clearError()
                authViewModel?.clearError()
            },
            label = "Password",
            enabled = !loading,
            imeAction = ImeAction.Done,
            keyboardActions = KeyboardActions(onDone = { submitPassword() }),
            modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
        )

        val displayError = error ?: authError
        if (displayError != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = displayError,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = submitPassword,
            enabled = !loading && password.isNotEmpty(),
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (loading) {
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

        if (showBiometric) {
            Spacer(modifier = Modifier.height(16.dp))
            OutlinedButton(
                onClick = {
                    if (context is FragmentActivity) {
                        val cipher = viewModel.getBiometricDecryptCipher()
                        if (cipher != null) {
                            BiometricHelper.authenticate(
                                activity = context,
                                cipher = cipher,
                                onSuccess = { authenticatedCipher ->
                                    viewModel.unlockWithBiometric(authenticatedCipher, onSuccess = onUnlocked)
                                },
                                onError = { msg -> viewModel.clearError() },
                            )
                        }
                    }
                },
                enabled = !loading && !passkeyLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    Icons.Default.Fingerprint,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Unlock with biometrics")
            }
        }

        if (showPasskey) {
            Spacer(modifier = Modifier.height(8.dp))
            OutlinedButton(
                onClick = {
                    if (context !is Activity) return@OutlinedButton
                    passkeyLoading = true
                    authViewModel.clearError()
                    scope.launch {
                        try {
                            val webAuthnApi = authViewModel.webAuthnApi
                            authViewModel.apiClient.baseUrl = serverUrl.trimEnd('/')
                            val begin = webAuthnApi.beginAssertion(email = email)
                            val helper = CredentialManagerHelper(context)
                            val assertionJson = helper.getPasskey(begin.publicKeyOptionsJson)
                            authViewModel.passkeyLogin(
                                serverUrl = serverUrl,
                                email = email,
                                ceremonyId = begin.ceremonyId,
                                assertionResponseJson = assertionJson,
                                unlockVault = { vaultKey -> viewModel.unlockWithKey(vaultKey) },
                                onSuccess = {
                                    authViewModel.syncNow()
                                    onUnlocked()
                                },
                                onNeedPassword = { envelopes, userId, deviceId ->
                                    // Stash so the password field below can finish
                                    // unlocking via passkeyUnlockWithPassword.
                                    needPasswordEnvelopes = envelopes
                                    needPasswordUserId = userId
                                    needPasswordDeviceId = deviceId
                                    password = ""
                                    focusRequester.requestFocus()
                                },
                                onComplete = { passkeyLoading = false },
                            )
                        } catch (_: PasskeyCancelledException) {
                            passkeyLoading = false
                        } catch (e: Exception) {
                            passkeyLoading = false
                            authViewModel.setError(e.message ?: "Passkey unlock failed")
                        }
                    }
                },
                enabled = !loading && !passkeyLoading,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (passkeyLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Verifying...")
                } else {
                    Icon(
                        Icons.Default.Key,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Unlock with passkey")
                }
            }
        }
    }
}
