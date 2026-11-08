package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object AdPairKeySchedule {
    const val VERSION = 1
    const val DOMAIN = "AD-PAIR-1-KS"
    const val KEY_BYTES = 32

    data class Key(val purpose: String, val bytes: ByteArray) {
        override fun equals(other: Any?): Boolean =
            other is Key && purpose == other.purpose && bytes.contentEquals(other.bytes)

        override fun hashCode(): Int = 31 * purpose.hashCode() + bytes.contentHashCode()
    }

    data class Keys(
        val initiatorToResponder: Key,
        val responderToInitiator: Key,
        val transport: Key,
    )

    fun derive(
        pakeSharedSecret: ByteArray,
        transcriptHash: ByteArray,
        channelBinding: AdPairChannelBinding,
    ): Keys {
        require(pakeSharedSecret.size in 16..1024) { "PAKE shared secret length out of range" }
        require(transcriptHash.size == 32) { "AD-PAIR-1 transcript hash must be 32 bytes" }
        require(channelBinding.value.isNotEmpty()) { "AD-PAIR-1 requires a non-empty channel binding" }
        val transcriptHex = DeviceId.hexLowercase(transcriptHash)
        fun key(label: String): Key {
            val info = buildString {
                append("{\"domain\":")
                append(quote(DOMAIN))
                append(",\"version\":")
                append(VERSION)
                append(",\"label\":")
                append(quote(label))
                append(",\"channelBinding\":{\"kind\":")
                append(quote(channelBinding.kind))
                append(",\"value\":")
                append(quote(channelBinding.value))
                append("},\"transcriptHash\":")
                append(quote(transcriptHex))
                append("}")
            }.toByteArray(Charsets.UTF_8)
            return Key(label, hkdf(pakeSharedSecret, transcriptHash, info, KEY_BYTES))
        }
        return Keys(
            initiatorToResponder = key("i2r"),
            responderToInitiator = key("r2i"),
            transport = key("transport"),
        )
    }

    private fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val prk = hmac(salt, ikm)
        val out = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(prk, "HmacSHA256"))
            mac.update(previous)
            mac.update(info)
            mac.update(counter.toByte())
            previous = mac.doFinal()
            val copy = minOf(previous.size, length - offset)
            previous.copyInto(out, offset, 0, copy)
            offset += copy
            counter += 1
        }
        return out
    }

    private fun hmac(key: ByteArray, message: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(message)
        }

    private fun quote(value: String): String = buildString {
        append('"')
        for (character in value) {
            when (character) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (character.code < 0x20) {
                    append("\\u")
                    append(character.code.toString(16).padStart(4, '0'))
                } else {
                    append(character)
                }
            }
        }
        append('"')
    }
}
