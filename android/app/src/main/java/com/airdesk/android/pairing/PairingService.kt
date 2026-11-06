package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId

class PairingService(
    private val peers: PeerRegistry,
    private val nonces: NonceStore,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000L },
) {
    fun validate(text: String, ownDeviceId: String?): PairingValidation =
        PairingValidator.validate(text, clock(), ownDeviceId)

    fun accept(
        text: String,
        ownDeviceId: String?,
        label: String? = null,
    ): PairingResult {
        val validation = validate(text, ownDeviceId)
        if (validation is PairingValidation.Invalid) {
            return PairingResult.Rejected(validation.error, validation.message)
        }
        val offer = (validation as PairingValidation.Valid).offer
        if (nonces.contains(offer.nonce)) {
            return PairingResult.Rejected(PairingError.REPLAYED, "this offer nonce has already been used")
        }
        val peer = PeerRecord(
            deviceId = offer.deviceId,
            publicKey = offer.publicKey,
            displayName = label?.trim()?.takeIf { it.isNotEmpty() } ?: defaultLabel(offer.deviceId),
            pairedAtEpochSeconds = clock(),
            capabilities = offer.capabilities,
        )
        peers.upsert(peer)
        nonces.consume(offer.nonce)
        return PairingResult.Accepted(peer, offer)
    }

    private fun defaultLabel(deviceId: String): String =
        "Peer " + deviceId.removePrefix(DeviceId.PREFIX).take(12)
}
