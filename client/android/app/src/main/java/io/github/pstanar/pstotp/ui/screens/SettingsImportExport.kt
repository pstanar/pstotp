package io.github.pstanar.pstotp.ui.screens

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.pstanar.pstotp.core.model.ImportAction
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.components.PasswordField

/**
 * The Import & Export section of SettingsScreen: the two buttons (Export /
 * Import) plus all four dialogs they can spawn. Bundled together because
 * they share transient state (selected format, export password, pending
 * import content, etc.) that shouldn't leak into the parent screen.
 */
@Composable
fun SettingsImportExport(viewModel: VaultViewModel?) {
    if (viewModel == null) return
    val context = LocalContext.current

    // Export state
    var showExportDialog by remember { mutableStateOf(false) }
    var exportFormat by remember { mutableStateOf("encrypted") }
    var exportPassword by remember { mutableStateOf("") }

    // Import state
    var showImportPasswordDialog by remember { mutableStateOf(false) }
    var importPassword by remember { mutableStateOf("") }
    var pendingImportContent by remember { mutableStateOf<String?>(null) }

    val saveLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val data = viewModel.getExportData(exportFormat, exportPassword.ifEmpty { null })
        if (data != null) {
            context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray()) }
            Toast.makeText(context, "Vault exported", Toast.LENGTH_SHORT).show()
        }
        showExportDialog = false
        exportPassword = ""
    }

    val openLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val content = context.contentResolver.openInputStream(uri)?.bufferedReader()?.readText()
        if (content == null) {
            Toast.makeText(context, "Failed to read file", Toast.LENGTH_SHORT).show()
            return@rememberLauncherForActivityResult
        }
        pendingImportContent = content
        viewModel.prepareImport(content)
    }

    // React to NEEDS_PASSWORD from async prepareImport
    val error by viewModel.error.collectAsStateWithLifecycle()
    LaunchedEffect(error) {
        if (error == "NEEDS_PASSWORD") {
            viewModel.clearError()
            showImportPasswordDialog = true
        }
    }

    // --- Section UI (rendered inline in the Settings Column) ---
    Text("Import & Export", style = MaterialTheme.typography.titleMedium)
    Spacer(modifier = Modifier.height(8.dp))
    Text(
        "Export your vault or import from another authenticator.",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(modifier = Modifier.height(12.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = { showExportDialog = true }) { Text("Export") }
        OutlinedButton(onClick = {
            openLauncher.launch(arrayOf("application/json", "text/plain"))
        }) { Text("Import") }
    }

    // --- Dialogs (render as overlays regardless of where they're invoked) ---

    if (showExportDialog) {
        ExportDialog(
            format = exportFormat,
            onFormatChange = { exportFormat = it },
            password = exportPassword,
            onPasswordChange = { exportPassword = it },
            onConfirm = {
                val ext = if (exportFormat == "otpauth") ".txt" else ".json"
                saveLauncher.launch("pstotp-export$ext")
            },
            onDismiss = { showExportDialog = false },
        )
    }

    // Icon download progress
    val iconProgress by viewModel.iconProgress.collectAsStateWithLifecycle()
    iconProgress?.let { (done, total) -> IconDownloadProgressDialog(done, total) }

    if (showImportPasswordDialog) {
        ImportPasswordDialog(
            password = importPassword,
            onPasswordChange = { importPassword = it },
            onConfirm = {
                pendingImportContent?.let { content -> viewModel.prepareImport(content, importPassword) }
                showImportPasswordDialog = false
                pendingImportContent = null
                importPassword = ""
            },
            onDismiss = {
                showImportPasswordDialog = false
                pendingImportContent = null
            },
        )
    }

    // Import preview + conflict resolution
    val candidates by viewModel.importCandidates.collectAsStateWithLifecycle()
    val currentDuplicateAction by viewModel.duplicateAction.collectAsStateWithLifecycle()
    candidates?.let { list ->
        ImportPreviewDialog(
            candidates = list,
            duplicateAction = currentDuplicateAction,
            onSetDuplicateAction = viewModel::setDuplicateAction,
            onSetCandidateAction = viewModel::setImportCandidateAction,
            onConfirm = { onComplete ->
                viewModel.confirmImport { count ->
                    onComplete()
                    Toast.makeText(context, "Imported $count entries", Toast.LENGTH_SHORT).show()
                }
            },
            onCancel = { viewModel.cancelImport() },
        )
    }
}

