package io.github.pstanar.pstotp.ui.screens

import androidx.compose.animation.core.animateDpAsState
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.draw.shadow
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.Sort
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState
import io.github.pstanar.pstotp.core.model.LayoutMode
import io.github.pstanar.pstotp.core.model.OtpauthUri
import io.github.pstanar.pstotp.core.model.SortMode
import io.github.pstanar.pstotp.core.model.VaultEntry
import io.github.pstanar.pstotp.core.model.VaultEntryPlaintext
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.components.QrCodeDialog
import io.github.pstanar.pstotp.ui.components.TotpCard
import io.github.pstanar.pstotp.ui.components.TotpGridDetail
import io.github.pstanar.pstotp.ui.components.TotpGridTile

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VaultScreen(
    viewModel: VaultViewModel,
    onAddAccount: () -> Unit,
    onEditAccount: (String) -> Unit,
    onSettings: () -> Unit,
    onLock: () -> Unit,
) {
    val entries by viewModel.entries.collectAsStateWithLifecycle()
    val sortMode by viewModel.sortMode.collectAsStateWithLifecycle()
    val sortReversed by viewModel.sortReversed.collectAsStateWithLifecycle()
    val layoutMode by viewModel.layoutMode.collectAsStateWithLifecycle()
    val usage by viewModel.usage.collectAsStateWithLifecycle()
    val showNextCode by viewModel.showNextCode.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var qrEntry by remember { mutableStateOf<VaultEntry?>(null) }
    var deleteEntry by remember { mutableStateOf<VaultEntry?>(null) }
    var deleting by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var showSearch by remember { mutableStateOf(false) }
    var sortMenuOpen by remember { mutableStateOf(false) }

    // Sort is computed on enter / sort-mode change / direction toggle /
    // layout toggle / entries change, then cached. Copying an entry
    // records usage but doesn't re-sort mid-session — otherwise the row
    // would jump to the top while the user is still interacting with it.
    val sortedEntries = remember(sortMode, sortReversed, layoutMode, entries) {
        val snapshotUsage = usage
        val natural = when (sortMode) {
            SortMode.MANUAL -> entries
            SortMode.ALPHABETICAL -> entries.sortedWith(
                compareBy<VaultEntry> { it.issuer.lowercase() }.thenBy { it.accountName.lowercase() },
            )
            SortMode.LRU -> entries.sortedByDescending { snapshotUsage[it.id]?.lastUsedAt ?: 0L }
            SortMode.MFU -> entries.sortedWith(
                compareByDescending<VaultEntry> { snapshotUsage[it.id]?.useCount ?: 0 }
                    .thenByDescending { snapshotUsage[it.id]?.lastUsedAt ?: 0L },
            )
        }
        // Reversal doesn't apply to MANUAL — it's the user's own order.
        if (sortReversed && sortMode != SortMode.MANUAL) natural.reversed() else natural
    }
    val filteredEntries = if (searchQuery.isBlank()) sortedEntries else {
        val q = searchQuery.lowercase()
        sortedEntries.filter {
            it.issuer.lowercase().contains(q) || it.accountName.lowercase().contains(q)
        }
    }

    Scaffold(
        topBar = {
            if (showSearch) {
                TopAppBar(
                    title = {
                        OutlinedTextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            placeholder = { Text("Search accounts...") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = MaterialTheme.typography.bodyLarge,
                            trailingIcon = if (searchQuery.isNotEmpty()) {
                                {
                                    IconButton(onClick = { searchQuery = "" }) {
                                        Icon(Icons.Default.Close, contentDescription = "Clear search")
                                    }
                                }
                            } else null,
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = { showSearch = false; searchQuery = "" }) {
                            Icon(Icons.Default.Close, contentDescription = "Close search")
                        }
                    },
                )
            } else {
                TopAppBar(
                    title = { Text("PsTotp") },
                    actions = {
                        IconButton(onClick = {
                            viewModel.setLayoutMode(
                                if (layoutMode == LayoutMode.LIST) LayoutMode.GRID else LayoutMode.LIST,
                            )
                        }) {
                            Icon(
                                if (layoutMode == LayoutMode.LIST)
                                    Icons.Default.GridView
                                else Icons.AutoMirrored.Filled.List,
                                contentDescription =
                                    if (layoutMode == LayoutMode.LIST) "Grid view" else "List view",
                            )
                        }
                        Box {
                            IconButton(onClick = { sortMenuOpen = true }) {
                                Icon(Icons.AutoMirrored.Filled.Sort, contentDescription = "Sort")
                            }
                            DropdownMenu(
                                expanded = sortMenuOpen,
                                onDismissRequest = { sortMenuOpen = false },
                            ) {
                                SortMode.entries.forEach { mode ->
                                    DropdownMenuItem(
                                        text = { Text(mode.label) },
                                        leadingIcon = if (mode == sortMode) {
                                            { Icon(Icons.Default.Check, contentDescription = null) }
                                        } else null,
                                        onClick = { viewModel.setSortMode(mode); sortMenuOpen = false },
                                    )
                                }
                                // Direction selector. Matches the mode rows'
                                // visual pattern — leading Check when
                                // selected — so the active direction is
                                // glanceable. The arrow goes in the trailing
                                // slot as a direction cue that's always
                                // visible. Disabled for MANUAL.
                                HorizontalDivider()
                                DropdownMenuItem(
                                    text = { Text("Natural") },
                                    leadingIcon = if (!sortReversed) {
                                        { Icon(Icons.Default.Check, contentDescription = null) }
                                    } else null,
                                    trailingIcon = {
                                        Icon(
                                            Icons.Default.ArrowDownward,
                                            contentDescription = null,
                                        )
                                    },
                                    enabled = sortMode != SortMode.MANUAL,
                                    onClick = { viewModel.setSortReversed(false); sortMenuOpen = false },
                                )
                                DropdownMenuItem(
                                    text = { Text("Reversed") },
                                    leadingIcon = if (sortReversed) {
                                        { Icon(Icons.Default.Check, contentDescription = null) }
                                    } else null,
                                    trailingIcon = {
                                        Icon(
                                            Icons.Default.ArrowUpward,
                                            contentDescription = null,
                                        )
                                    },
                                    enabled = sortMode != SortMode.MANUAL,
                                    onClick = { viewModel.setSortReversed(true); sortMenuOpen = false },
                                )
                            }
                        }
                        IconButton(onClick = { showSearch = true }) {
                            Icon(Icons.Default.Search, contentDescription = "Search")
                        }
                        IconButton(onClick = onLock) {
                            Icon(Icons.Default.Lock, contentDescription = "Lock")
                        }
                        IconButton(onClick = onSettings) {
                            Icon(Icons.Default.Settings, contentDescription = "Settings")
                        }
                    },
                )
            }
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onAddAccount) {
                Icon(Icons.Default.Add, contentDescription = "Add account")
            }
        },
    ) { padding ->
        if (entries.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "Welcome to PsTotp",
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Tap + to add your first account",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else if (layoutMode == LayoutMode.GRID) {
            // Authy-style: detail panel on top shows the currently-selected
            // entry's live code + copy button; the grid below selects which
            // entry the panel displays. Our spin on it: the countdown is
            // shown as a ring around the detail icon (consistent with the
            // list view's per-row rings) as well as in text.
            var selectedId by remember { mutableStateOf<String?>(null) }
            LaunchedEffect(filteredEntries) {
                if (selectedId == null || filteredEntries.none { it.id == selectedId }) {
                    selectedId = filteredEntries.firstOrNull()?.id
                }
            }
            val selectedEntry = filteredEntries.firstOrNull { it.id == selectedId }
                ?: filteredEntries.firstOrNull()

            Column(modifier = Modifier.padding(padding)) {
                selectedEntry?.let { entry ->
                    TotpGridDetail(
                        entry = entry,
                        onCopy = { code, isNext ->
                            copyToClipboard(
                                context,
                                "TOTP Code",
                                code,
                                if (isNext) "Next code copied" else "Code copied",
                            )
                            viewModel.recordEntryUse(entry.id)
                        },
                        showNextCode = showNextCode,
                    )
                    HorizontalDivider()
                }
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 84.dp),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(filteredEntries, key = { it.id }) { entry ->
                        TotpGridTile(
                            entry = entry,
                            isSelected = entry.id == selectedId,
                            onSelect = { selectedId = entry.id },
                            onCopySecret = {
                                copyToClipboard(context, "Secret Key", entry.secret, "Secret key copied")
                            },
                            onShowQr = { qrEntry = entry },
                            onEdit = { onEditAccount(entry.id) },
                            onDelete = { deleteEntry = entry },
                        )
                    }
                }
            }
        } else {
            val lazyListState = rememberLazyListState()
            val reorderableLazyListState = rememberReorderableLazyListState(lazyListState) { from, to ->
                if (sortMode != SortMode.MANUAL) return@rememberReorderableLazyListState
                val list = filteredEntries.toMutableList()
                val fromIndex = list.indexOfFirst { it.id == from.key }
                val toIndex = list.indexOfFirst { it.id == to.key }
                if (fromIndex >= 0 && toIndex >= 0) {
                    val item = list.removeAt(fromIndex)
                    list.add(toIndex, item)
                    viewModel.reorderEntries(list.map { it.id })
                }
            }

            LazyColumn(
                state = lazyListState,
                modifier = Modifier.padding(padding),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(filteredEntries, key = { it.id }) { entry ->
                    ReorderableItem(reorderableLazyListState, key = entry.id) { isDragging ->
                        val elevation by animateDpAsState(
                            if (isDragging) 8.dp else 0.dp,
                            label = "dragElevation",
                        )
                        TotpCard(
                            entry = entry,
                            onCopy = { code, isNext ->
                                copyToClipboard(
                                    context,
                                    "TOTP Code",
                                    code,
                                    if (isNext) "Next code copied" else "Code copied",
                                )
                                viewModel.recordEntryUse(entry.id)
                            },
                            onCopySecret = {
                                copyToClipboard(context, "Secret Key", entry.secret, "Secret key copied")
                            },
                            onShowQr = { qrEntry = entry },
                            onEdit = { onEditAccount(entry.id) },
                            onDelete = { deleteEntry = entry },
                            dragModifier = Modifier.draggableHandle(),
                            showDragHandle = sortMode == SortMode.MANUAL,
                            showNextCode = showNextCode,
                            modifier = Modifier.shadow(elevation, shape = MaterialTheme.shapes.medium),
                        )
                    }
                }
            }
        }
    }

    // QR code dialog
    qrEntry?.let { entry ->
        val uri = OtpauthUri.build(
            VaultEntryPlaintext(
                issuer = entry.issuer,
                accountName = entry.accountName,
                secret = entry.secret,
                algorithm = entry.algorithm,
                digits = entry.digits,
                period = entry.period,
                icon = entry.icon,
            )
        )
        QrCodeDialog(
            uri = uri,
            title = "${entry.issuer} — ${entry.accountName}",
            onDismiss = { qrEntry = null },
        )
    }

    // Delete confirmation dialog
    deleteEntry?.let { entry ->
        AlertDialog(
            onDismissRequest = { deleteEntry = null },
            title = { Text("Delete Account") },
            text = { Text("Delete ${entry.issuer}? This cannot be undone.") },
            confirmButton = {
                TextButton(
                    enabled = !deleting,
                    onClick = {
                        deleting = true
                        viewModel.deleteEntry(entry.id) {
                            deleting = false
                            deleteEntry = null
                        }
                    },
                ) {
                    Text(
                        if (deleting) "Deleting..." else "Delete",
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteEntry = null }) {
                    Text("Cancel")
                }
            },
        )
    }
}

private const val CLIPBOARD_CLEAR_DELAY_MS = 30_000L

private fun copyToClipboard(context: Context, label: String, text: String, toast: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = ClipData.newPlainText(label, text)
    // Mark as sensitive so it won't appear in clipboard previews (API 33+)
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
        clip.description.extras = android.os.PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
    }
    clipboard.setPrimaryClip(clip)
    val seconds = CLIPBOARD_CLEAR_DELAY_MS / 1000
    Toast.makeText(context, "$toast — clearing in ${seconds}s", Toast.LENGTH_SHORT).show()

    // Auto-clear clipboard after the delay. Confirm the clear with a second
    // toast so the user knows the secret is gone and doesn't paste it into
    // the wrong place by habit.
    val appContext = context.applicationContext
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
                Toast.makeText(appContext, "Clipboard cleared", Toast.LENGTH_SHORT).show()
            }
        } catch (_: Exception) { }
    }, CLIPBOARD_CLEAR_DELAY_MS)
}
