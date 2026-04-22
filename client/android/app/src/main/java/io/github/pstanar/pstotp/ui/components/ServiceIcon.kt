package io.github.pstanar.pstotp.ui.components

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.github.pstanar.pstotp.core.ServiceBrands

@Composable
fun ServiceIcon(
    issuer: String,
    icon: String? = null,
    size: Int = 40,
) {
    val isDataUrl = icon?.startsWith("data:") == true
    val isEmoji = icon != null && !isDataUrl

    if (isDataUrl) {
        // Decode data URL: "data:image/png;base64,..." → bitmap
        val bitmap = remember(icon) {
            try {
                val base64Part = icon!!.substringAfter(",")
                val bytes = Base64.decode(base64Part, Base64.DEFAULT)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Exception) {
                null
            }
        }
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = issuer,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(size.dp)
                    .clip(CircleShape),
            )
            return
        }
    }

    if (isEmoji) {
        Box(
            modifier = Modifier
                .size(size.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = icon!!,
                fontSize = (size / 1.8).sp,
            )
        }
        return
    }

    // Fallback: brand letter
    val brand = ServiceBrands.get(issuer)
    val bgColor = if (brand != null) Color(brand.bg) else MaterialTheme.colorScheme.surfaceVariant
    val fgColor = if (brand != null) Color(brand.fg) else MaterialTheme.colorScheme.onSurfaceVariant
    val letter = brand?.letter ?: issuer.firstOrNull()?.uppercase() ?: "?"

    Box(
        modifier = Modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(bgColor),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = letter,
            color = fgColor,
            fontSize = (size / 2.5).sp,
            fontWeight = FontWeight.Bold,
        )
    }
}
