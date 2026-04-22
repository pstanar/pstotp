package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ClientProofTest {

    @Test
    fun `proof is deterministic for same inputs`() {
        val verifier = ByteArray(32) { it.toByte() }
        val nonce = ByteArray(16) { (it + 100).toByte() }
        val sessionId = "01020304-0506-0708-090a-0b0c0d0e0f10"

        val proof1 = ClientProof.compute(verifier, nonce, sessionId)
        val proof2 = ClientProof.compute(verifier, nonce, sessionId)

        assertEquals(32, proof1.size)
        assert(proof1.contentEquals(proof2))
    }

    @Test
    fun `different nonces produce different proofs`() {
        val verifier = ByteArray(32) { it.toByte() }
        val nonce1 = ByteArray(16) { 0x01 }
        val nonce2 = ByteArray(16) { 0x02 }
        val sessionId = "aabbccdd-eeff-0011-2233-445566778899"

        val proof1 = ClientProof.compute(verifier, nonce1, sessionId)
        val proof2 = ClientProof.compute(verifier, nonce2, sessionId)

        assert(!proof1.contentEquals(proof2))
    }

    @Test
    fun `different session IDs produce different proofs`() {
        val verifier = ByteArray(32) { it.toByte() }
        val nonce = ByteArray(16) { 0x01 }

        val proof1 = ClientProof.compute(verifier, nonce, "01020304-0506-0708-090a-0b0c0d0e0f10")
        val proof2 = ClientProof.compute(verifier, nonce, "11020304-0506-0708-090a-0b0c0d0e0f10")

        assert(!proof1.contentEquals(proof2))
    }
}
