package io.github.pstanar.pstotp

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.LaunchedEffect
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
            authViewModel.onSyncComplete = {
                viewModel.reloadEntries()
                // Converge the icon library with server state on every sync
                // so edits from another device land here too. Last-write-wins
                // on conflicts per project policy.
                viewModel.refreshIconLibraryFromServer()
            }
            // Hand VaultViewModel the server-side api. Null in standalone mode
            // leaves the library purely local-first.
            viewModel.iconLibraryApi = authViewModel.iconLibraryApi
            val useSystemColors by viewModel.useSystemColors.collectAsStateWithLifecycle()
            PsTotpTheme(dynamicColor = useSystemColors) {
                val isSetUp by viewModel.isSetUp.collectAsStateWithLifecycle()

                val isUnlocked by viewModel.isUnlocked.collectAsStateWithLifecycle()

                // Register lifecycle observer for auto-lock
                if (lifecycleObserver == null) {
                    lifecycleObserver = AppLifecycleObserver(
                        onBackground = { /* timestamp recorded automatically */ },
                        onForeground = {
                            val duration = lifecycleObserver?.getBackgroundDurationMs() ?: 0
                            val timeout = viewModel.lockTimeoutMs.value
                            if (duration > timeout && viewModel.isUnlocked.value) {
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
                                viewModel.isUnlocked.value -> Routes.VAULT
                                else -> Routes.UNLOCK
                            }
                        }

                        // Auto-lock redirect. lock() clears the vault key
                        // but doesn't navigate; without this, the user
                        // returning from background after the inactivity
                        // timeout sees /vault rendering its empty-state
                        // ("Welcome to PsTotp") instead of being asked to
                        // unlock. Skip while still on /setup so the
                        // first-run flow isn't hijacked.
                        LaunchedEffect(isUnlocked, isSetUp) {
                            if (isSetUp == true && !isUnlocked &&
                                navController.currentDestination?.route != Routes.UNLOCK
                            ) {
                                navController.navigate(Routes.UNLOCK) {
                                    popUpTo(0) { inclusive = true }
                                    launchSingleTop = true
                                }
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
