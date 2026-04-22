package io.github.pstanar.pstotp.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import io.github.pstanar.pstotp.core.model.OtpauthUri
import io.github.pstanar.pstotp.core.model.VaultEntryPlaintext
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.components.IconPicker
import io.github.pstanar.pstotp.ui.components.QrScanner

@Composable
internal fun QrScanTab(viewModel: VaultViewModel, onAccountAdded: () -> Unit) {
    var error by remember { mutableStateOf<String?>(null) }
    QrScanner(
        modifier = Modifier.fillMaxWidth().height(300.dp),
        onResult = { otpauthUri ->
            try {
                viewModel.addEntry(OtpauthUri.parse(otpauthUri), onComplete = onAccountAdded)
            } catch (e: Exception) {
                error = e.message ?: "Invalid QR code"
            }
        },
    )
    ErrorText(error)
    Spacer(modifier = Modifier.height(8.dp))
    Text(
        text = "Point your camera at a QR code",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
internal fun ImagePickTab(viewModel: VaultViewModel, onAccountAdded: () -> Unit) {
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }

    val photoLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        try {
            val inputImage = InputImage.fromFilePath(context, uri)
            BarcodeScanning.getClient().process(inputImage)
                .addOnSuccessListener { barcodes ->
                    val otpauth = barcodes.firstNotNullOfOrNull { it.rawValue }
                        ?.takeIf { it.startsWith("otpauth://") }
                    if (otpauth != null) {
                        try {
                            viewModel.addEntry(OtpauthUri.parse(otpauth), onComplete = onAccountAdded)
                        } catch (e: Exception) {
                            error = e.message ?: "Invalid QR code"
                        }
                    } else {
                        error = "No QR code found in image"
                    }
                }
                .addOnFailureListener { error = "Failed to scan image" }
        } catch (_: Exception) {
            error = "Failed to load image"
        }
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(32.dp))
        Icon(
            Icons.Default.Image,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(onClick = {
            photoLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }) {
            Text("Select image with QR code")
        }
    }
    ErrorText(error)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ManualEntryTab(viewModel: VaultViewModel, onAccountAdded: () -> Unit) {
    var issuer by remember { mutableStateOf("") }
    var accountName by remember { mutableStateOf("") }
    var secret by remember { mutableStateOf("") }
    var algorithm by remember { mutableStateOf("SHA1") }
    var digits by remember { mutableStateOf("6") }
    var period by remember { mutableStateOf("30") }
    var icon by remember { mutableStateOf<String?>(null) }
    var showAdvanced by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    OutlinedTextField(
        value = issuer,
        onValueChange = { issuer = it; error = null },
        label = { Text("Service Name") },
        placeholder = { Text("Google, GitHub, etc.") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(modifier = Modifier.height(12.dp))
    OutlinedTextField(
        value = accountName,
        onValueChange = { accountName = it },
        label = { Text("Account (optional)") },
        placeholder = { Text("alice@example.com") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(modifier = Modifier.height(12.dp))
    OutlinedTextField(
        value = secret,
        onValueChange = { secret = it; error = null },
        label = { Text("Secret Key") },
        placeholder = { Text("JBSWY3DPEHPK3PXP") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )

    Spacer(modifier = Modifier.height(16.dp))
    IconPicker(
        currentIcon = icon,
        issuer = issuer,
        onIconChanged = { icon = it },
        vaultViewModel = viewModel,
    )

    Spacer(modifier = Modifier.height(12.dp))
    TextButton(onClick = { showAdvanced = !showAdvanced }) {
        Icon(Icons.Default.KeyboardArrowDown, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(4.dp))
        Text("Advanced")
    }

    AnimatedVisibility(visible = showAdvanced) {
        Column {
            Spacer(modifier = Modifier.height(4.dp))
            var algorithmExpanded by remember { mutableStateOf(false) }
            val algorithms = listOf("SHA1" to "SHA-1 (default)", "SHA256" to "SHA-256", "SHA512" to "SHA-512")
            ExposedDropdownMenuBox(
                expanded = algorithmExpanded,
                onExpandedChange = { algorithmExpanded = it },
            ) {
                OutlinedTextField(
                    value = algorithms.first { it.first == algorithm }.second,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Algorithm") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = algorithmExpanded) },
                    modifier = Modifier.menuAnchor(MenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
                )
                ExposedDropdownMenu(
                    expanded = algorithmExpanded,
                    onDismissRequest = { algorithmExpanded = false },
                ) {
                    algorithms.forEach { (value, label) ->
                        DropdownMenuItem(
                            text = { Text(label) },
                            onClick = { algorithm = value; algorithmExpanded = false },
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    value = digits,
                    onValueChange = { digits = it },
                    label = { Text("Digits") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
                OutlinedTextField(
                    value = period,
                    onValueChange = { period = it },
                    label = { Text("Period (sec)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    ErrorText(error)
    Spacer(modifier = Modifier.height(24.dp))
    Button(
        onClick = {
            val trimmedSecret = secret.trim().replace(" ", "")
            if (trimmedSecret.isEmpty()) { error = "Secret key is required"; return@Button }
            val d = digits.toIntOrNull()
            if (d == null || d < 4 || d > 10) { error = "Digits must be between 4 and 10"; return@Button }
            val p = period.toIntOrNull()
            if (p == null || p <= 0) { error = "Period must be a positive number"; return@Button }
            viewModel.addEntry(
                VaultEntryPlaintext(
                    issuer = issuer.trim().ifEmpty { "Unknown" },
                    accountName = accountName.trim().ifEmpty { issuer.trim().ifEmpty { "Account" } },
                    secret = trimmedSecret.uppercase(),
                    algorithm = algorithm,
                    digits = d,
                    period = p,
                    icon = icon,
                ),
                onComplete = onAccountAdded,
            )
        },
        modifier = Modifier.fillMaxWidth(),
    ) { Text("Add") }
}

@Composable
internal fun PasteUriTab(viewModel: VaultViewModel, onAccountAdded: () -> Unit) {
    var uri by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }

    OutlinedTextField(
        value = uri,
        onValueChange = { uri = it; error = null },
        label = { Text("otpauth:// URI") },
        placeholder = { Text("otpauth://totp/Issuer:account?secret=...") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
    )
    ErrorText(error)
    Spacer(modifier = Modifier.height(24.dp))
    Button(
        onClick = {
            try {
                viewModel.addEntry(OtpauthUri.parse(uri.trim()), onComplete = onAccountAdded)
            } catch (e: Exception) {
                error = e.message ?: "Invalid URI"
            }
        },
        enabled = uri.isNotBlank(),
        modifier = Modifier.fillMaxWidth(),
    ) { Text("Add") }
}

@Composable
private fun ErrorText(error: String?) {
    if (error != null) {
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            error,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall,
        )
    }
}
