package io.github.pstanar.pstotp.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import io.github.pstanar.pstotp.core.api.IconLibraryApi
import io.github.pstanar.pstotp.core.crypto.KeystoreHelper
import io.github.pstanar.pstotp.core.db.AppDatabase
import io.github.pstanar.pstotp.core.db.EntryUsageEntity
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.core.model.ImportAction
import io.github.pstanar.pstotp.core.model.ImportCandidate
import io.github.pstanar.pstotp.core.model.LayoutMode
import io.github.pstanar.pstotp.core.model.LibraryIcon
import io.github.pstanar.pstotp.core.model.LockTimeout
import io.github.pstanar.pstotp.core.model.SortMode
import io.github.pstanar.pstotp.core.model.VaultEntry
import io.github.pstanar.pstotp.core.model.VaultEntryPlaintext
import io.github.pstanar.pstotp.core.model.VaultExport
import io.github.pstanar.pstotp.core.util.IconFetch
import javax.crypto.Cipher
import io.github.pstanar.pstotp.core.repository.IconLibraryRepository
import io.github.pstanar.pstotp.core.repository.VaultKeyMismatchException
import io.github.pstanar.pstotp.core.repository.VaultRepository

/**
 * Main ViewModel — holds vault state, handles setup/unlock/CRUD.
 * Like useAuthStore + useVaultStore combined in the web app.
 *
 * StateFlow is the Kotlin equivalent of React useState — UI observes it
 * and re-renders when it changes.
 */
class VaultViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = VaultRepository(AppDatabase.getInstance(application))
    private val iconLibraryRepo = IconLibraryRepository(AppDatabase.getInstance(application))

    /**
     * Optional IconLibraryApi — set by AuthViewModel once the session is
     * connected. Null in standalone mode (local-first library still works,
     * just no server sync). Mutations fall back to local-only when null.
     */
    var iconLibraryApi: IconLibraryApi? = null

    private val _isSetUp = MutableStateFlow<Boolean?>(null) // null = loading
    val isSetUp: StateFlow<Boolean?> = _isSetUp.asStateFlow()

    private val _useSystemColors = MutableStateFlow(true)
    val useSystemColors: StateFlow<Boolean> = _useSystemColors.asStateFlow()

    private val _showNextCode = MutableStateFlow(false)
    val showNextCode: StateFlow<Boolean> = _showNextCode.asStateFlow()

    private val _sortMode = MutableStateFlow(SortMode.MANUAL)
    val sortMode: StateFlow<SortMode> = _sortMode.asStateFlow()

    /** When true, flip the natural direction of the current sort mode. */
    private val _sortReversed = MutableStateFlow(false)
    val sortReversed: StateFlow<Boolean> = _sortReversed.asStateFlow()

    private val _layoutMode = MutableStateFlow(LayoutMode.LIST)
    val layoutMode: StateFlow<LayoutMode> = _layoutMode.asStateFlow()

    /** Per-entry usage metadata loaded from the local db (local-only, not synced). */
    private val _usage = MutableStateFlow<Map<String, EntryUsageEntity>>(emptyMap())
    val usage: StateFlow<Map<String, EntryUsageEntity>> = _usage.asStateFlow()

    private val _vaultKey = MutableStateFlow<ByteArray?>(null)
    val isUnlocked: Boolean get() = _vaultKey.value != null

    fun getVaultKey(): ByteArray? = _vaultKey.value

    private val _lockTimeoutMs = MutableStateFlow(SettingsKeys.DEFAULT_LOCK_TIMEOUT_MS)
    val lockTimeoutMs: StateFlow<Long> = _lockTimeoutMs.asStateFlow()

    private val _entries = MutableStateFlow<List<VaultEntry>>(emptyList())
    val entries: StateFlow<List<VaultEntry>> = _entries.asStateFlow()

    private val _isBiometricEnabled = MutableStateFlow(false)
    val isBiometricEnabled: StateFlow<Boolean> = _isBiometricEnabled.asStateFlow()

    private val _libraryIcons = MutableStateFlow<List<LibraryIcon>>(emptyList())
    val libraryIcons: StateFlow<List<LibraryIcon>> = _libraryIcons.asStateFlow()

    /** Set by MainActivity to trigger sync after CRUD operations in connected mode. */
    var onSyncNeeded: (() -> Unit)? = null

    /**
     * Reload entries from the database (call after sync pulls new data).
     *
     * Decrypt failures here almost always mean the server pushed entries
     * encrypted with a different vault key — exactly the silent-drop class
     * of bug we've been chasing. Surface it via _error instead of swallowing.
     */
    fun reloadEntries() {
        val key = _vaultKey.value ?: return
        viewModelScope.launch {
            try {
                _entries.value = repository.getAllEntries(key)
            } catch (e: VaultKeyMismatchException) {
                _error.value =
                    "Vault key mismatch: ${e.failed} of ${e.total} entries could not be decrypted."
            } catch (e: Exception) {
                _error.value = "Failed to reload vault: ${e.message}"
            }
        }
    }

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        viewModelScope.launch {
            _isSetUp.value = repository.isSetUp()
            _useSystemColors.value = repository.getSetting(SettingsKeys.USE_SYSTEM_COLORS) != "false"
            _showNextCode.value = repository.getSetting(SettingsKeys.SHOW_NEXT_CODE) == "true"
            _sortMode.value = SortMode.fromStorageKey(repository.getSetting(SettingsKeys.SORT_MODE))
            _sortReversed.value = repository.getSetting(SettingsKeys.SORT_REVERSED) == "true"
            _layoutMode.value = LayoutMode.fromStorageKey(repository.getSetting(SettingsKeys.LAYOUT_MODE))
            _isBiometricEnabled.value = repository.isBiometricEnabled()
            cachedBiometricIv = repository.getBiometricIv()
            _lockTimeoutMs.value = repository.getSetting(SettingsKeys.LOCK_TIMEOUT_MS)?.toLongOrNull()
                ?: SettingsKeys.DEFAULT_LOCK_TIMEOUT_MS
            _usage.value = repository.getAllUsage().associateBy { it.entryId }
        }
    }

    fun setUseSystemColors(value: Boolean) {
        _useSystemColors.value = value
        viewModelScope.launch {
            repository.setSetting(SettingsKeys.USE_SYSTEM_COLORS, value.toString())
        }
    }

    fun setShowNextCode(value: Boolean) {
        _showNextCode.value = value
        viewModelScope.launch {
            repository.setSetting(SettingsKeys.SHOW_NEXT_CODE, value.toString())
        }
    }

    fun setSortMode(mode: SortMode) {
        _sortMode.value = mode
        viewModelScope.launch {
            repository.setSetting(SettingsKeys.SORT_MODE, mode.storageKey)
        }
    }

    fun setSortReversed(reversed: Boolean) {
        _sortReversed.value = reversed
        viewModelScope.launch {
            repository.setSetting(SettingsKeys.SORT_REVERSED, reversed.toString())
        }
    }

    fun setLayoutMode(mode: LayoutMode) {
        _layoutMode.value = mode
        viewModelScope.launch {
            repository.setSetting(SettingsKeys.LAYOUT_MODE, mode.storageKey)
        }
    }

    fun setLockTimeout(timeout: LockTimeout) {
        _lockTimeoutMs.value = timeout.millis
        viewModelScope.launch {
            repository.setSetting(SettingsKeys.LOCK_TIMEOUT_MS, timeout.millis.toString())
        }
    }

    fun recordEntryUse(entryId: String) {
        viewModelScope.launch {
            repository.recordEntryUse(entryId)
            _usage.value = repository.getAllUsage().associateBy { it.entryId }
        }
    }

    // --- Icon library ---
    //
    // Local-first: all mutations write to local settings immediately and —
    // if we're connected — push through to the server. Standalone callers
    // just don't wire `iconLibraryApi`; the library remains device-local.
    // Last-write-wins on concurrent edits, matching the web client.

    /**
     * Reconcile the local library with the server. Offline edits go up
     * first — otherwise pullFromServer would overwrite the local
     * ciphertext and clear the dirty flag before the push ever ran,
     * silently dropping the user's offline changes. A 409 during the
     * push is resolved inside pushCiphertext via refetch-and-retry
     * (last-write-wins per project policy).
     */
    fun refreshIconLibraryFromServer() {
        val key = _vaultKey.value ?: return
        val api = iconLibraryApi ?: return
        viewModelScope.launch {
            runCatching {
                iconLibraryRepo.pushIfDirty(api)
                val blob = iconLibraryRepo.pullFromServer(key, api)
                _libraryIcons.value = blob.icons
            }
        }
    }

    fun addLibraryIcon(label: String, dataUrl: String, onError: (String) -> Unit = {}) {
        val key = _vaultKey.value ?: return
        viewModelScope.launch {
            try {
                if (_libraryIcons.value.size >= IconLibraryRepository.MAX_ICONS) {
                    onError("Icon library is full (${IconLibraryRepository.MAX_ICONS} max).")
                    return@launch
                }
                val next = _libraryIcons.value + LibraryIcon(
                    id = IconLibraryRepository.newIconId(),
                    label = label.ifBlank { "Icon" },
                    data = dataUrl,
                    createdAt = java.time.Instant.now().toString(),
                )
                val blob = iconLibraryRepo.save(key, next, iconLibraryApi)
                _libraryIcons.value = blob.icons
            } catch (e: Exception) {
                onError(e.message ?: "Could not save icon")
            }
        }
    }

    fun removeLibraryIcon(id: String, onError: (String) -> Unit = {}) {
        val key = _vaultKey.value ?: return
        viewModelScope.launch {
            try {
                val next = _libraryIcons.value.filterNot { it.id == id }
                val blob = iconLibraryRepo.save(key, next, iconLibraryApi)
                _libraryIcons.value = blob.icons
            } catch (e: Exception) {
                onError(e.message ?: "Could not remove icon")
            }
        }
    }

    fun renameLibraryIcon(id: String, label: String, onError: (String) -> Unit = {}) {
        val key = _vaultKey.value ?: return
        viewModelScope.launch {
            try {
                val next = _libraryIcons.value.map {
                    if (it.id == id) it.copy(label = label.ifBlank { it.label }) else it
                }
                val blob = iconLibraryRepo.save(key, next, iconLibraryApi)
                _libraryIcons.value = blob.icons
            } catch (e: Exception) {
                onError(e.message ?: "Could not rename icon")
            }
        }
    }

    fun setupPassword(password: String, onComplete: () -> Unit) {
        viewModelScope.launch {
            try {
                val vaultKey = repository.setupPassword(password)
                _vaultKey.value = vaultKey
                _entries.value = emptyList()
                _isSetUp.value = true
                onComplete()
            } catch (e: Exception) {
                _error.value = "Setup failed: ${e.message}"
            }
        }
    }

    /**
     * Shared tail for every unlock path. Decrypts entries BEFORE touching
     * _vaultKey / _entries so a wrong-key failure (surfaced as
     * VaultKeyMismatchException from repository.getAllEntries) doesn't leave
     * the UI in a "unlocked with no entries" state. On any exception the
     * error is set and state is untouched.
     */
    private suspend fun completeUnlock(vaultKey: ByteArray) {
        val entries = repository.getAllEntries(vaultKey)
        _vaultKey.value = vaultKey
        _entries.value = entries
        _error.value = null
        // Warm up the icon library from local storage so the picker is
        // populated without waiting on the network. Server pull is opt-in
        // via refreshIconLibraryFromServer() once connected.
        _libraryIcons.value = iconLibraryRepo.loadLocal(vaultKey).icons
    }

    fun unlock(password: String, onSuccess: () -> Unit, onComplete: () -> Unit = {}) {
        viewModelScope.launch {
            try {
                val vaultKey = repository.unlockVault(password)
                if (vaultKey == null) {
                    _error.value = "Incorrect password"
                    return@launch
                }
                completeUnlock(vaultKey)
                onSuccess()
            } catch (e: Exception) {
                _error.value = "Unlock failed: ${e.message}"
            } finally {
                onComplete()
            }
        }
    }

    fun lock() {
        _vaultKey.value?.fill(0) // Zero out vault key
        _vaultKey.value = null
        _entries.value = emptyList()
        _libraryIcons.value = emptyList()
    }

    /**
     * Unlock the vault with a key obtained out-of-band (server response from
     * a password/passkey login, recovery, etc.). Suspending + throwing on
     * failure so AuthViewModel can gate the "Connected" transition on actual
     * successful decryption — see AuthViewModel.tryUnlockThenConnect.
     */
    suspend fun unlockWithKey(vaultKey: ByteArray) {
        try {
            completeUnlock(vaultKey)
        } catch (e: VaultKeyMismatchException) {
            _error.value =
                "Vault key mismatch: ${e.failed} of ${e.total} entries could not be decrypted."
            throw e
        } catch (e: Exception) {
            _error.value = "Unlock failed: ${e.message}"
            throw e
        }
    }

    // --- Biometric ---

    private var cachedBiometricIv: ByteArray? = null

    /** Pre-load biometric IV so we don't need runBlocking later. */
    fun preloadBiometricIv() {
        viewModelScope.launch {
            cachedBiometricIv = repository.getBiometricIv()
        }
    }

    /** Get the decrypt cipher for biometric unlock. Returns null if not enrolled. */
    fun getBiometricDecryptCipher(): Cipher? {
        return try {
            val iv = cachedBiometricIv ?: return null
            KeystoreHelper.getDecryptCipher(iv)
        } catch (_: Exception) {
            null
        }
    }

    /** Complete biometric unlock using the authenticated cipher from BiometricPrompt. */
    fun unlockWithBiometric(
        cipher: Cipher,
        onSuccess: () -> Unit,
        onComplete: () -> Unit = {},
    ) {
        viewModelScope.launch {
            try {
                val vaultKey = repository.unlockWithBiometric(cipher)
                if (vaultKey == null) {
                    _error.value = "Biometric unlock failed"
                    return@launch
                }
                completeUnlock(vaultKey)
                onSuccess()
            } catch (e: Exception) {
                _error.value = "Biometric unlock failed: ${e.message}"
            } finally {
                onComplete()
            }
        }
    }

    /** Enable biometric: generate Keystore key, prompt for encrypt, store wrapped vault key. */
    fun getEnableBiometricCipher(): Cipher? {
        return try {
            KeystoreHelper.generateKey()
            KeystoreHelper.getEncryptCipher()
        } catch (e: Exception) {
            _error.value = "Failed to set up biometric key: ${e.message}"
            null
        }
    }

    /** Store the vault key wrapped by the authenticated encrypt cipher. */
    fun completeBiometricEnrollment(cipher: Cipher) {
        val key = _vaultKey.value
        if (key == null) {
            _error.value = "Vault is locked"
            return
        }
        viewModelScope.launch {
            try {
                repository.storeBiometricKey(cipher, key)
                cachedBiometricIv = repository.getBiometricIv()
                _isBiometricEnabled.value = true
            } catch (e: Exception) {
                _error.value = "Failed to enable biometric: ${e.message}"
            }
        }
    }

    fun disableBiometric() {
        viewModelScope.launch {
            repository.disableBiometric()
            cachedBiometricIv = null
            _isBiometricEnabled.value = false
        }
    }

    fun addEntry(plaintext: VaultEntryPlaintext, onComplete: () -> Unit) {
        val key = _vaultKey.value
        if (key == null) {
            _error.value = "Vault is locked"
            return
        }
        viewModelScope.launch {
            try {
                val entry = repository.addEntry(key, plaintext)
                _entries.value = _entries.value + entry
                onComplete()
                onSyncNeeded?.invoke()
            } catch (e: Exception) {
                _error.value = "Failed to add entry: ${e.message}"
            }
        }
    }

    fun updateEntry(entry: VaultEntry, onComplete: () -> Unit) {
        val key = _vaultKey.value
        if (key == null) {
            _error.value = "Vault is locked"
            return
        }
        viewModelScope.launch {
            try {
                repository.updateEntry(key, entry)
                _entries.value = _entries.value.map { if (it.id == entry.id) entry else it }
                onComplete()
                onSyncNeeded?.invoke()
            } catch (e: Exception) {
                _error.value = "Failed to update entry: ${e.message}"
            }
        }
    }

    fun deleteEntry(id: String, onComplete: (() -> Unit)? = null) {
        viewModelScope.launch {
            try {
                repository.deleteEntry(id)
                _entries.value = _entries.value.filter { it.id != id }
                onSyncNeeded?.invoke()
            } catch (e: Exception) {
                _error.value = "Failed to delete entry: ${e.message}"
            } finally {
                onComplete?.invoke()
            }
        }
    }

    fun reorderEntries(orderedIds: List<String>) {
        // Build a position map from the ordered IDs, then sort the FULL entry list
        // to avoid dropping entries that are hidden by search filtering.
        val positionMap = orderedIds.withIndex().associate { (index, id) -> id to index }
        _entries.value = _entries.value.sortedBy { positionMap[it.id] ?: Int.MAX_VALUE }
        viewModelScope.launch {
            try {
                repository.reorderEntries(_entries.value.map { it.id })
                onSyncNeeded?.invoke()
            } catch (_: Exception) {
                _entries.value = repository.getAllEntries(_vaultKey.value ?: return@launch)
            }
        }
    }

    fun moveEntry(id: String, direction: Int) {
        val list = _entries.value.toMutableList()
        val index = list.indexOfFirst { it.id == id }
        if (index < 0) return
        val newIndex = index + direction
        if (newIndex < 0 || newIndex >= list.size) return

        val item = list.removeAt(index)
        list.add(newIndex, item)
        _entries.value = list
        reorderEntries(list.map { it.id })
    }

    fun getEntry(id: String): VaultEntry? = _entries.value.find { it.id == id }

    fun clearError() {
        _error.value = null
    }

    fun getExportData(format: String, password: String? = null): String? {
        return try {
            when (format) {
                "encrypted" -> {
                    if (password.isNullOrEmpty()) { _error.value = "Password required"; return null }
                    VaultExport.exportEncrypted(_entries.value, password)
                }
                "plain" -> VaultExport.exportPlain(_entries.value)
                "otpauth" -> VaultExport.exportOtpauthUris(_entries.value)
                else -> null
            }
        } catch (e: Exception) {
            _error.value = "Export failed: ${e.message}"
            null
        }
    }

    // --- Import with conflict resolution ---

    private val _importCandidates = MutableStateFlow<List<ImportCandidate>?>(null)
    val importCandidates: StateFlow<List<ImportCandidate>?> = _importCandidates.asStateFlow()

    private val _duplicateAction = MutableStateFlow(ImportAction.OVERWRITE)
    val duplicateAction: StateFlow<ImportAction> = _duplicateAction.asStateFlow()

    /** (done, total) when downloading URL icons during import, or null when not active. */
    private val _iconProgress = MutableStateFlow<Pair<Int, Int>?>(null)
    val iconProgress: StateFlow<Pair<Int, Int>?> = _iconProgress.asStateFlow()

    /**
     * Parse an import file and build candidates with duplicate detection.
     * Sets importCandidates for the UI to display, or sets error to "NEEDS_PASSWORD".
     */
    fun prepareImport(content: String, password: String? = null) {
        viewModelScope.launch {
            try {
                val parsed = if (password != null) {
                    VaultExport.importEncrypted(content, password)
                } else {
                    when (val result = VaultExport.importAutoDetect(content)) {
                        is VaultExport.ImportResult.Success -> result.entries
                        is VaultExport.ImportResult.NeedsPassword -> {
                            _error.value = "NEEDS_PASSWORD"
                            return@launch
                        }
                        is VaultExport.ImportResult.Error -> {
                            _error.value = result.message
                            return@launch
                        }
                    }
                }

                val resolved = resolveIconUrls(parsed)
                _importCandidates.value = ImportCandidate.buildCandidates(resolved, _entries.value)
            } catch (e: Exception) {
                _error.value = "Import failed: ${e.message}"
            }
        }
    }

    /** Download URL-based icons, replacing with data URLs. Icons that fail to fetch become null. */
    private suspend fun resolveIconUrls(entries: List<VaultEntryPlaintext>): List<VaultEntryPlaintext> {
        val urls = entries.mapNotNull { it.icon }.filter { IconFetch.isUrl(it) }.distinct()
        if (urls.isEmpty()) return entries

        _iconProgress.value = 0 to urls.size
        val iconByUrl = mutableMapOf<String, String?>()
        urls.forEachIndexed { index, url ->
            iconByUrl[url] = IconFetch.downloadAsDataUrl(url)
            _iconProgress.value = (index + 1) to urls.size
        }
        _iconProgress.value = null

        return entries.map { e ->
            if (IconFetch.isUrl(e.icon)) e.copy(icon = iconByUrl[e.icon!!]) else e
        }
    }

    /** Set the global action for all duplicate entries. */
    fun setDuplicateAction(action: ImportAction) {
        _duplicateAction.value = action
        _importCandidates.value = _importCandidates.value?.map { c ->
            if (c.isDuplicate) c.copy(action = action) else c
        }
    }

    /** Override the action for a single import candidate by index. */
    fun setImportCandidateAction(index: Int, action: ImportAction) {
        _importCandidates.value = _importCandidates.value?.mapIndexed { i, c ->
            if (i == index) c.copy(action = action) else c
        }
    }

    /** Cancel the pending import. */
    fun cancelImport() {
        _importCandidates.value = null
    }

    /**
     * Execute the import according to each candidate's chosen action.
     * Overwrites update existing entries; add-copies create new entries with deduplicated names.
     */
    fun confirmImport(onComplete: (Int) -> Unit) {
        val key = _vaultKey.value
        val candidates = _importCandidates.value
        if (key == null || candidates == null) return

        viewModelScope.launch {
            try {
                var imported = 0
                val allEntries = _entries.value.toMutableList() // Track additions for name deduplication
                for (candidate in candidates) {
                    if (candidate.action == ImportAction.SKIP) continue

                    val match = candidate.existingMatch
                    if (candidate.action == ImportAction.OVERWRITE && match != null) {
                        val updated = match.copy(
                            issuer = candidate.imported.issuer,
                            accountName = candidate.imported.accountName,
                            secret = candidate.imported.secret,
                            algorithm = candidate.imported.algorithm,
                            digits = candidate.imported.digits,
                            period = candidate.imported.period,
                            icon = candidate.imported.icon,
                        )
                        repository.updateEntry(key, updated)
                    } else {
                        val plaintext = if (match != null) {
                            candidate.imported.copy(
                                accountName = ImportCandidate.makeUniqueName(
                                    candidate.imported.accountName,
                                    candidate.imported.issuer,
                                    allEntries,
                                )
                            )
                        } else {
                            candidate.imported
                        }
                        val entry = repository.addEntry(key, plaintext)
                        allEntries.add(entry)
                    }
                    imported++
                }

                _entries.value = repository.getAllEntries(key)
                _importCandidates.value = null
                onComplete(imported)
                onSyncNeeded?.invoke()
            } catch (e: Exception) {
                _error.value = "Import failed: ${e.message}"
            }
        }
    }
}
