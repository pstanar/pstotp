package io.github.pstanar.pstotp.core.crypto

import java.math.BigInteger
import java.util.Base64
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.security.spec.PKCS8EncodedKeySpec
import javax.crypto.KeyAgreement

/**
 * ECDH P-256 operations for device envelope key exchange.
 *
 * Device envelopes wrap the vault key with an ECDH-derived AES key so that
 * each device can decrypt the vault key using its own private key. The wire
 * format matches the web client's packEcdhDeviceEnvelope/unpackEcdhDeviceEnvelope.
 *
 * Wire format (before base64): [ephemeralPubKey(65)] [ciphertext+tag]
 * Nonce is transmitted separately.
 */
object Ecdh {

    private const val CURVE = "secp256r1"
    private const val DEVICE_ENVELOPE_CONTEXT = "device-envelope-v1"
    private const val COORD_SIZE = 32
    const val PUBLIC_KEY_LENGTH = 65  // 0x04 + X(32) + Y(32)

    /** Generate a new ECDH P-256 key pair. */
    fun generateKeyPair(): KeyPair {
        val gen = KeyPairGenerator.getInstance("EC")
        gen.initialize(ECGenParameterSpec(CURVE))
        return gen.generateKeyPair()
    }

    /**
     * Export a public key as 65-byte uncompressed point: [0x04 || X(32) || Y(32)].
     * This format is interoperable with the Web Crypto API.
     */
    fun exportPublicKey(publicKey: PublicKey): ByteArray {
        val ecKey = publicKey as ECPublicKey
        val point = ecKey.w
        val x = toFixedBytes(point.affineX, COORD_SIZE)
        val y = toFixedBytes(point.affineY, COORD_SIZE)
        return byteArrayOf(0x04) + x + y
    }

    /**
     * Import a public key from 65-byte uncompressed point format.
     */
    fun importPublicKey(bytes: ByteArray): PublicKey {
        require(bytes.size == PUBLIC_KEY_LENGTH && bytes[0] == 0x04.toByte()) {
            "Expected 65-byte uncompressed EC point (0x04 prefix)"
        }
        val x = BigInteger(1, bytes.copyOfRange(1, 1 + COORD_SIZE))
        val y = BigInteger(1, bytes.copyOfRange(1 + COORD_SIZE, PUBLIC_KEY_LENGTH))

        // Get the P-256 parameter spec from a temporary key pair
        val tempGen = KeyPairGenerator.getInstance("EC")
        tempGen.initialize(ECGenParameterSpec(CURVE))
        val tempKey = tempGen.generateKeyPair().public as ECPublicKey
        val params: ECParameterSpec = tempKey.params

        val point = ECPoint(x, y)
        val spec = ECPublicKeySpec(point, params)
        return KeyFactory.getInstance("EC").generatePublic(spec)
    }

    /** Export a private key as PKCS#8 DER bytes (for encrypted storage). */
    fun exportPrivateKey(privateKey: PrivateKey): ByteArray = privateKey.encoded

    /** Import a private key from PKCS#8 DER bytes. */
    fun importPrivateKey(bytes: ByteArray): PrivateKey {
        return KeyFactory.getInstance("EC").generatePrivate(PKCS8EncodedKeySpec(bytes))
    }

    /**
     * Derive the AES wrapping key from an ECDH shared secret.
     * ECDH raw shared secret → HKDF-SHA256(info="device-envelope-v1") → 32 bytes.
     */
    fun deriveWrappingKey(privateKey: PrivateKey, publicKey: PublicKey): ByteArray {
        val agreement = KeyAgreement.getInstance("ECDH")
        agreement.init(privateKey)
        agreement.doPhase(publicKey, true)
        val sharedSecret = agreement.generateSecret()
        return Hkdf.derive(sharedSecret, DEVICE_ENVELOPE_CONTEXT)
    }

    /**
     * Pack a device envelope: encrypt the vault key for the recipient.
     *
     * 1. Generate ephemeral key pair
     * 2. ECDH with recipient's public key → wrapping key
     * 3. AES-GCM encrypt vault key
     * 4. Wire format: [ephemeralPubKey(65) || ciphertext+tag]
     *
     * @return Pair(ciphertext=base64, nonce=base64)
     */
    fun packDeviceEnvelope(vaultKey: ByteArray, recipientPublicKey: PublicKey): EnvelopeParts {
        val ephemeral = generateKeyPair()
        val ephemeralPubBytes = exportPublicKey(ephemeral.public)
        val wrappingKey = deriveWrappingKey(ephemeral.private, recipientPublicKey)

        // AES-GCM encrypt (returns nonce || ciphertext+tag)
        val encrypted = AesGcm.encrypt(wrappingKey, vaultKey)
        val nonce = encrypted.copyOfRange(0, 12)
        val ciphertextAndTag = encrypted.copyOfRange(12, encrypted.size)

        // Wire format: ephemeralPubKey || ciphertext+tag
        val wire = ephemeralPubBytes + ciphertextAndTag

        return EnvelopeParts(
            ciphertext = Base64.getEncoder().encodeToString(wire),
            nonce = Base64.getEncoder().encodeToString(nonce),
        )
    }

    /**
     * Unpack a device envelope: decrypt the vault key using our private key.
     *
     * 1. Split wire format: first 65 bytes = ephemeral public key, rest = ciphertext+tag
     * 2. ECDH with ephemeral public key → wrapping key
     * 3. AES-GCM decrypt → vault key
     */
    fun unpackDeviceEnvelope(
        ciphertextB64: String,
        nonceB64: String,
        devicePrivateKey: PrivateKey,
    ): ByteArray {
        val wire = Base64.getDecoder().decode(ciphertextB64)
        val nonce = Base64.getDecoder().decode(nonceB64)

        require(wire.size > PUBLIC_KEY_LENGTH) { "Envelope too short" }

        val ephemeralPubBytes = wire.copyOfRange(0, PUBLIC_KEY_LENGTH)
        val ciphertextAndTag = wire.copyOfRange(PUBLIC_KEY_LENGTH, wire.size)

        val ephemeralPubKey = importPublicKey(ephemeralPubBytes)
        val wrappingKey = deriveWrappingKey(devicePrivateKey, ephemeralPubKey)

        // Reconstruct the AesGcm payload format: nonce || ciphertext+tag
        val payload = nonce + ciphertextAndTag
        return AesGcm.decrypt(wrappingKey, payload)
    }

    /** BigInteger to fixed-length unsigned byte array, left-padded with zeros. */
    private fun toFixedBytes(value: BigInteger, length: Int): ByteArray {
        val bytes = value.toByteArray()
        return when {
            bytes.size == length -> bytes
            bytes.size > length -> bytes.copyOfRange(bytes.size - length, bytes.size) // strip leading zero
            else -> ByteArray(length - bytes.size) + bytes // left-pad
        }
    }
}

data class EnvelopeParts(val ciphertext: String, val nonce: String)
