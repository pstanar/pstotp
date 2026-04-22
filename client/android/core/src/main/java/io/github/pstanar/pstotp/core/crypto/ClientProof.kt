package io.github.pstanar.pstotp.core.crypto

/**
 * Compute the client proof for password-based login.
 *
 * The proof demonstrates knowledge of the password verifier without
 * transmitting the password or verifier. The server computes the same
 * HMAC and compares.
 *
 * Must match the web client's computeClientProof().
 */
object ClientProof {

    /**
     * Compute HMAC-SHA256(key=verifier, message=nonce || guidToBytes(loginSessionId)).
     *
     * @param verifier 32-byte password verifier derived via HKDF
     * @param nonce Server-provided random nonce (16 bytes)
     * @param loginSessionId Server-provided login session GUID string
     * @return 32-byte client proof
     */
    fun compute(verifier: ByteArray, nonce: ByteArray, loginSessionId: String): ByteArray {
        val sessionBytes = GuidBytes.guidToBytes(loginSessionId)
        val message = nonce + sessionBytes
        return Hkdf.hmacSha256(verifier, message)
    }
}
