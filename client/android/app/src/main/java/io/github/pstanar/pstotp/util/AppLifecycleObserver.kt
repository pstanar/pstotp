package io.github.pstanar.pstotp.util

import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Observes app lifecycle to detect when the app goes to background.
 * Calls onBackground when the app is no longer visible.
 * Calls onForeground when the app becomes visible again.
 */
class AppLifecycleObserver(
    private val onBackground: () -> Unit,
    private val onForeground: () -> Unit = {},
) : DefaultLifecycleObserver {

    private var backgroundTimestamp: Long = 0L

    override fun onStop(owner: LifecycleOwner) {
        backgroundTimestamp = System.currentTimeMillis()
        onBackground()
    }

    override fun onStart(owner: LifecycleOwner) {
        onForeground()
    }

    fun getBackgroundDurationMs(): Long {
        return if (backgroundTimestamp > 0) {
            System.currentTimeMillis() - backgroundTimestamp
        } else 0L
    }
}
