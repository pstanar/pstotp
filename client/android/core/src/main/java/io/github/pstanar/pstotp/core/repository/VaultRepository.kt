package io.github.pstanar.pstotp.core.repository

import java.util.Base64
import io.github.pstanar.pstotp.core.crypto.AesGcm
import io.github.pstanar.pstotp.core.crypto.KeyDerivation
import io.github.pstanar.pstotp.core.crypto.KeystoreHelper
import javax.crypto.Cipher
import androidx.room.withTransaction
import io.github.pstanar.pstotp.core.db.AppDatabase
import io.github.pstanar.pstotp.core.db.EntryUsageEntity
import io.github.pstanar.pstotp.core.db.SettingsEntity
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.core.db.VaultEntryEntity
import io.github.pstanar.pstotp.core.model.VaultEntry
import io.github.pstanar.pstotp.core.model.VaultEntryPlaintext
import org.json.JSONObject
import java.util.UUID

/**
 * Repository that handles vault encryption/decryption and persistence.
 *
 * Vault entries are stored as AES-256-GCM encrypted JSON payloads.
 * The entry ID is used as associated data (AD) to bind the ciphertext to the entry.
 */
class VaultRepository(private val db: AppDatabase) {

    private val entryDao = db.vaultEntryDao()
    private val settingsDao = db.settingsDao()
    private val entryUsageDao = db.entryUsageDao()

    // --- Setup & Unlock ---

    suspend fun isSetUp(): Boolean = settingsDao.isSetUp()

    suspend fun setupPassword(password: String): ByteArray {
        val result = KeyDerivation.setupPassword(password)

        settingsDao.set(SettingsEntity(SettingsKeys.KDF_SALT, Base64.getEncoder().encodeToString(result.salt)))
        settingsDao.set(SettingsEntity(SettingsKeys.PASSWORD_VERIFIER, Base64.getEncoder().encodeToString(result.verifier)))
        settingsDao.set(SettingsEntity(SettingsKeys.ENCRYPTED_VAULT_KEY, Base64.getEncoder().encodeToString(result.encryptedVaultKey)))
        settingsDao.set(SettingsEntity(SettingsKeys.MODE, SettingsKeys.MODE_STANDALONE))

        return result.vaultKey
    }

    suspend fun unlockVault(password: String): ByteArray? {
        val saltB64 = settingsDao.get(SettingsKeys.KDF_SALT) ?: return null
        val verifierB64 = settingsDao.get(SettingsKeys.PASSWORD_VERIFIER) ?: return null
        val encKeyB64 = settingsDao.get(SettingsKeys.ENCRYPTED_VAULT_KEY) ?: return null

        val salt = Base64.getDecoder().decode(saltB64)
        val verifier = Base64.getDecoder().decode(verifierB64)
        val encKey = Base64.getDecoder().decode(encKeyB64)

        return KeyDerivation.unlockVault(password, salt, verifier, encKey)
    }

    // --- Vault CRUD ---

    /**
     * Decrypt all stored entries with the given vault key.
     *
     * Silent `mapNotNull`-style skipping has hidden a class of wrong-key bugs
     * several times (server-returned key was discarded by the UI and every
     * synced entry was silently dropped, user saw an empty vault with no
     * error). So: tolerate a single sporadic failure (rare storage
     * corruption), throw on anything beyond that.
     *
     * Mismatch when nothing decrypted (incl. a 1-entry vault whose single
     * entry failed) or more than one entry failed. One failure is always
     * tolerated — regardless of vault size — as long as something decrypted.
     */
    suspend fun getAllEntries(vaultKey: ByteArray): List<VaultEntry> {
        val all = entryDao.getAll()
        if (all.isEmpty()) return emptyList()

        val decrypted = mutableListOf<VaultEntry>()
        var failures = 0
        for (entity in all) {
            try {
                decrypted.add(decryptEntry(vaultKey, entity))
            } catch (_: Exception) {
                failures++
            }
        }

        if (isVaultKeyMismatch(failures = failures, successes = decrypted.size)) {
            throw VaultKeyMismatchException(failures, all.size)
        }
        return decrypted
    }

