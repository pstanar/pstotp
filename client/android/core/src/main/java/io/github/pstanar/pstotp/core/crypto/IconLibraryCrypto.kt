package io.github.pstanar.pstotp.core.crypto

import io.github.pstanar.pstotp.core.model.IconLibraryBlob

/**
 * Encrypt / decrypt the user's icon-library blob with the vault key.
 * Mirrors the web client's icon-library-crypto.ts byte-for-byte: same
 * AEAD (AES-256-GCM), same AAD ("pstotp-icon-library-v1"), same
 * nonce(12) || ciphertext+tag(16) layout. A blob written on one
 * platform must decrypt on the other.
 */
object IconLibraryCrypto {

    /** Fixed AD per blob-format version. Changing the string invalidates
     *  all existing blobs — only do that with an explicit migration. */
    private val AD_V1 = "pstotp-icon-library-v1".toByteArray(Charsets.UTF_8)

    /**
     * Encrypt a blob with the given vault key. Returns the raw
     * nonce||ciphertext||tag bytes; the caller base64-encodes before
     * sending to the server or storing locally.
     */
    fun encrypt(vaultKey: ByteArray, blob: IconLibraryBlob): ByteArray {
        val plaintext = blob.toJsonString().toByteArray(Charsets.UTF_8)
        return AesGcm.encrypt(vaultKey, plaintext, AD_V1)
    }

    /**
     * Decrypt a blob fetched from the server or loaded from local
     * settings. Throws on MAC failure / wrong key.
     */
    fun decrypt(vaultKey: ByteArray, payload: ByteArray): IconLibraryBlob {
        val plaintext = AesGcm.decrypt(vaultKey, payload, AD_V1)
        return IconLibraryBlob.fromJsonString(String(plaintext, Charsets.UTF_8))
    }
}
