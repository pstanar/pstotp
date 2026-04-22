package io.github.pstanar.pstotp.core.crypto

import io.github.pstanar.pstotp.core.model.api.Envelope
import java.util.Base64

/**
 * Helpers for converting between AES-GCM encrypted payloads and API Envelope DTOs.
 *
 * AES-GCM encrypt output: nonce(12) || ciphertext+tag
 * Envelope DTO: { ciphertext: base64(ciphertext+tag), nonce: base64(nonce), version: 1 }
 */
object EnvelopeHelper {

    private const val NONCE_SIZE = 12

    /** Encrypt plaintext with a key and return an Envelope DTO. */
    fun encrypt(key: ByteArray, plaintext: ByteArray): Envelope {
        val raw = AesGcm.encrypt(key, plaintext)
        return fromRaw(raw)
    }

    /** Decrypt an Envelope DTO with a key. */
    fun decrypt(key: ByteArray, envelope: Envelope): ByteArray {
        val raw = toRaw(envelope)
        return AesGcm.decrypt(key, raw)
    }

    /** Convert raw AES-GCM output (nonce || ciphertext+tag) to an Envelope DTO. */
    fun fromRaw(raw: ByteArray): Envelope = Envelope(
        ciphertext = Base64.getEncoder().encodeToString(raw.copyOfRange(NONCE_SIZE, raw.size)),
        nonce = Base64.getEncoder().encodeToString(raw.copyOfRange(0, NONCE_SIZE)),
    )

    /** Convert an Envelope DTO back to raw AES-GCM format (nonce || ciphertext+tag). */
    fun toRaw(envelope: Envelope): ByteArray {
        val nonce = Base64.getDecoder().decode(envelope.nonce)
        val ciphertext = Base64.getDecoder().decode(envelope.ciphertext)
        return nonce + ciphertext
    }
}
