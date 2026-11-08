package com.airdesk.android.pairing

import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

object PairingWire {
    const val PROTOCOL = "adpair-wire"
    const val VERSION = 1
    const val MAX_PAYLOAD_BYTES = 1_048_576

    val PAYLOAD_NAMES = listOf("response", "share", "confirmation", "signature")

    enum class Kind(val wireName: String) {
        RESPONSE("response"),
        SHARE("share"),
        VERIFIER_RESPONSE("verifier-response"),
        INITIATOR_FINISH("initiator-finish"),
        RESPONDER_FINISH("responder-finish");

        companion object {
            fun fromWireName(name: String): Kind? = entries.firstOrNull { it.wireName == name }
        }
    }

    enum class ErrorCode {
        MALFORMED,
        UNSUPPORTED_PROTOCOL,
        UNSUPPORTED_VERSION,
        INVALID_PAYLOAD,
    }

    class PairingWireException(
        val code: ErrorCode,
        message: String,
    ) : IllegalArgumentException(message)

    data class Message(
        val kind: Kind,
        val response: ByteArray? = null,
        val share: ByteArray? = null,
        val confirmation: ByteArray? = null,
        val signature: ByteArray? = null,
    ) {
        override fun equals(other: Any?): Boolean =
            other is Message &&
                kind == other.kind &&
                response.contentEqualsNullable(other.response) &&
                share.contentEqualsNullable(other.share) &&
                confirmation.contentEqualsNullable(other.confirmation) &&
                signature.contentEqualsNullable(other.signature)

        override fun hashCode(): Int = listOf(
            kind,
            response.contentHashCodeNullable(),
            share.contentHashCodeNullable(),
            confirmation.contentHashCodeNullable(),
            signature.contentHashCodeNullable(),
        ).hashCode()
    }

    fun response(response: ByteArray): Message = message(Kind.RESPONSE, response = response)

    fun share(share: ByteArray): Message = message(Kind.SHARE, share = share)

    fun verifierResponse(share: ByteArray, confirmation: ByteArray, signature: ByteArray): Message =
        message(
            Kind.VERIFIER_RESPONSE,
            share = share,
            confirmation = confirmation,
            signature = signature,
        )

    fun initiatorFinish(confirmation: ByteArray, signature: ByteArray): Message =
        message(Kind.INITIATOR_FINISH, confirmation = confirmation, signature = signature)

    fun responderFinish(confirmation: ByteArray, signature: ByteArray): Message =
        message(Kind.RESPONDER_FINISH, confirmation = confirmation, signature = signature)

    fun encode(message: Message): ByteArray {
        validate(message)
        val encoded = buildJsonObject {
            put("protocol", JsonPrimitive(PROTOCOL))
            put("version", JsonPrimitive(VERSION))
            put("kind", JsonPrimitive(message.kind.wireName))
            message.response?.let { put("response", JsonPrimitive(base64(it))) }
            message.share?.let { put("share", JsonPrimitive(base64(it))) }
            message.confirmation?.let { put("confirmation", JsonPrimitive(base64(it))) }
            message.signature?.let { put("signature", JsonPrimitive(base64(it))) }
        }
        return encoded.toString().toByteArray(Charsets.UTF_8)
    }

    fun decode(serialized: String): Message {
        val record = try {
            Json.parseToJsonElement(serialized)
        } catch (error: Exception) {
            fail(ErrorCode.MALFORMED, "Pairing message is malformed.")
        }
        if (record !is JsonObject) {
            fail(ErrorCode.MALFORMED, "Pairing message is malformed.")
        }
        val protocol = record.primitiveString("protocol")
        if (protocol == null) fail(ErrorCode.MALFORMED, "Pairing message is malformed.")
        if (protocol != PROTOCOL) {
            fail(ErrorCode.UNSUPPORTED_PROTOCOL, "Unsupported pairing message protocol.")
        }
        val version = (record["version"] as? JsonPrimitive)?.content?.toIntOrNull()
        if (version != VERSION) {
            fail(ErrorCode.UNSUPPORTED_VERSION, "Unsupported pairing message version.")
        }
        val kindName = record.primitiveString("kind")
        if (kindName == null) fail(ErrorCode.MALFORMED, "Pairing message is malformed.")
        val kind = Kind.fromWireName(kindName)
            ?: fail(ErrorCode.INVALID_PAYLOAD, "Invalid pairing wire kind: $kindName.")
        val payload = PAYLOAD_NAMES.associateWith { name ->
            val value = record[name] ?: return@associateWith null
            val primitive = value as? JsonPrimitive
            if (primitive == null || !primitive.isString) {
                fail(ErrorCode.INVALID_PAYLOAD, "Invalid pairing wire payload: $name.")
            }
            try {
                Base64.getDecoder().decode(primitive.content)
            } catch (error: Exception) {
                fail(ErrorCode.INVALID_PAYLOAD, "Invalid pairing wire payload: $name.")
            }
        }
        val result = Message(
            kind = kind,
            response = payload["response"],
            share = payload["share"],
            confirmation = payload["confirmation"],
            signature = payload["signature"],
        )
        validate(result)
        return result
    }

    fun decode(serialized: ByteArray): Message = decode(serialized.toString(Charsets.UTF_8))

    private fun message(
        kind: Kind,
        response: ByteArray? = null,
        share: ByteArray? = null,
        confirmation: ByteArray? = null,
        signature: ByteArray? = null,
    ): Message {
        val result = Message(kind, response, share, confirmation, signature)
        validate(result)
        return result
    }

    private fun validate(message: Message) {
        val allowed = when (message.kind) {
            Kind.RESPONSE -> setOf("response")
            Kind.SHARE -> setOf("share")
            Kind.VERIFIER_RESPONSE -> setOf("share", "confirmation", "signature")
            Kind.INITIATOR_FINISH, Kind.RESPONDER_FINISH -> setOf("confirmation", "signature")
        }
        for (name in PAYLOAD_NAMES) {
            val payload = when (name) {
                "response" -> message.response
                "share" -> message.share
                "confirmation" -> message.confirmation
                else -> message.signature
            }
            if (name in allowed) {
                validatePayload(payload, name)
            } else if (payload != null) {
                fail(
                    ErrorCode.INVALID_PAYLOAD,
                    "Invalid pairing wire message: ${message.kind.wireName}.",
                )
            }
        }
    }

    private fun validatePayload(payload: ByteArray?, name: String) {
        if (payload == null || payload.isEmpty() || payload.size > MAX_PAYLOAD_BYTES) {
            fail(ErrorCode.INVALID_PAYLOAD, "Invalid pairing wire payload: $name.")
        }
    }

    private fun JsonObject.primitiveString(name: String): String? {
        val value = this[name] as? JsonPrimitive ?: return null
        return if (value.isString) value.content else null
    }

    private fun base64(value: ByteArray): String = Base64.getEncoder().encodeToString(value)

    private fun fail(code: ErrorCode, message: String): Nothing =
        throw PairingWireException(code, message)

    private fun ByteArray?.contentEqualsNullable(other: ByteArray?): Boolean =
        if (this == null || other == null) this === other else contentEquals(other)

    private fun ByteArray?.contentHashCodeNullable(): Int =
        if (this == null) 0 else contentHashCode()
}
