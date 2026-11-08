package com.airdesk.android.pairing

import kotlinx.serialization.Serializable

@Serializable
data class PairingOffer(
    val protocol: String,
    val version: String,
    val kind: String,
    val deviceId: String,
    val publicKey: String,
    val nonce: String,
    val expiresAt: Long,
    val capabilities: List<String>,
)

@Serializable
data class PeerRecord(
    val deviceId: String,
    val publicKey: String,
    val displayName: String,
    val pairedAtEpochSeconds: Long,
    val capabilities: List<String>,
    val trusted: Boolean = true,
    val revoked: Boolean = false,
    val revokedAtEpochSeconds: Long? = null,
)

data class LocalOffer(
    val offer: PairingOffer,
    val json: String,
    val canonical: com.airdesk.android.protocol.CanonicalPairingOffer? = null,
)

enum class PairingError {
    MALFORMED,
    WRONG_PROTOCOL,
    WRONG_VERSION,
    WRONG_KIND,
    INVALID_DEVICE_ID,
    SELF_PAIRING,
    INVALID_PUBLIC_KEY,
    INVALID_NONCE,
    INVALID_CAPABILITY,
    EXPIRED,
    EXPIRY_TOO_FAR,
    REPLAYED,
}

sealed interface PairingValidation {
    data class Valid(
        val offer: PairingOffer,
        val peerPublicKeySpki: ByteArray,
    ) : PairingValidation

    data class Invalid(
        val error: PairingError,
        val message: String,
    ) : PairingValidation
}

sealed interface PairingResult {
    data class Accepted(
        val peer: PeerRecord,
        val offer: PairingOffer,
    ) : PairingResult

    data class Rejected(
        val error: PairingError,
        val message: String,
    ) : PairingResult
}
