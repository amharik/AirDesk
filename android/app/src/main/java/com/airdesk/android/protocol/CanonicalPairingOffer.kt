package com.airdesk.android.protocol

import AirDesk.Protocol.ChannelBindingKind
import AirDesk.Protocol.DeviceKind
import AirDesk.Protocol.SenderRole
import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.pairing.PairingOffer
import com.airdesk.android.util.Base64Url

object CanonicalPairingOfferBuilder {
    fun build(
        identity: DeviceIdentity,
        offer: PairingOffer,
        channelBindingCertificateHash: String = AdfpProtocol.sha256Hex(identity.publicKeySpki),
        deviceKind: UByte = DeviceKind.unknown,
    ): CanonicalPairingOffer {
        val nonce = Base64Url.decode(offer.nonce)
        require(offer.expiresAt >= 0) { "offer expiry must not be negative" }
        val expiresAtMillis = Math.multiplyExact(offer.expiresAt, 1000L).toULong()
        val messageId = "pairing-offer:" + AdfpProtocol.sha256Hex(nonce).take(32)

        val canonicalIdentity = AdfpDeviceIdentity(
            version = 1u,
            kind = deviceKind,
            deviceId = offer.deviceId,
            publicKey = identity.publicKeyBase64Url,
            nonce = nonce,
            expiresAtEpochMillis = expiresAtMillis,
            channelBindingKind = ChannelBindingKind.certificate_hash,
            channelBindingValue = channelBindingCertificateHash,
            capabilities = offer.capabilities,
        )
        val canonicalOffer = AdfpPairingOffer(
            identity = canonicalIdentity,
            offerNonce = nonce,
            expiresAtEpochMillis = expiresAtMillis,
            channelBindingKind = ChannelBindingKind.certificate_hash,
            channelBindingValue = channelBindingCertificateHash,
            capabilities = offer.capabilities,
        )
        val header = AdfpControlHeader(
            messageId = messageId,
            senderDeviceId = identity.deviceId,
            senderRole = SenderRole.agent,
            expiresAtEpochMillis = expiresAtMillis,
        )

        val bytes = AdfpProtocol.encodePairingOffer(header, canonicalOffer)
        val decoded = AdfpProtocol.decode(bytes)
        val decodedOffer = decoded.payload as? AdfpPayload.PairingOffer
            ?: throw AdfpException(AdfpError.ROUND_TRIP, "canonical offer did not decode as a PairingOffer")
        val reencoded = AdfpProtocol.encodePairingOffer(decoded.header, decodedOffer.offer)
        if (!reencoded.contentEquals(bytes)) {
            throw AdfpException(
                AdfpError.ROUND_TRIP,
                "canonical offer failed deterministic round-trip verification",
            )
        }

        return CanonicalPairingOffer(
            bytes = bytes,
            sha256Hex = AdfpProtocol.sha256Hex(bytes),
            envelope = decoded,
        )
    }
}
