package io.github.pstanar.pstotp

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.rememberNavController
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.nav.AppNavGraph
import io.github.pstanar.pstotp.ui.nav.Routes
import io.github.pstanar.pstotp.ui.theme.PsTotpTheme
import io.github.pstanar.pstotp.util.AppLifecycleObserver

class MainActivity : FragmentActivity() {

    private var lifecycleObserver: AppLifecycleObserver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            android.view.WindowManager.LayoutParams.FLAG_SECURE,
            android.view.WindowManager.LayoutParams.FLAG_SECURE,
        )
        enableEdgeToEdge()
        setContent {
            val viewModel: VaultViewModel = viewModel()
            val authViewModel: AuthViewModel = viewModel()
            viewModel.onSyncNeeded = { authViewModel.syncNow() }
            authViewModel.onSyncComplete = { viewModel.reloadEntries() }
            val useSystemColors by viewModel.useSystemColors.collectAsStateWithLifecycle()
            PsTotpTheme(dynamicColor = useSystemColors) {
                val isSetUp by viewModel.isSetUp.collectAsStateWithLifecycle()

                // Register lifecycle observer for auto-lock
                if (lifecycleObserver == null) {
                    lifecycleObserver = AppLifecycleObserver(
                        onBackground = { /* timestamp recorded automatically */ },
                        onForeground = {
                            val duration = lifecycleObserver?.getBackgroundDurationMs() ?: 0
                            val timeout = viewModel.lockTimeoutMs.value
                            if (duration > timeout && viewModel.isUnlocked) {
                                viewModel.lock()
                            }
                        },
                    )
                    ProcessLifecycleOwner.get().lifecycle.addObserver(lifecycleObserver!!)
                }

                when (isSetUp) {
                    null -> {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    }

                    else -> {
                        val navController = rememberNavController()
                        val startDestination = remember(isSetUp) {
                            when {
                                isSetUp != true -> Routes.SETUP
                                viewModel.isUnlocked -> Routes.VAULT
                                else -> Routes.UNLOCK
                            }
                        }
                        AppNavGraph(
                            navController = navController,
                            startDestination = startDestination,
                            viewModel = viewModel,
                            authViewModel = authViewModel,
                        )
                    }
                }
            }
        }
    }
}
