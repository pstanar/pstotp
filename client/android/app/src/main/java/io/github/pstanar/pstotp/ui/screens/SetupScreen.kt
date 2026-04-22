package io.github.pstanar.pstotp.ui.screens

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
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.pstanar.pstotp.R
import io.github.pstanar.pstotp.ui.components.PasswordField
import io.github.pstanar.pstotp.ui.VaultViewModel

@Composable
fun SetupScreen(
    viewModel: VaultViewModel,
    onSetupComplete: () -> Unit,
) {
    var password by remember { mutableStateOf("") }
    var confirmPassword by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }

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
            text = "Create a password to protect your vault",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(32.dp))

        val submit = {
            val validationError = validatePassword(password, confirmPassword)
            if (validationError != null) {
                error = validationError
            } else if (!loading) {
                loading = true
                viewModel.setupPassword(password) {
                    loading = false
                    onSetupComplete()
                }
            }
        }

        PasswordField(
            value = password,
            onValueChange = { password = it; error = null },
            label = "Password",
            enabled = !loading,
            imeAction = ImeAction.Next,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(modifier = Modifier.height(12.dp))

        PasswordField(
            value = confirmPassword,
            onValueChange = { confirmPassword = it; error = null },
            label = "Confirm Password",
            enabled = !loading,
            imeAction = ImeAction.Done,
            keyboardActions = KeyboardActions(onDone = { submit() }),
            modifier = Modifier.fillMaxWidth(),
        )

        if (error != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = error!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = { submit() },
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
                Text("Creating vault...")
            } else {
                Text("Create Vault")
            }
        }
    }
}

private fun validatePassword(password: String, confirm: String): String? {
    if (password.length < 8) return "Password must be at least 8 characters"
    if (!password.any { it.isUpperCase() }) return "Must contain an uppercase letter"
    if (!password.any { it.isLowerCase() }) return "Must contain a lowercase letter"
    if (!password.any { it.isDigit() }) return "Must contain a number"
    if (!password.any { !it.isLetterOrDigit() }) return "Must contain a special character"
    if (password != confirm) return "Passwords do not match"
    return null
}
