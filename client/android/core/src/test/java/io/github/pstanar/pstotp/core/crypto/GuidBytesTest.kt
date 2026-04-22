package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class GuidBytesTest {

    @Test
    fun `converts zero GUID to correct bytes`() {
        val bytes = GuidBytes.guidToBytes("00000000-0000-0000-0000-000000000000")
        assertArrayEquals(ByteArray(16), bytes)
    }

    @Test
    fun `matches dotnet Guid ToByteArray for known value`() {
        // .NET: new Guid("aabbccdd-eeff-0011-2233-445566778899").ToByteArray()
        // yields: dd cc bb aa ff ee 11 00 22 33 44 55 66 77 88 99
        val bytes = GuidBytes.guidToBytes("aabbccdd-eeff-0011-2233-445566778899")
        val expected = byteArrayOf(
            0xdd.toByte(), 0xcc.toByte(), 0xbb.toByte(), 0xaa.toByte(), // group 1 reversed
            0xff.toByte(), 0xee.toByte(),                               // group 2 reversed
            0x11, 0x00,                                                   // group 3 reversed
            0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88.toByte(), 0x99.toByte(), // groups 4-5 as-is
        )
        assertArrayEquals(expected, bytes)
    }

    @Test
    fun `handles typical UUID format`() {
        // .NET: new Guid("01020304-0506-0708-090a-0b0c0d0e0f10").ToByteArray()
        // yields: 04 03 02 01 06 05 08 07 09 0a 0b 0c 0d 0e 0f 10
        val bytes = GuidBytes.guidToBytes("01020304-0506-0708-090a-0b0c0d0e0f10")
        val expected = byteArrayOf(
            0x04, 0x03, 0x02, 0x01,
            0x06, 0x05,
            0x08, 0x07,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
        )
        assertArrayEquals(expected, bytes)
    }
}
