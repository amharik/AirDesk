package com.airdesk.android.identity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceIdTest {
    @Test
    fun matchesKnownSha256Vector() {
        val actual = DeviceId.fromSpki("airdesk-test-spki".toByteArray(Charsets.UTF_8))
        assertEquals(
            "ad-device:7ce97bbaf7235efcc1591592a01893fbcf579d353538f4559d19417e1982b815",
            actual,
        )
    }

    @Test
    fun formattingIsLowercaseHexWithPrefix() {
        val id = DeviceId.fromSpki("another-spki".toByteArray(Charsets.UTF_8))
        assertTrue(id.startsWith(DeviceId.PREFIX))
        assertEquals("ad-device:".length + 64, id.length)
        assertEquals(id, id.lowercase())
        assertTrue(DeviceId.isValid(id))
    }

    @Test
    fun differentSpkiProducesDifferentId() {
        val first = DeviceId.fromSpki("a".toByteArray(Charsets.UTF_8))
        val second = DeviceId.fromSpki("b".toByteArray(Charsets.UTF_8))
        assertNotEquals(first, second)
    }

    @Test
    fun rejectsWrongPrefixCaseOrLength() {
        assertFalse(DeviceId.isValid("ad-device:" + "A".repeat(64)))
        assertFalse(DeviceId.isValid("ad-device:" + "a".repeat(63)))
        assertFalse(DeviceId.isValid("AD-DEVICE:" + "a".repeat(64)))
    }

    @Test
    fun hexEncodingIsStable() {
        assertEquals("00ff10", DeviceId.hexLowercase(byteArrayOf(0x00, 0xff.toByte(), 0x10)))
    }
}