    suspend fun addEntry(vaultKey: ByteArray, plaintext: VaultEntryPlaintext): VaultEntry {
        val id = UUID.randomUUID().toString()
        val maxSort = entryDao.getMaxSortOrder() ?: -1
        val now = System.currentTimeMillis()
        val connected = isConnected()

        val json = plaintextToJson(plaintext)
        val encrypted = AesGcm.encrypt(vaultKey, json, id.toByteArray(Charsets.UTF_8))

        val entity = VaultEntryEntity(
            id = id,
            encryptedPayload = encrypted,
            sortOrder = maxSort + 1,
            createdAt = now,
            updatedAt = now,
            pendingSync = connected,
        )
        entryDao.upsert(entity)

        return VaultEntry(
            id = id,
            issuer = plaintext.issuer,
            accountName = plaintext.accountName,
            secret = plaintext.secret,
            algorithm = plaintext.algorithm,
            digits = plaintext.digits,
            period = plaintext.period,
            icon = plaintext.icon,
            sortOrder = entity.sortOrder,
        )
    }

    suspend fun updateEntry(vaultKey: ByteArray, entry: VaultEntry) {
        val existing = entryDao.getById(entry.id) ?: return
        val connected = isConnected()
        val plaintext = VaultEntryPlaintext(
            issuer = entry.issuer,
            accountName = entry.accountName,
            secret = entry.secret,
            algorithm = entry.algorithm,
            digits = entry.digits,
            period = entry.period,
            icon = entry.icon,
        )
        val json = plaintextToJson(plaintext)
        val encrypted = AesGcm.encrypt(vaultKey, json, entry.id.toByteArray(Charsets.UTF_8))

        entryDao.upsert(
            existing.copy(
                encryptedPayload = encrypted,
                updatedAt = System.currentTimeMillis(),
                pendingSync = connected,
            )
        )
    }

    suspend fun deleteEntry(id: String) {
        val connected = isConnected()
        entryDao.softDelete(id)
        if (connected) {
            entryDao.markPendingSync(id)
        }
        entryUsageDao.delete(id)
    }

    // --- Usage tracking (local-only) ---

    suspend fun getAllUsage(): List<EntryUsageEntity> = entryUsageDao.getAll()

    suspend fun recordEntryUse(entryId: String) {
        entryUsageDao.recordUse(entryId, System.currentTimeMillis())
    }

    suspend fun reorderEntries(orderedIds: List<String>) {
        orderedIds.forEachIndexed { index, id ->
            entryDao.updateSortOrder(id, index)
        }
        if (isConnected()) {
            settingsDao.set(SettingsEntity(SettingsKeys.PENDING_REORDER, "true"))
        }
    }

    suspend fun isPendingReorder(): Boolean =
        settingsDao.get(SettingsKeys.PENDING_REORDER) == "true"

    suspend fun clearPendingReorder() {
        settingsDao.delete(SettingsKeys.PENDING_REORDER)
    }

    /** Check if the app is in connected (server sync) mode. */
    suspend fun isConnected(): Boolean = settingsDao.get(SettingsKeys.MODE) == SettingsKeys.MODE_CONNECTED

    /** Get the encrypted payload as base64 for pushing to server. */
    suspend fun getEntryPayloadBase64(entryId: String): String? {
        val entity = entryDao.getById(entryId) ?: return null
        return Base64.getEncoder().encodeToString(entity.encryptedPayload)
    }

    /** Get the server entry version for an entry. */
    suspend fun getEntryVersion(entryId: String): Int {
        return entryDao.getById(entryId)?.entryVersion ?: 0
    }

    // --- Biometric ---

    suspend fun isBiometricEnabled(): Boolean =
        settingsDao.get(SettingsKeys.BIOMETRIC_ENABLED) == "true" && KeystoreHelper.hasValidKey()

