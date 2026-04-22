package io.github.pstanar.pstotp.ui.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import io.github.pstanar.pstotp.core.crypto.TotpGenerator
import io.github.pstanar.pstotp.core.model.VaultEntry

/**
 * Authy-style detail panel for the grid view: big centered icon with our
 * countdown ring around it, issuer + account underneath, the TOTP code
 * rendered large and monospace, and a "token expires in Xs" line with an
 * inline copy button. The grid below selects which entry the panel shows.
 *
 * "Our flare" vs Authy: the countdown shows as a ring around the icon
 * (our signature visual, consistent with the list view's per-row rings)
 * in addition to the text countdown.
 */
@Composable
fun TotpGridDetail(
    entry: VaultEntry,
    onCopy: (code: String, isNext: Boolean) -> Unit,
    showNextCode: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var code by remember(entry.id) { mutableStateOf("") }
    var nextCode by remember(entry.id) { mutableStateOf("") }
    var timeLeft by remember(entry.id) { mutableIntStateOf(entry.period) }

    LaunchedEffect(entry.id, entry.secret, entry.period) {
        while (true) {
            val now = System.currentTimeMillis() / 1000
            code = TotpGenerator.generate(entry.secret, entry.algorithm, entry.digits, entry.period, now)
            nextCode = TotpGenerator.generate(entry.secret, entry.algorithm, entry.digits, entry.period, now + entry.period)
            timeLeft = TotpGenerator.timeRemaining(entry.period)
            delay(1000)
        }
    }

    // The whole panel is tappable — code, icon, issuer, countdown line all
    // copy. The explicit IconButton stays as a discoverability affordance
    // but it isn't the only way to trigger copy. Consistent with the list
    // view where any tap on a row copies.
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clickable {
                val useNext = showNextCode && timeLeft <= 3 && nextCode.isNotEmpty()
                val pick = if (useNext) nextCode else code
                if (pick.isNotEmpty()) onCopy(pick, useNext)
            }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CountdownRing(period = entry.period, size = 72.dp, strokeWidth = 3.dp) {
            ServiceIcon(issuer = entry.issuer, icon = entry.icon, size = 52)
        }

        Spacer(modifier = Modifier.height(10.dp))

        Text(
            text = entry.issuer,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (entry.accountName.isNotBlank() && entry.accountName != entry.issuer) {
            Text(
                text = entry.accountName,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Big code, split so the digits breathe.
        AnimatedContent(
            targetState = code,
            transitionSpec = { fadeIn() togetherWith fadeOut() },
            label = "code",
        ) { visible ->
            val (first, second) = splitCode(visible)
            Row(
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = first,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 44.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 2.sp,
                )
                Spacer(modifier = Modifier.width(14.dp))
                Text(
                    text = second,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 44.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 2.sp,
                )
            }
        }

        // Next-code preview — only in the last 10s so the panel doesn't
        // grow at rest. Indicates which code will be handed to the
        // clipboard if the user taps during the final 3s.
        if (showNextCode && timeLeft <= 10 && nextCode.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            val previewColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
            Row(
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "next",
                    style = MaterialTheme.typography.labelSmall,
                    color = previewColor,
                )
                Spacer(modifier = Modifier.width(8.dp))
                val (nextFirst, nextSecond) = splitCode(nextCode)
                Text(
                    text = nextFirst,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 1.sp,
                    color = previewColor,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = nextSecond,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 1.sp,
                    color = previewColor,
                )
            }
        }

        Spacer(modifier = Modifier.height(6.dp))

        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(modifier = Modifier.width(40.dp)) // balance for the copy button on the right
            Text(
                text = "Your token expires in ${timeLeft}s",
                style = MaterialTheme.typography.bodySmall,
                color = if (timeLeft <= 5) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            IconButton(
                onClick = {
                    val useNext = showNextCode && timeLeft <= 3 && nextCode.isNotEmpty()
                    val pick = if (useNext) nextCode else code
                    if (pick.isNotEmpty()) onCopy(pick, useNext)
                },
                modifier = Modifier.size(40.dp),
            ) {
                Icon(
                    Icons.Default.ContentCopy,
                    contentDescription = "Copy code",
                    modifier = Modifier.size(22.dp),
                )
            }
        }
    }
}

private fun splitCode(code: String): Pair<String, String> {
    if (code.isEmpty()) return "" to ""
    val mid = (code.length + 1) / 2
    return code.take(mid) to code.drop(mid)
}
