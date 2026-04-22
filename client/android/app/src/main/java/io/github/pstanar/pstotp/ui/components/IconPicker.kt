package io.github.pstanar.pstotp.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.pstanar.pstotp.core.model.LibraryIcon
import io.github.pstanar.pstotp.core.model.MAX_LIBRARY_ICONS
import io.github.pstanar.pstotp.core.util.IconFetch
import io.github.pstanar.pstotp.ui.VaultViewModel
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.net.URI

private val COMMON_EMOJIS = listOf(
    "🔒", "🔑", "📧", "💻", "☁️",
    "🏦", "🛒", "🎮", "📱", "🌐",
    "💳", "🎓", "⚙️", "🛡️", "🤖",
    "💬", "🎥", "🎵", "📚", "✈️",
)

private const val MAX_ICON_SIZE = 64

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun IconPicker(
    currentIcon: String?,
    issuer: String,
    onIconChanged: (String?) -> Unit,
    vaultViewModel: VaultViewModel? = null,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var urlInput by remember { mutableStateOf("") }
    var fetching by remember { mutableStateOf(false) }
    var urlError by remember { mutableStateOf<String?>(null) }

    val libraryIcons by (vaultViewModel?.libraryIcons?.collectAsState() ?: remember {
        mutableStateOf(emptyList<LibraryIcon>())
    })

    // Parallels the web's adoptIcon: set the entry icon, then save to the library
    // (skipping duplicates and respecting the hard cap). Only runs when the caller
    // supplied a VaultViewModel — standalone call sites keep the picker local.
    fun adoptIcon(dataUrl: String, label: String) {
        onIconChanged(dataUrl)
        val vm = vaultViewModel ?: return
        val current = libraryIcons
        if (current.any { it.data == dataUrl }) return
        if (current.size >= MAX_LIBRARY_ICONS) {
            Toast.makeText(
                context,
                "Library is full ($MAX_LIBRARY_ICONS max). Icon saved to entry but not added to library.",
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        vm.addLibraryIcon(label.ifBlank { "Icon" }, dataUrl) { msg ->
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
        }
    }

    val photoLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        try {
            val inputStream = context.contentResolver.openInputStream(uri)
            val original = BitmapFactory.decodeStream(inputStream)
            inputStream?.close()
            if (original == null) return@rememberLauncherForActivityResult

            // Scale to fit MAX_ICON_SIZE x MAX_ICON_SIZE, center crop
            val scale = maxOf(
                MAX_ICON_SIZE.toFloat() / original.width,
                MAX_ICON_SIZE.toFloat() / original.height,
            )
            val scaledW = (original.width * scale).toInt()
            val scaledH = (original.height * scale).toInt()
            val scaled = Bitmap.createScaledBitmap(original, scaledW, scaledH, true)

            val x = (scaledW - MAX_ICON_SIZE) / 2
            val y = (scaledH - MAX_ICON_SIZE) / 2
            val cropped = Bitmap.createBitmap(scaled, x, y, MAX_ICON_SIZE, MAX_ICON_SIZE)

            val baos = ByteArrayOutputStream()
            cropped.compress(Bitmap.CompressFormat.PNG, 100, baos)
            val base64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
            val dataUrl = "data:image/png;base64,$base64"
            adoptIcon(dataUrl, issuer.trim())

            original.recycle()
            if (scaled !== original) scaled.recycle()
            if (cropped !== scaled) cropped.recycle()
        } catch (_: Exception) {
            // Silently fail on bad images
        }
    }

    Column {
        Text("Icon", style = MaterialTheme.typography.labelMedium)
        Spacer(modifier = Modifier.height(8.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            // Preview
            ServiceIcon(issuer = issuer, icon = currentIcon, size = 48)

            Spacer(modifier = Modifier.width(12.dp))

            // Upload button
            OutlinedButton(onClick = {
                photoLauncher.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }) {
                Icon(Icons.Default.Upload, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text("Upload")
            }

            // Clear button
            if (currentIcon != null) {
                Spacer(modifier = Modifier.width(4.dp))
                IconButton(onClick = { onIconChanged(null) }) {
                    Icon(
                        Icons.Default.Clear,
                        contentDescription = "Clear icon",
                        tint = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // URL input
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = urlInput,
                onValueChange = { urlInput = it; urlError = null },
                label = { Text("Icon URL", style = MaterialTheme.typography.bodySmall) },
                placeholder = { Text("https://example.com/favicon.ico", style = MaterialTheme.typography.bodySmall) },
                singleLine = true,
                enabled = !fetching,
                textStyle = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f),
            )
            Spacer(modifier = Modifier.width(8.dp))
            OutlinedButton(
                enabled = urlInput.isNotBlank() && !fetching,
                onClick = {
                    scope.launch {
                        fetching = true
                        urlError = null
                        val trimmed = urlInput.trim()
                        val result = IconFetch.downloadAsDataUrl(trimmed)
                        fetching = false
                        if (result != null) {
                            val host = runCatching { URI(trimmed).host }.getOrNull()
                                ?.takeIf { it.isNotBlank() }
                                ?: issuer.trim().ifBlank { "Icon" }
                            adoptIcon(result, host)
                            urlInput = ""
                        } else {
                            urlError = "Could not fetch image"
                        }
                    }
                },
            ) {
                Text(if (fetching) "..." else "Fetch")
            }
        }
        if (urlError != null) {
            Text(
                urlError!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }

        // "My Icons" library — only shown when a VaultViewModel was wired in.
        if (vaultViewModel != null) {
            Spacer(modifier = Modifier.height(12.dp))
            MyIconsSection(
                icons = libraryIcons,
                currentIcon = currentIcon,
                onPick = { onIconChanged(it) },
                onRename = { id, label ->
                    vaultViewModel.renameLibraryIcon(id, label) { msg ->
                        Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                    }
                },
                onDelete = { id ->
                    vaultViewModel.removeLibraryIcon(id) { msg ->
                        Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                    }
                },
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Emoji grid
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            COMMON_EMOJIS.forEach { emoji ->
                val selected = currentIcon == emoji
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .then(
                            if (selected) Modifier.border(
                                2.dp,
                                MaterialTheme.colorScheme.primary,
                                RoundedCornerShape(8.dp),
                            ) else Modifier
                        )
                        .clickable { onIconChanged(emoji) },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(text = emoji, fontSize = 22.sp)
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MyIconsSection(
    icons: List<LibraryIcon>,
    currentIcon: String?,
    onPick: (String) -> Unit,
    onRename: (String, String) -> Unit,
    onDelete: (String) -> Unit,
) {
    var renameTarget by remember { mutableStateOf<LibraryIcon?>(null) }

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (icons.isEmpty()) "My icons" else "My icons (${icons.size}/$MAX_LIBRARY_ICONS)",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    Spacer(modifier = Modifier.height(4.dp))

    if (icons.isEmpty()) {
        Text(
            "No custom icons yet. Upload an image or fetch one from a URL — it'll be saved here for reuse.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    } else {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 160.dp)
                .verticalScroll(rememberScrollState()),
        ) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                icons.forEach { libIcon ->
                    val selected = currentIcon == libIcon.data
                    val bitmap = remember(libIcon.data) { decodeDataUrlToBitmap(libIcon.data) }
                    var menuExpanded by remember(libIcon.id) { mutableStateOf(false) }
                    Box(
                        modifier = Modifier
                            .size(44.dp)
                            .then(
                                if (selected) Modifier.border(
                                    2.dp,
                                    MaterialTheme.colorScheme.primary,
                                    RoundedCornerShape(4.dp),
                                ) else Modifier.border(
                                    2.dp,
                                    MaterialTheme.colorScheme.outline.copy(alpha = 0.0f),
                                    RoundedCornerShape(4.dp),
                                )
                            ),
                    ) {
                        // Tap target for picking (the whole tile area)
                        Box(
                            modifier = Modifier
                                .matchParentSize()
                                .clickable { onPick(libIcon.data) },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (bitmap != null) {
                                Image(
                                    bitmap = bitmap.asImageBitmap(),
                                    contentDescription = libIcon.label,
                                    modifier = Modifier.size(36.dp),
                                )
                            } else {
                                Text("?", style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                        // Corner overflow — opens the per-tile action menu.
                        Box(
                            modifier = Modifier
                                .align(Alignment.TopEnd)
                                .padding(1.dp)
                                .size(18.dp)
                                .clip(CircleShape)
                                .background(
                                    MaterialTheme.colorScheme.surface.copy(alpha = 0.85f)
                                )
                                .clickable { menuExpanded = true },
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Default.MoreVert,
                                contentDescription = "Icon options",
                                modifier = Modifier.size(12.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            DropdownMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text("Rename") },
                                    onClick = { menuExpanded = false; renameTarget = libIcon },
                                )
                                DropdownMenuItem(
                                    text = {
                                        Text("Delete", color = MaterialTheme.colorScheme.error)
                                    },
                                    onClick = { menuExpanded = false; onDelete(libIcon.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Rename dialog
    renameTarget?.let { target ->
        var draft by remember(target.id) { mutableStateOf(target.label) }
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("Rename icon") },
            text = {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    singleLine = true,
                    label = { Text("Label") },
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    onRename(target.id, draft.trim().ifBlank { "Icon" })
                    renameTarget = null
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) { Text("Cancel") }
            },
        )
    }
}

private fun decodeDataUrlToBitmap(dataUrl: String): Bitmap? {
    val comma = dataUrl.indexOf(',')
    if (comma < 0) return null
    val payload = dataUrl.substring(comma + 1)
    return try {
        val bytes = Base64.decode(payload, Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    } catch (_: Exception) {
        null
    }
}
