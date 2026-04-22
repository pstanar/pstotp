package io.github.pstanar.pstotp.ui.nav

import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.ui.AuthViewModel
import io.github.pstanar.pstotp.ui.VaultViewModel
import io.github.pstanar.pstotp.ui.screens.AddAccountScreen
import io.github.pstanar.pstotp.ui.screens.AuditScreen
import io.github.pstanar.pstotp.ui.screens.ChangePasswordScreen
import io.github.pstanar.pstotp.ui.screens.ConnectServerScreen
import io.github.pstanar.pstotp.ui.screens.DevicesScreen
import io.github.pstanar.pstotp.ui.screens.EditAccountScreen
import io.github.pstanar.pstotp.ui.screens.PasskeyManagementScreen
import io.github.pstanar.pstotp.ui.screens.RecoveryScreen
import io.github.pstanar.pstotp.ui.screens.RegenerateCodesScreen
import io.github.pstanar.pstotp.ui.screens.RegisterScreen
import io.github.pstanar.pstotp.ui.screens.SettingsScreen
import io.github.pstanar.pstotp.ui.screens.SetupScreen
import io.github.pstanar.pstotp.ui.screens.UnlockScreen
import io.github.pstanar.pstotp.ui.screens.VaultScreen

object Routes {
    const val SETUP = "setup"
    const val UNLOCK = "unlock"
    const val VAULT = "vault"
    const val ADD_ACCOUNT = "add_account"
    const val EDIT_ACCOUNT = "edit_account/{entryId}"
    const val SETTINGS = "settings"
    const val CONNECT_SERVER = "connect_server"
    const val REGISTER = "register/{serverUrl}"
    const val DEVICES = "devices"
    const val CHANGE_PASSWORD = "change_password"
    const val RECOVERY = "recovery/{serverUrl}"
    const val AUDIT_LOG = "audit_log"
    const val REGENERATE_CODES = "regenerate_codes"
    const val PASSKEYS = "passkeys"

    fun editAccount(entryId: String) = "edit_account/$entryId"
    fun register(serverUrl: String) = "register/${java.net.URLEncoder.encode(serverUrl, "UTF-8")}"
    fun recovery(serverUrl: String) = "recovery/${java.net.URLEncoder.encode(serverUrl, "UTF-8")}"
}

@Composable
fun AppNavGraph(
    navController: NavHostController,
    startDestination: String,
    viewModel: VaultViewModel,
    authViewModel: AuthViewModel,
) {
    NavHost(navController = navController, startDestination = startDestination) {

        composable(Routes.SETUP) {
            SetupScreen(
                viewModel = viewModel,
                onSetupComplete = {
                    navController.navigate(Routes.VAULT) {
                        popUpTo(Routes.SETUP) { inclusive = true }
                    }
                },
            )
        }

        composable(Routes.UNLOCK) {
            UnlockScreen(
                viewModel = viewModel,
                authViewModel = authViewModel,
                onUnlocked = {
                    navController.navigate(Routes.VAULT) {
                        popUpTo(Routes.UNLOCK) { inclusive = true }
                    }
                },
            )
        }

        composable(Routes.VAULT) {
            VaultScreen(
                viewModel = viewModel,
                onAddAccount = { navController.navigate(Routes.ADD_ACCOUNT) },
                onEditAccount = { entryId -> navController.navigate(Routes.editAccount(entryId)) },
                onSettings = { navController.navigate(Routes.SETTINGS) },
                onLock = {
                    viewModel.lock()
                    navController.navigate(Routes.UNLOCK) {
                        popUpTo(Routes.VAULT) { inclusive = true }
                    }
                },
            )
        }

        composable(Routes.ADD_ACCOUNT) {
            AddAccountScreen(
                viewModel = viewModel,
                onAccountAdded = { navController.popBackStack() },
                onCancel = { navController.popBackStack() },
            )
        }

        composable(Routes.EDIT_ACCOUNT) { backStackEntry ->
            val entryId = backStackEntry.arguments?.getString("entryId") ?: return@composable
            EditAccountScreen(
                viewModel = viewModel,
                entryId = entryId,
                onSaved = { navController.popBackStack() },
                onCancel = { navController.popBackStack() },
            )
        }

        composable(Routes.SETTINGS) {
            SettingsScreen(
                onBack = { navController.popBackStack() },
                viewModel = viewModel,
                authViewModel = authViewModel,
                onConnectServer = { navController.navigate(Routes.CONNECT_SERVER) },
                onDevices = { navController.navigate(Routes.DEVICES) },
                onChangePassword = { navController.navigate(Routes.CHANGE_PASSWORD) },
                onAuditLog = { navController.navigate(Routes.AUDIT_LOG) },
                onRegenerateCodes = { navController.navigate(Routes.REGENERATE_CODES) },
                onPasskeys = { navController.navigate(Routes.PASSKEYS) },
            )
        }

        composable(Routes.CONNECT_SERVER) {
            ConnectServerScreen(
                authViewModel = authViewModel,
                vaultViewModel = viewModel,
                onConnected = { navController.popBackStack() },
                onRegister = { serverUrl -> navController.navigate(Routes.register(serverUrl)) },
                onRecover = { serverUrl -> navController.navigate(Routes.recovery(serverUrl)) },
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.REGISTER) { backStackEntry ->
            val serverUrl = backStackEntry.arguments?.getString("serverUrl")
                ?.let { java.net.URLDecoder.decode(it, "UTF-8") } ?: return@composable
            val scope = rememberCoroutineScope()
            RegisterScreen(
                authViewModel = authViewModel,
                serverUrl = serverUrl,
                onRegistered = { vaultKey ->
                    scope.launch {
                        try {
                            viewModel.unlockWithKey(vaultKey)
                            authViewModel.syncNow()
                            navController.navigate(Routes.VAULT) {
                                popUpTo(Routes.CONNECT_SERVER) { inclusive = true }
                            }
                        } catch (_: Exception) {
                            // Error surfaced via viewModel.error (shown on
                            // whatever screen navigates next).
                        }
                    }
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.DEVICES) {
            DevicesScreen(
                authViewModel = authViewModel,
                vaultViewModel = viewModel,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.RECOVERY) { backStackEntry ->
            val serverUrl = backStackEntry.arguments?.getString("serverUrl")
                ?.let { java.net.URLDecoder.decode(it, "UTF-8") } ?: return@composable
            val scope = rememberCoroutineScope()
            RecoveryScreen(
                authViewModel = authViewModel,
                serverUrl = serverUrl,
                onRecovered = { vaultKey ->
                    scope.launch {
                        try {
                            viewModel.unlockWithKey(vaultKey)
                            authViewModel.syncNow()
                            navController.navigate(Routes.VAULT) {
                                popUpTo(Routes.CONNECT_SERVER) { inclusive = true }
                            }
                        } catch (_: Exception) {
                            // Error surfaced via viewModel.error.
                        }
                    }
                },
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.CHANGE_PASSWORD) {
            ChangePasswordScreen(
                authViewModel = authViewModel,
                vaultViewModel = viewModel,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.AUDIT_LOG) {
            AuditScreen(
                authViewModel = authViewModel,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.REGENERATE_CODES) {
            RegenerateCodesScreen(
                authViewModel = authViewModel,
                vaultViewModel = viewModel,
                onBack = { navController.popBackStack() },
            )
        }

        composable(Routes.PASSKEYS) {
            PasskeyManagementScreen(
                authViewModel = authViewModel,
                onBack = { navController.popBackStack() },
            )
        }
    }
}
