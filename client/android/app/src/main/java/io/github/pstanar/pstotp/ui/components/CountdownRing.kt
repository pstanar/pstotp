package io.github.pstanar.pstotp.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/**
 * Circular countdown ring that depletes as the TOTP period expires.
 * Wraps content (typically a ServiceIcon) in the center.
 *
 * Matches the web app's CountdownRing component.
 */
@Composable
fun CountdownRing(
    period: Int,
    size: Dp = 44.dp,
    strokeWidth: Dp = 2.5.dp,
    content: @Composable () -> Unit,
) {
    var fraction by remember { mutableFloatStateOf(1f) }

    // Update fraction every 500ms
    LaunchedEffect(period) {
        while (true) {
            val now = System.currentTimeMillis() / 1000
            val elapsed = now % period
            fraction = 1f - (elapsed.toFloat() / period)
            delay(500)
        }
    }

    val animatedFraction by animateFloatAsState(
        targetValue = fraction,
        animationSpec = tween(durationMillis = 500, easing = LinearEasing),
        label = "countdown",
    )

    val ringColor = if (fraction <= 0.17f) { // ~5 seconds on 30s period
        MaterialTheme.colorScheme.error
    } else {
        MaterialTheme.colorScheme.primary
    }

    val trackColor = MaterialTheme.colorScheme.surfaceVariant

    Box(
        modifier = Modifier.size(size),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.size(size)) {
            val stroke = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)

            // Background track
            drawArc(
                color = trackColor,
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                style = stroke,
            )

            // Countdown arc
            drawArc(
                color = ringColor,
                startAngle = -90f,
                sweepAngle = 360f * animatedFraction,
                useCenter = false,
                style = stroke,
            )
        }

        content()
    }
}
