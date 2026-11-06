package com.airdesk.android.identity

import java.security.MessageDigest

object DeviceId {
    const val PREFIX = "ad-device:"
    private val shape = Regex("^ad-device:[0-9a-f]{64}$")

    fun fromSpki(spki: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(spki)
        return PREFIX + hexLowercase(digest)
    }

    fun isValid(value: String): Boolean = shape.matches(value)

    fun hexLowercase(bytes: ByteArray): String {
        val digits = "0123456789abcdef"
        val out = CharArray(bytes.size * 2)
        bytes.forEachIndexed { index, byte ->
            val value = byte.toInt() and 0xff
            out[index * 2] = digits[value ushr 4]
            out[index * 2 + 1] = digits[value and 0x0f]
        }
        return String(out)
    }
}