@Composable
private fun ExportDialog(
    format: String,
    onFormatChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Export Vault") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    FilterChip(selected = format == "encrypted",
                        onClick = { onFormatChange("encrypted") },
                        label = { Text("Encrypted") })
                    FilterChip(selected = format == "plain",
                        onClick = { onFormatChange("plain") },
                        label = { Text("Plain JSON") })
                    FilterChip(selected = format == "otpauth",
                        onClick = { onFormatChange("otpauth") },
                        label = { Text("otpauth:// URIs") })
                }
                if (format == "encrypted") {
                    PasswordField(value = password, onValueChange = onPasswordChange, label = "Export Password")
                }
                if (format != "encrypted") {
                    Text(
                        "TOTP secrets will be visible in the file.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = format != "encrypted" || password.isNotEmpty(),
                onClick = onConfirm,
            ) { Text("Export") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun IconDownloadProgressDialog(done: Int, total: Int) {
    AlertDialog(
        onDismissRequest = { /* non-dismissable during download */ },
        title = { Text("Downloading icons") },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(12.dp))
                Text("$done / $total", style = MaterialTheme.typography.bodyMedium)
            }
        },
        confirmButton = {},
    )
}

@Composable
private fun ImportPasswordDialog(
    password: String,
    onPasswordChange: (String) -> Unit,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Decrypt Import") },
        text = {
            Column {
                Text("This file is encrypted.", style = MaterialTheme.typography.bodySmall)
                Spacer(modifier = Modifier.height(12.dp))
                PasswordField(value = password, onValueChange = onPasswordChange, label = "Password")
            }
        },
        confirmButton = {
            TextButton(enabled = password.isNotEmpty(), onClick = onConfirm) { Text("Decrypt") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ImportPreviewDialog(
    candidates: List<io.github.pstanar.pstotp.core.model.ImportCandidate>,
    duplicateAction: ImportAction,
    onSetDuplicateAction: (ImportAction) -> Unit,
    onSetCandidateAction: (Int, ImportAction) -> Unit,
    onConfirm: (onComplete: () -> Unit) -> Unit,
    onCancel: () -> Unit,
) {
    val duplicateCount = candidates.count { it.isDuplicate }
    val activeCount = candidates.count { it.action != ImportAction.SKIP }
    var importing by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onCancel,
        title = {
            Text(buildString {
                append("${candidates.size} entries found")
                if (duplicateCount > 0) append(" ($duplicateCount duplicate${if (duplicateCount != 1) "s" else ""})")
            })
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (duplicateCount > 0) {
                    Text("Duplicates:", style = MaterialTheme.typography.labelMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        ImportAction.entries.forEach { action ->
                            FilterChip(
                                selected = duplicateAction == action,
                                onClick = { onSetDuplicateAction(action) },
                                label = { Text(action.label(), style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                    }
                    HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                }

                Column(
                    modifier = Modifier.heightIn(max = 300.dp)
                        .then(Modifier.verticalScroll(rememberScrollState())),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    candidates.forEachIndexed { index, candidate ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    "${candidate.imported.issuer} \u2014 ${candidate.imported.accountName}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (candidate.action == ImportAction.SKIP)
                                        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                    else MaterialTheme.colorScheme.onSurface,
                                )
                                if (candidate.isDuplicate) {
                                    Text(
                                        "DUPLICATE",
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.tertiary,
                                    )
                                }
                            }
                            if (candidate.isDuplicate) {
                                var expanded by remember { mutableStateOf(false) }
                                Box {
                                    TextButton(onClick = { expanded = true }) {
                                        Text(candidate.action.label(), style = MaterialTheme.typography.labelSmall)
                                    }
                                    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                                        ImportAction.entries.forEach { action ->
                                            DropdownMenuItem(
                                                text = { Text(action.label()) },
                                                onClick = {
                                                    onSetCandidateAction(index, action)
                                                    expanded = false
                                                },
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = activeCount > 0 && !importing,
                onClick = {
                    importing = true
                    onConfirm { importing = false }
                },
            ) { Text(if (importing) "Importing..." else "Import $activeCount") }
        },
        dismissButton = {
            TextButton(onClick = onCancel, enabled = !importing) { Text("Cancel") }
        },
    )
}

private fun ImportAction.label(): String = when (this) {
    ImportAction.OVERWRITE -> "Overwrite"
    ImportAction.ADD_COPY -> "Add copy"
    ImportAction.SKIP -> "Skip"
}
