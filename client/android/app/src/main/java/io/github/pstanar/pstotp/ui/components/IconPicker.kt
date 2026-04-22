package io.github.pstanar.pstotp.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.util.IconFetch
import java.io.ByteArrayOutputStream

private val COMMON_EMOJIS = listOf(
    "\uD83D\uDD12", "\uD83D\uDD11", "\uD83D\uDCE7", "\uD83D\uDCBB", "\u2601\uFE0F",
    "\uD83C\uDFE6", "\uD83D\uDED2", "\uD83C\uDFAE", "\uD83D\uDCF1", "\uD83C\uDF10",
    "\uD83D\uDCB3", "\uD83C\uDF93", "\u2699\uFE0F", "\uD83D\uDEE1\uFE0F", "\uD83E\uDD16",
    "\uD83D\uDCAC", "\uD83C\uDFA5", "\uD83C\uDFB5", "\uD83D\uDCDA", "\u2708\uFE0F",
)

private const val MAX_ICON_SIZE = 64

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun IconPicker(
    currentIcon: String?,
    issuer: String,
    onIconChanged: (String?) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var urlInput by remember { mutableStateOf("") }
    var fetching by remember { mutableStateOf(false) }
    var urlError by remember { mutableStateOf<String?>(null) }

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
            onIconChanged("data:image/png;base64,$base64")

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
                        val result = IconFetch.downloadAsDataUrl(urlInput.trim())
                        fetching = false
                        if (result != null) {
                            onIconChanged(result)
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
