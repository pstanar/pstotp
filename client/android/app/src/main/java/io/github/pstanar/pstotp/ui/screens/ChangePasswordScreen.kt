package io.github.pstanar.pstotp.ui.screens

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.VaultViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChangePasswordScreen(
    authViewModel: AuthViewModel,
    vaultViewModel: VaultViewModel,
    onBack: () -> Unit,
) {
    var currentPassword by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Change Password") },
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
                "Changes the password on both this device and the server.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(4.dp))

            PasswordField(
                value = currentPassword,
                onValueChange = { currentPassword = it; error = null },
                label = "Current Password",
                enabled = !loading,
                imeAction = ImeAction.Next,
                modifier = Modifier.fillMaxWidth(),
            )

            PasswordField(
                value = newPassword,
                onValueChange = { newPassword = it; error = null },
                label = "New Password",
                enabled = !loading,
                imeAction = ImeAction.Next,
                modifier = Modifier.fillMaxWidth(),
            )

            PasswordField(
                value = confirmPassword,
                onValueChange = { confirmPassword = it; error = null },
                label = "Confirm New Password",
                enabled = !loading,
                modifier = Modifier.fillMaxWidth(),
            )

            if (error != null) {
                Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }

            Spacer(modifier = Modifier.height(8.dp))

            Button(
                onClick = {
                    if (newPassword != confirmPassword) {
                        error = "Passwords do not match"
                        return@Button
                    }
                    if (newPassword.length < 8) {
                        error = "Password must be at least 8 characters"
                        return@Button
                    }
                    val email = authViewModel.email.value
                    val vaultKey = vaultViewModel.getVaultKey()
                    if (email.isBlank() || vaultKey == null) {
                        error = "Not connected or vault locked"
                        return@Button
                    }

                    loading = true; error = null
                    scope.launch {
                        try {
                            authViewModel.authService.changePassword(
                                email = email,
                                currentPassword = currentPassword,
                                newPassword = newPassword,
                                vaultKey = vaultKey,
                            )
                            Toast.makeText(context, "Password changed", Toast.LENGTH_SHORT).show()
                            onBack()
                        } catch (e: Exception) {
                            error = e.message ?: "Password change failed"
                        } finally {
                            loading = false
                        }
                    }
                },
                enabled = !loading && currentPassword.isNotEmpty() && newPassword.isNotEmpty() && confirmPassword.isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (loading) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Changing...")
                } else {
                    Text("Change Password")
                }
            }
        }
    }
}
