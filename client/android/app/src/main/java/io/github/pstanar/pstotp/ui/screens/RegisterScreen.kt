package io.github.pstanar.pstotp.ui.screens

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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.ui.AuthViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RegisterScreen(
    authViewModel: AuthViewModel,
    serverUrl: String,
    onRegistered: (vaultKey: ByteArray) -> Unit,
    onBack: () -> Unit,
) {
    var step by remember { mutableIntStateOf(0) } // 0=email, 1=verify, 2=password, 3=processing, 4=recovery codes
    var email by remember { mutableStateOf("") }
    var verificationCode by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var registrationSessionId by remember { mutableStateOf<String?>(null) }
    var recoveryCodes by remember { mutableStateOf<List<String>>(emptyList()) }
    // Freshly-generated vault key returned by the server — handed to the
    // caller when the user finishes the recovery-codes step so
    // VaultViewModel is unlocked in memory immediately.
    var registeredVaultKey by remember { mutableStateOf<ByteArray?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Create Account") },
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
            Text(
                "Register on ${serverUrl.removePrefix("https://").removePrefix("http://").removeSuffix("/api")}",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(4.dp))

            when (step) {
                0 -> {
                    // Email step
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it; error = null },
                        label = { Text("Email") },
                        singleLine = true,
                        enabled = !loading,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Done),
                        modifier = Modifier.fillMaxWidth(),
                    )

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Button(
                        onClick = {
                            loading = true; error = null
                            scope.launch {
                                try {
                                    val result = authViewModel.authService.registerBegin(serverUrl, email.trim())
                                    registrationSessionId = result.registrationSessionId
                                    if (result.emailVerificationRequired) {
                                        result.verificationCode?.let { verificationCode = it }
                                        step = 1
                                    } else {
                                        step = 2
                                    }
                                } catch (e: Exception) {
                                    error = e.message ?: "Registration failed"
                                } finally {
                                    loading = false
                                }
                            }
                        },
                        enabled = !loading && email.isNotBlank(),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        if (loading) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                            Spacer(modifier = Modifier.width(8.dp))
                        }
                        Text("Continue")
                    }
                }

                1 -> {
                    // Verification code step
                    Text("Enter the verification code sent to $email", style = MaterialTheme.typography.bodyMedium)

                    OutlinedTextField(
                        value = verificationCode,
                        onValueChange = { verificationCode = it; error = null },
                        label = { Text("Verification Code") },
                        singleLine = true,
                        enabled = !loading,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Button(
                        onClick = {
                            loading = true; error = null
                            scope.launch {
                                try {
                                    val verified = authViewModel.authService.verifyEmail(registrationSessionId!!, verificationCode.trim())
                                    if (verified) {
                                        step = 2
                                    } else {
                                        error = "Invalid verification code"
                                    }
                                } catch (e: Exception) {
                                    error = e.message ?: "Verification failed"
                                } finally {
                                    loading = false
                                }
                            }
                        },
                        enabled = !loading && verificationCode.isNotBlank(),
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Verify") }
                }

                2 -> {
                    // Password step
                    PasswordField(
                        value = password,
                        onValueChange = { password = it; error = null },
                        label = "Password",
                        enabled = !loading,
                        imeAction = ImeAction.Next,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    PasswordField(
                        value = confirmPassword,
                        onValueChange = { confirmPassword = it; error = null },
                        label = "Confirm Password",
                        enabled = !loading,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Button(
                        onClick = {
                            if (password != confirmPassword) {
                                error = "Passwords do not match"
                                return@Button
                            }
                            if (password.length < 8) {
                                error = "Password must be at least 8 characters"
                                return@Button
                            }
                            step = 3
                            loading = true; error = null
                            scope.launch {
                                try {
                                    val result = authViewModel.authService.register(
                                        serverUrl = serverUrl,
                                        email = email.trim(),
                                        password = password,
                                        registrationSessionId = registrationSessionId,
                                    )
                                    recoveryCodes = result.recoveryCodes
                                    registeredVaultKey = result.vaultKey
                                    step = 4
                                } catch (e: Exception) {
                                    error = e.message ?: "Registration failed"
                                    step = 2
                                } finally {
                                    loading = false
                                }
                            }
                        },
                        enabled = !loading && password.isNotEmpty() && confirmPassword.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Create Account") }
                }

                3 -> {
                    // Processing
                    Text("Creating account...", style = MaterialTheme.typography.bodyMedium)
                    Text("This may take a moment (key derivation).",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(modifier = Modifier.height(16.dp))
                    CircularProgressIndicator()

                    if (error != null) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }

                4 -> {
                    // Recovery codes
                    Text("Save Your Recovery Codes", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Store these codes in a safe place. They are the only way to recover your account if you lose all your devices.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(12.dp))

                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        recoveryCodes.forEachIndexed { index, code ->
                            Text(
                                "${index + 1}. $code",
                                style = MaterialTheme.typography.bodyMedium,
                                fontFamily = FontFamily.Monospace,
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    Button(
                        onClick = {
                            registeredVaultKey?.let { onRegistered(it) }
                        },
                        enabled = registeredVaultKey != null,
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("I've Saved My Codes") }
                }
            }
        }
    }
}
