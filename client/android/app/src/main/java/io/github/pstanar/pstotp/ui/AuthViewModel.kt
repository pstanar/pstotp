package io.github.pstanar.pstotp.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.api.ApiClient
import io.github.pstanar.pstotp.core.api.AuthApi
import io.github.pstanar.pstotp.core.api.DevicesApi
import io.github.pstanar.pstotp.core.api.VaultApi
import io.github.pstanar.pstotp.core.db.AppDatabase
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.core.repository.VaultRepository
import io.github.pstanar.pstotp.core.api.WebAuthnApi
import io.github.pstanar.pstotp.core.model.api.LoginEnvelopes
import io.github.pstanar.pstotp.core.sync.AuthService
import io.github.pstanar.pstotp.core.sync.LoginResult
import io.github.pstanar.pstotp.core.sync.PasskeyLoginResult
import io.github.pstanar.pstotp.core.sync.SyncResult
import io.github.pstanar.pstotp.core.sync.SyncService

/**
 * ViewModel for server authentication and sync state.
 * Separate from VaultViewModel to keep concerns isolated.
 */
class AuthViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val repository = VaultRepository(db)
    val apiClient = ApiClient("").apply {
        onTokensRefreshed = { access, refresh ->
            // commit() instead of apply() — synchronous write ensures tokens survive a crash
            io.github.pstanar.pstotp.core.crypto.SecureStore.getInstance(application).edit()
                .putString(io.github.pstanar.pstotp.core.crypto.SecureStore.ACCESS_TOKEN, access)
                .putString(io.github.pstanar.pstotp.core.crypto.SecureStore.REFRESH_TOKEN, refresh)
                .commit()
        }
    }
    private val authApi = AuthApi(apiClient)
    private val vaultApi = VaultApi(apiClient)
    val authService = AuthService(application, db, apiClient, authApi)
    val devicesApi = DevicesApi(apiClient)
    val syncService = SyncService(db, apiClient, vaultApi, repository)

    private val _connectionState = MutableStateFlow(ConnectionState.Disconnected)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _syncState = MutableStateFlow<SyncState>(SyncState.Idle)
    val syncState: StateFlow<SyncState> = _syncState.asStateFlow()

    private val _serverUrl = MutableStateFlow("")
    val serverUrl: StateFlow<String> = _serverUrl.asStateFlow()

    private val _email = MutableStateFlow("")
    val email: StateFlow<String> = _email.asStateFlow()

    private val _lastSyncAt = MutableStateFlow<String?>(null)
    val lastSyncAt: StateFlow<String?> = _lastSyncAt.asStateFlow()

    /** Set by MainActivity to reload vault entries after sync. */
    var onSyncComplete: (() -> Unit)? = null

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        viewModelScope.launch {
            if (authService.isConnected()) {
                authService.restoreSession()
                _connectionState.value = ConnectionState.Connected
                _serverUrl.value = authService.getServerUrl() ?: ""
                _email.value = repository.getSetting(SettingsKeys.EMAIL) ?: ""
                _lastSyncAt.value = repository.getSetting(SettingsKeys.LAST_SYNC_AT)
            }
        }
    }

    fun connect(
        serverUrl: String,
        email: String,
        password: String,
        vaultKey: ByteArray,
        unlockVault: suspend (serverVaultKey: ByteArray) -> Unit,
        onSuccess: () -> Unit,
        onComplete: () -> Unit = {},
    ) {
        _connectionState.value = ConnectionState.Connecting
        _error.value = null

        viewModelScope.launch {
            try {
                when (val result = authService.login(serverUrl, email, password, vaultKey)) {
                    is LoginResult.Approved -> {
                        if (tryUnlockThenConnect(result.serverVaultKey, unlockVault, serverUrl, email)) {
                            onSuccess()
                        }
                    }
                    is LoginResult.PendingApproval -> {
                        _connectionState.value = ConnectionState.PendingApproval
                        _error.value = "Device is pending approval from an existing device"
                    }
                    is LoginResult.Error -> {
                        _connectionState.value = ConnectionState.Error
                        _error.value = result.message
                    }
                }
            } catch (e: Exception) {
                _connectionState.value = ConnectionState.Error
                _error.value = friendlyError(e, "Connection failed")
            } finally {
                onComplete()
            }
        }
    }

    /**
     * Run the caller-supplied vault unlock and only flip to Connected if it
     * succeeds. Prevents the "auth says connected but vault is empty / wrong
     * key" split-brain state that has bitten us several times. Returns true
     * when the session is now fully established.
     */
    private suspend fun tryUnlockThenConnect(
        serverVaultKey: ByteArray,
        unlockVault: suspend (ByteArray) -> Unit,
        serverUrl: String,
        email: String,
    ): Boolean {
        try {
            unlockVault(serverVaultKey)
        } catch (e: Exception) {
            _connectionState.value = ConnectionState.Error
            _error.value = friendlyError(e, "Vault unlock failed")
            // Don't leave a dangling server session behind when the key we
            // got back doesn't decrypt the vault.
            runCatching { authService.logout() }
            return false
        }
        _connectionState.value = ConnectionState.Connected
        _serverUrl.value = serverUrl
        _email.value = email
        return true
    }

    fun disconnect() {
        viewModelScope.launch {
            authService.logout()
            _connectionState.value = ConnectionState.Disconnected
            _serverUrl.value = ""
            _lastSyncAt.value = null
            _error.value = null
        }
    }

    // --- Passkey login ---

    val webAuthnApi = WebAuthnApi(apiClient)

    fun passkeyLogin(
        serverUrl: String,
        email: String,
        ceremonyId: String,
        assertionResponseJson: String,
        unlockVault: suspend (serverVaultKey: ByteArray) -> Unit,
        onSuccess: () -> Unit,
        onNeedPassword: (envelopes: LoginEnvelopes, userId: String, deviceId: String) -> Unit,
        onComplete: () -> Unit = {},
    ) {
        _connectionState.value = ConnectionState.Connecting
        _error.value = null

        viewModelScope.launch {
            try {
                when (val result = authService.passkeyLogin(serverUrl, email, assertionResponseJson, ceremonyId)) {
                    is PasskeyLoginResult.Approved -> {
                        if (tryUnlockThenConnect(result.serverVaultKey, unlockVault, serverUrl, email)) {
                            onSuccess()
                        }
                    }
                    is PasskeyLoginResult.NeedPassword -> {
                        _connectionState.value = ConnectionState.Disconnected
                        onNeedPassword(result.envelopes, result.userId, result.deviceId)
                    }
                    is PasskeyLoginResult.PendingApproval -> {
                        _connectionState.value = ConnectionState.PendingApproval
                        _error.value = "Device is pending approval from an existing device"
                    }
                    is PasskeyLoginResult.Error -> {
                        _connectionState.value = ConnectionState.Error
                        _error.value = result.message
                    }
                }
            } catch (e: Exception) {
                _connectionState.value = ConnectionState.Error
                _error.value = friendlyError(e, "Passkey login failed")
            } finally {
                onComplete()
            }
        }
    }

    fun passkeyUnlockWithPassword(
        serverUrl: String,
        email: String,
        password: String,
        envelopes: LoginEnvelopes,
        userId: String,
        deviceId: String,
        unlockVault: suspend (serverVaultKey: ByteArray) -> Unit,
        onSuccess: () -> Unit,
        onComplete: () -> Unit = {},
    ) {
        _connectionState.value = ConnectionState.Connecting
        _error.value = null

        viewModelScope.launch {
            try {
                when (val result = authService.passkeyUnlockWithPassword(
                    serverUrl, email, password, envelopes, userId, deviceId,
                )) {
                    is PasskeyLoginResult.Approved -> {
                        if (tryUnlockThenConnect(result.serverVaultKey, unlockVault, serverUrl, email)) {
                            onSuccess()
                        }
                    }
                    is PasskeyLoginResult.Error -> {
                        _connectionState.value = ConnectionState.Error
                        _error.value = result.message
                    }
                    else -> {
                        _connectionState.value = ConnectionState.Error
                        _error.value = "Unexpected result"
                    }
                }
            } catch (e: Exception) {
                _connectionState.value = ConnectionState.Error
                _error.value = friendlyError(e, "Password unlock failed")
            } finally {
                onComplete()
            }
        }
    }

    fun syncNow(onComplete: (() -> Unit)? = null) {
        if (_syncState.value == SyncState.Syncing) return // Already syncing
        _syncState.value = SyncState.Syncing
        viewModelScope.launch {
            when (val result = syncService.fullSync()) {
                is SyncResult.Success -> {
                    _syncState.value = SyncState.Idle
                    _lastSyncAt.value = repository.getSetting(SettingsKeys.LAST_SYNC_AT)
                    onSyncComplete?.invoke()
                    onComplete?.invoke()
                }
                is SyncResult.Error -> {
                    _syncState.value = SyncState.Error(result.message)
                }
                is SyncResult.SessionExpired -> {
                    _connectionState.value = ConnectionState.Disconnected
                    _syncState.value = SyncState.Error("Session expired — please reconnect")
                }
                is SyncResult.NotConnected -> {
                    _syncState.value = SyncState.Idle
                }
            }
        }
    }

    fun clearError() {
        _error.value = null
    }

    fun setError(message: String) {
        _error.value = message
    }

    /** Translate common network exceptions into user-facing messages. */
    private fun friendlyError(e: Exception, fallback: String): String = when (e) {
        is java.net.UnknownHostException -> "Server not found. Check the URL and your connection."
        is java.net.SocketTimeoutException -> "Server did not respond in time."
        is java.net.ConnectException -> "Could not reach the server."
        is javax.net.ssl.SSLException -> "Secure connection failed (TLS/certificate issue)."
        else -> e.message?.takeIf { it.isNotBlank() } ?: fallback
    }

    // --- Registration ---

    fun registerBegin(serverUrl: String, email: String, onResult: (String?, Boolean, String?) -> Unit) {
        viewModelScope.launch {
            try {
                val result = authService.registerBegin(serverUrl, email)
                onResult(result.registrationSessionId, result.emailVerificationRequired, result.verificationCode)
            } catch (e: Exception) {
                _error.value = e.message ?: "Registration failed"
                onResult(null, false, null)
            }
        }
    }

    fun verifyEmail(sessionId: String, code: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            try {
                onResult(authService.verifyEmail(sessionId, code))
            } catch (e: Exception) {
                _error.value = e.message ?: "Verification failed"
                onResult(false)
            }
        }
    }


    // --- Recovery ---

    fun redeemRecoveryCode(
        serverUrl: String, email: String, password: String, code: String,
        onResult: (sessionId: String?, releaseTime: String?, status: String?) -> Unit,
    ) {
        viewModelScope.launch {
            try {
                val redeemResult = authService.redeemRecoveryCode(serverUrl, email, password, code)
                val material = authService.getRecoveryMaterial(serverUrl, redeemResult.recoverySessionId)
                onResult(redeemResult.recoverySessionId, material.releaseEarliestAt, material.status)
            } catch (e: Exception) {
                _error.value = e.message ?: "Recovery failed"
                onResult(null, null, null)
            }
        }
    }

    fun checkRecoveryMaterial(
        serverUrl: String, sessionId: String,
        onResult: (status: String?, releaseTime: String?) -> Unit,
    ) {
        viewModelScope.launch {
            try {
                val material = authService.getRecoveryMaterial(serverUrl, sessionId)
                onResult(material.status, material.releaseEarliestAt)
            } catch (e: Exception) {
                _error.value = e.message ?: "Check failed"
                onResult(null, null)
            }
        }
    }

    private val _recoveryCodes = MutableStateFlow<List<String>>(emptyList())
    val recoveryCodes: StateFlow<List<String>> = _recoveryCodes.asStateFlow()

    fun completeRecovery(
        serverUrl: String, email: String, password: String,
        sessionId: String, envelope: io.github.pstanar.pstotp.core.model.api.Envelope,
        replacementDeviceId: String,
        onApproved: (vaultKey: ByteArray) -> Unit,
    ) {
        viewModelScope.launch {
            try {
                val result = authService.completeRecovery(
                    serverUrl, email, password, sessionId, envelope, replacementDeviceId,
                )
                _recoveryCodes.value = result.recoveryCodes
                _connectionState.value = ConnectionState.Connected
                _serverUrl.value = serverUrl
                _email.value = email
                // See comment on register(): the recovered vault key must
                // be adopted by VaultViewModel via unlockWithKey or any
                // subsequent sync/decrypt silently produces empty entries.
                onApproved(result.vaultKey)
            } catch (e: Exception) {
                _error.value = e.message ?: "Recovery failed"
            }
        }
    }
}

enum class ConnectionState { Disconnected, Connecting, Connected, PendingApproval, Error }

sealed class SyncState {
    data object Idle : SyncState()
    data object Syncing : SyncState()
    data class Error(val message: String) : SyncState()
}
