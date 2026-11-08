package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import java.security.MessageDigest

data class AdPairPakeEvidence(
    val initiatorShare: String,
    val responderShare: String,
    val initiatorConfirmation: String,
    val responderConfirmation: String,
) {
    companion object {
        fun fromBytes(
            initiatorShare: ByteArray,
            responderShare: ByteArray,
            initiatorConfirmation: ByteArray,
            responderConfirmation: ByteArray,
        ): AdPairPakeEvidence = AdPairPakeEvidence(
            initiatorShare = com.airdesk.android.util.Base64Url.encode(initiatorShare),
            responderShare = com.airdesk.android.util.Base64Url.encode(responderShare),
            initiatorConfirmation = com.airdesk.android.util.Base64Url.encode(initiatorConfirmation),
            responderConfirmation = com.airdesk.android.util.Base64Url.encode(responderConfirmation),
        )
    }
}

object AdPairTranscript {
    const val DOMAIN = "AD-PAIR-1"
    const val SAS_DOMAIN = "AD-PAIR-1-SAS"

    fun canonical(
        offer: AdPairOffer,
        response: AdPairOffer,
        pake: AdPairPakeEvidence,
    ): ByteArray {
        if (offer.channelBinding != response.channelBinding) {
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.BINDING_MISMATCH,
                "pairing channel binding mismatch",
            )
        }
        val json = buildString {
            append("{\"domain\":")
            append(quote(DOMAIN))
            append(",\"protocol\":")
            append(quote(offer.protocol))
            append(",\"version\":")
            append(quote(offer.version))
            append(",\"channelBinding\":")
            append(bindingJson(offer.channelBinding))
            append(",\"offer\":")
            append(payloadJson(offer))
            append(",\"response\":")
            append(payloadJson(response))
            append(",\"pake\":{\"initiatorShare\":")
            append(quote(pake.initiatorShare))
            append(",\"responderShare\":")
            append(quote(pake.responderShare))
            append(",\"initiatorConfirmation\":")
            append(quote(pake.initiatorConfirmation))
            append(",\"responderConfirmation\":")
            append(quote(pake.responderConfirmation))
            append("}}")
        }
        return "$DOMAIN\n$json".toByteArray(Charsets.UTF_8)
    }

    fun hash(
        offer: AdPairOffer,
        response: AdPairOffer,
        pake: AdPairPakeEvidence,
    ): ByteArray = MessageDigest.getInstance("SHA-256").digest(canonical(offer, response, pake))

    fun shortAuthenticationString(transcriptHash: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(
            "$SAS_DOMAIN\n".toByteArray(Charsets.UTF_8) + transcriptHash,
        )
        var value = 0L
        for (index in 0 until 4) {
            value = (value shl 8) or (digest[index].toLong() and 0xff)
        }
        return (value % 1_000_000L).toString().padStart(6, '0')
    }

    fun transcriptHex(transcriptHash: ByteArray): String = DeviceId.hexLowercase(transcriptHash)

    private fun payloadJson(payload: AdPairOffer): String = buildString {
        append("{\"type\":")
        append(quote(payload.type))
        append(",\"deviceId\":")
        append(quote(payload.deviceId))
        append(",\"publicKey\":")
        append(quote(payload.publicKey))
        append(",\"nonce\":")
        append(quote(payload.nonce))
        append(",\"replyTo\":")
        append(payload.replyTo?.let(::quote) ?: "null")
        append(",\"expiresAt\":")
        append(payload.expiresAt)
        append(",\"endpointHint\":")
        append(payload.endpointHint?.let(::quote) ?: "null")
        append(",\"relayHint\":")
        append(payload.relayHint?.let(::quote) ?: "null")
        append(",\"capabilities\":[")
        append(payload.capabilities.sorted().joinToString(",") { quote(it) })
        append("],\"channelBinding\":")
        append(bindingJson(payload.channelBinding))
        append("}")
    }

    private fun bindingJson(binding: AdPairChannelBinding): String =
        "{\"kind\":${quote(binding.kind)},\"value\":${quote(binding.value)}}"

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
