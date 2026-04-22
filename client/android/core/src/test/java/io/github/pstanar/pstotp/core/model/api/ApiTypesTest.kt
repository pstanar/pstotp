package io.github.pstanar.pstotp.core.model.api

import org.junit.Assert.assertEquals
import org.junit.Test

class ApiTypesTest {

    @Test
    fun `KdfConfig default factory uses standard parameters`() {
        val config = KdfConfig.default("c2FsdA==")
        assertEquals("argon2id", config.algorithm)
        assertEquals(64, config.memoryMb)
        assertEquals(3, config.iterations)
        assertEquals(4, config.parallelism)
        assertEquals("c2FsdA==", config.salt)
    }

    @Test
    fun `DeviceDto android factory sets correct values`() {
        val device = DeviceDto.android("pubkey_b64")
        assertEquals("PsTotp on Android", device.deviceName)
        assertEquals("android", device.platform)
        assertEquals("android", device.clientType)
        assertEquals("pubkey_b64", device.devicePublicKey)
    }

    @Test
    fun `Envelope default version is 1`() {
        val envelope = Envelope("ct", "nc")
        assertEquals(1, envelope.version)
    }

    @Test
    fun `RecoveryDto default version is 1`() {
        val dto = RecoveryDto("ct", "nc", recoveryCodeHashes = listOf("h1"))
        assertEquals(1, dto.recoveryEnvelopeVersion)
    }
}
