package io.github.pstanar.pstotp.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.components.IconPicker

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditAccountScreen(
    viewModel: VaultViewModel,
    entryId: String,
    onSaved: () -> Unit,
    onCancel: () -> Unit,
) {
    val entry = viewModel.getEntry(entryId)
    if (entry == null) {
        onCancel()
        return
    }

    var issuer by remember { mutableStateOf(entry.issuer) }
    var accountName by remember { mutableStateOf(entry.accountName) }
    var icon by remember { mutableStateOf(entry.icon) }
    var saving by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Edit Account") },
                navigationIcon = {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .padding(horizontal = 16.dp, vertical = 16.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            OutlinedTextField(
                value = issuer,
                onValueChange = { issuer = it },
                label = { Text("Service Name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedTextField(
                value = accountName,
                onValueChange = { accountName = it },
                label = { Text("Account") },
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

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = {
                    saving = true
                    viewModel.updateEntry(
                        entry.copy(
                            issuer = issuer.trim().ifEmpty { "Unknown" },
                            accountName = accountName.trim().ifEmpty { "Account" },
                            icon = icon,
                        ),
                        onComplete = onSaved,
                    )
                },
                enabled = !saving,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (saving) "Saving..." else "Save")
            }
        }
    }
}
