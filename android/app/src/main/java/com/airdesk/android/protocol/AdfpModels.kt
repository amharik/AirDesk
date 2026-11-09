package com.airdesk.android.protocol

enum class AdfpError {
    EMPTY,
    OVERSIZED,
    TRUNCATED,
    WRONG_FILE_IDENTIFIER,
    WRONG_VERSION,
    MALFORMED,
    UNSUPPORTED_PAYLOAD,
    ROUND_TRIP,
    HEADER_EXPIRED,
    INVALID_PATH,
    INLINE_TOO_LARGE,
    AMBIGUOUS_PAYLOAD,
    UNSUPPORTED_BLOB,
}

class AdfpException(
    val reason: AdfpError,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

data class AdfpControlHeader(
    val messageId: String,
    val senderDeviceId: String,
    val senderRole: UByte,
    val correlationId: String? = null,
    val idempotencyKey: String? = null,
    val expiresAtEpochMillis: ULong = 0UL,
    val cancellationId: String? = null,
)

data class AdfpDeviceIdentity(
    val version: UInt,
    val kind: UByte,
    val deviceId: String,
    val publicKey: String,
    val nonce: ByteArray,
    val expiresAtEpochMillis: ULong,
    val channelBindingKind: UByte,
    val channelBindingValue: String?,
    val capabilities: List<String>,
)

data class AdfpPairingOffer(
    val identity: AdfpDeviceIdentity,
    val offerNonce: ByteArray,
    val expiresAtEpochMillis: ULong,
    val channelBindingKind: UByte,
    val channelBindingValue: String?,
    val capabilities: List<String>,
)

data class AdfpCapabilityDescriptor(
    val capUri: String,
    val version: UInt,
    val providerDeviceId: String,
    val availability: UByte,
    val authorization: UByte,
    val permissions: List<String>,
    val execution: String?,
    val transport: String?,
    val constraints: String?,
)

sealed interface AdfpPayload {
    data class Identity(val identity: AdfpDeviceIdentity) : AdfpPayload
    data class PairingOffer(val offer: AdfpPairingOffer) : AdfpPayload
    data class CapabilityDescriptor(val descriptor: AdfpCapabilityDescriptor) : AdfpPayload
}

data class AdfpEnvelope(
    val version: UInt,
    val header: AdfpControlHeader,
    val payload: AdfpPayload,
)

class CanonicalPairingOffer(
    val bytes: ByteArray,
    val sha256Hex: String,
    val envelope: AdfpEnvelope,
)

data class AdfpSelfTestResult(
    val ok: Boolean,
    val detail: String,
)
