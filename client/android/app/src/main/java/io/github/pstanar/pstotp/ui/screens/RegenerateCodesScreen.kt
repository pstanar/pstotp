package io.github.pstanar.pstotp.ui.screens

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
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.VaultViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RegenerateCodesScreen(
    authViewModel: AuthViewModel,
    vaultViewModel: VaultViewModel,
    onBack: () -> Unit,
) {
    // 0=confirm, 1=generating, 2=show codes
    var step by remember { mutableIntStateOf(0) }
    var password by remember { mutableStateOf("") }
    var codes by remember { mutableStateOf<List<String>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    val email by authViewModel.email.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Recovery Codes") },
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
                    Text("Regenerate Recovery Codes", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "This will invalidate all existing recovery codes and generate 8 new ones. Make sure you save the new codes.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    PasswordField(
                        value = password,
                        onValueChange = { password = it; error = null },
                        label = "Password",
                        modifier = Modifier.fillMaxWidth(),
                    )

                    if (error != null) {
                        Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    Button(
                        onClick = {
                            val vaultKey = vaultViewModel.getVaultKey()
                            if (vaultKey == null) {
                                error = "Vault is locked"
                                return@Button
                            }
                            step = 1; error = null
                            scope.launch {
                                try {
                                    codes = authViewModel.authService.regenerateRecoveryCodes(email, password, vaultKey)
                                    step = 2
                                } catch (e: Exception) {
                                    error = e.message ?: "Failed to regenerate codes"
                                    step = 0
                                }
                            }
                        },
                        enabled = password.isNotEmpty(),
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text("Regenerate Codes") }

                    OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                        Text("Cancel")
                    }
                }

                1 -> {
                    Text("Generating new recovery codes...", style = MaterialTheme.typography.bodyMedium)
                    Spacer(modifier = Modifier.height(16.dp))
                    CircularProgressIndicator()
                }

                2 -> {
                    Text("New Recovery Codes", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        "Your old codes are no longer valid. Save these new codes in a safe place.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(12.dp))

                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        codes.forEachIndexed { index, code ->
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
                    Button(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
                        Text("I've Saved My Codes")
                    }
                }
            }
        }
    }
}