    /**
     * Encrypt the vault key with the biometric-authenticated cipher and persist it.
     * Call this after a successful BiometricPrompt with an ENCRYPT-mode CryptoObject.
     */
    suspend fun storeBiometricKey(cipher: Cipher, vaultKey: ByteArray) {
        val encrypted = cipher.doFinal(vaultKey)
        val iv = cipher.iv

        settingsDao.set(SettingsEntity(SettingsKeys.BIOMETRIC_IV, Base64.getEncoder().encodeToString(iv)))
        settingsDao.set(SettingsEntity(SettingsKeys.BIOMETRIC_ENCRYPTED_KEY, Base64.getEncoder().encodeToString(encrypted)))
        settingsDao.set(SettingsEntity(SettingsKeys.BIOMETRIC_ENABLED, "true"))
    }

    /**
     * Get the IV needed to initialize the decrypt cipher for biometric unlock.
     * Returns null if biometric was never enrolled.
     */
    suspend fun getBiometricIv(): ByteArray? {
        val ivB64 = settingsDao.get(SettingsKeys.BIOMETRIC_IV) ?: return null
        return Base64.getDecoder().decode(ivB64)
    }

    /**
     * Decrypt the vault key with the biometric-authenticated cipher.
     * Call this after a successful BiometricPrompt with a DECRYPT-mode CryptoObject.
     */
    suspend fun unlockWithBiometric(cipher: Cipher): ByteArray? {
        val encB64 = settingsDao.get(SettingsKeys.BIOMETRIC_ENCRYPTED_KEY) ?: return null
        val encrypted = Base64.getDecoder().decode(encB64)
        return cipher.doFinal(encrypted)
    }

    /** Remove biometric key material and delete the Keystore key. */
    suspend fun disableBiometric() {
        KeystoreHelper.deleteKey()
        settingsDao.set(SettingsEntity(SettingsKeys.BIOMETRIC_ENABLED, "false"))
        settingsDao.set(SettingsEntity(SettingsKeys.BIOMETRIC_IV, ""))
        settingsDao.set(SettingsEntity(SettingsKeys.BIOMETRIC_ENCRYPTED_KEY, ""))
    }

    // --- Transactions ---

    /** Run a block inside a Room transaction for atomic multi-step persistence. */
    suspend fun <T> runInTransaction(block: suspend () -> T): T {
        return db.withTransaction { block() }
    }

    // --- Settings ---

    suspend fun getSetting(key: String): String? = settingsDao.get(key)

    suspend fun setSetting(key: String, value: String) {
        settingsDao.set(SettingsEntity(key, value))
    }

    // --- Encryption helpers ---

    private fun decryptEntry(vaultKey: ByteArray, entity: VaultEntryEntity): VaultEntry {
        val json = AesGcm.decrypt(vaultKey, entity.encryptedPayload, entity.id.toByteArray(Charsets.UTF_8))
        val plaintext = jsonToPlaintext(json)
        return VaultEntry(
            id = entity.id,
            issuer = plaintext.issuer,
            accountName = plaintext.accountName,
            secret = plaintext.secret,
            algorithm = plaintext.algorithm,
            digits = plaintext.digits,
            period = plaintext.period,
            icon = plaintext.icon,
            version = 1,
            sortOrder = entity.sortOrder,
        )
    }

    private fun plaintextToJson(plaintext: VaultEntryPlaintext): ByteArray {
        val obj = JSONObject().apply {
            put("issuer", plaintext.issuer)
            put("accountName", plaintext.accountName)
            put("secret", plaintext.secret)
            put("algorithm", plaintext.algorithm)
            put("digits", plaintext.digits)
            put("period", plaintext.period)
            if (plaintext.icon != null) put("icon", plaintext.icon)
        }
        return obj.toString().toByteArray(Charsets.UTF_8)
    }

    private fun jsonToPlaintext(json: ByteArray): VaultEntryPlaintext {
        val obj = JSONObject(String(json, Charsets.UTF_8))
        return VaultEntryPlaintext(
            issuer = obj.getString("issuer"),
            accountName = obj.getString("accountName"),
            secret = obj.getString("secret"),
            algorithm = obj.optString("algorithm", "SHA1"),
            digits = obj.optInt("digits", 6),
            period = obj.optInt("period", 30),
            icon = obj.optString("icon", null),
        )
    }
}
