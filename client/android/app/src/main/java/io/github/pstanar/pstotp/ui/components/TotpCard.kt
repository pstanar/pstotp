package io.github.pstanar.pstotp.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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

@Composable
fun TotpCard(
    entry: VaultEntry,
    onCopy: (code: String, isNext: Boolean) -> Unit,
    onCopySecret: () -> Unit,
    onShowQr: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    dragModifier: Modifier = Modifier,
    showDragHandle: Boolean = true,
    showNextCode: Boolean = false,
    modifier: Modifier = Modifier,
) {
    // TOTP code — regenerate only at period boundaries.
    // Next code is the code for the step after the current one; used for
    // the preview shown during the last 10s and for the "copy fresh code"
    // behaviour when the user taps in the last 3s.
    var code by remember { mutableStateOf("") }
    var nextCode by remember { mutableStateOf("") }
    var timeLeft by remember { mutableIntStateOf(0) }

    LaunchedEffect(entry.secret, entry.period, entry.algorithm, entry.digits) {
        while (true) {
            val now = System.currentTimeMillis() / 1000
            code = TotpGenerator.generate(entry.secret, entry.algorithm, entry.digits, entry.period, now)
            nextCode = TotpGenerator.generate(entry.secret, entry.algorithm, entry.digits, entry.period, now + entry.period)
            timeLeft = TotpGenerator.timeRemaining(entry.period)
            delay(timeLeft * 1000L)
        }
    }

    // Countdown — only tick every second when nearing expiry
    LaunchedEffect(entry.period) {
        while (true) {
            val remaining = TotpGenerator.timeRemaining(entry.period)
            timeLeft = remaining
            if (remaining <= 10) {
                delay(1000)
            } else {
                delay((remaining - 10) * 1000L)
            }
        }
    }

    var menuExpanded by remember { mutableStateOf(false) }

    // Copy is the primary action. Tap anywhere on the card (except the
    // menu IconButton, which consumes its own taps). Matches Authy UX.
    // Within the last 3s we hand out the NEXT code so the user doesn't
    // paste a code that expired mid-flow — the preview below makes this
    // visible ahead of time.
    Card(
        onClick = {
            val useNext = showNextCode && timeLeft <= 3 && nextCode.isNotEmpty()
            onCopy(if (useNext) nextCode else code, useNext)
        },
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .padding(start = 4.dp, end = 8.dp, top = 8.dp, bottom = 8.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Drag handle
            if (showDragHandle) {
                Icon(
                    Icons.Default.DragHandle,
                    contentDescription = "Drag to reorder",
                    modifier = dragModifier
                        .size(24.dp)
                        .padding(end = 4.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Service icon with countdown ring — spans full card height
            CountdownRing(period = entry.period, size = 48.dp) {
                ServiceIcon(issuer = entry.issuer, icon = entry.icon, size = 36)
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Issuer + code stacked
            Column(modifier = Modifier.weight(1f)) {
                // Issuer row with menu
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = entry.issuer,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Normal,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )

                    // Menu
                    Box {
                        IconButton(
                            onClick = { menuExpanded = true },
                            modifier = Modifier.size(32.dp),
                        ) {
                            Icon(
                                Icons.Default.MoreVert,
                                contentDescription = "More options",
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        DropdownMenu(
                            expanded = menuExpanded,
                            onDismissRequest = { menuExpanded = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Copy Secret Key") },
                                onClick = { menuExpanded = false; onCopySecret() },
                            )
                            DropdownMenuItem(
                                text = { Text("Show QR Code") },
                                onClick = { menuExpanded = false; onShowQr() },
                            )
                            DropdownMenuItem(
                                text = { Text("Edit") },
                                onClick = { menuExpanded = false; onEdit() },
                            )
                            DropdownMenuItem(
                                text = { Text("Delete", color = MaterialTheme.colorScheme.error) },
                                onClick = { menuExpanded = false; onDelete() },
                            )
                        }
                    }
                }

                // Code + countdown + copy
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val (first, second) = splitCode(code)
                    Text(
                        text = first,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 2.sp,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = second,
                        fontFamily = FontFamily.Monospace,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 2.sp,
                    )

                    // Countdown text — only visible in last 10 seconds
                    if (timeLeft <= 10) {
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "${timeLeft}s",
                            style = MaterialTheme.typography.labelMedium,
                            color = if (timeLeft <= 5) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                }

                // Next-code preview — only in the last 10s so the card
                // doesn't grow at rest. Faded to stay visually subordinate
                // to the current code.
                if (showNextCode && timeLeft <= 10 && nextCode.isNotEmpty()) {
                    val previewColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    Row(
                        modifier = Modifier.padding(top = 2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "next",
                            style = MaterialTheme.typography.labelSmall,
                            color = previewColor,
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        val (nextFirst, nextSecond) = splitCode(nextCode)
                        Text(
                            text = nextFirst,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            letterSpacing = 1.sp,
                            color = previewColor,
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = nextSecond,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            letterSpacing = 1.sp,
                            color = previewColor,
                        )
                    }
                }
            }
        }
    }
}

private fun splitCode(code: String): Pair<String, String> {
    val mid = (code.length + 1) / 2
    return code.take(mid) to code.drop(mid)
}
