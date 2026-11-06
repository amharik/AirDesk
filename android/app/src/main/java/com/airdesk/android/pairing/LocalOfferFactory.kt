package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.protocol.CanonicalPairingOfferBuilder
import com.airdesk.android.util.Base64Url
import java.security.SecureRandom
import kotlinx.serialization.encodeToString

object LocalOfferFactory {
    fun create(
        identity: DeviceIdentity,
        capabilities: List<String>,
        nowEpochSeconds: Long,
        secureRandom: SecureRandom = SecureRandom(),
    ): LocalOffer {
        val nonce = ByteArray(32).also(secureRandom::nextBytes)
        val offer = PairingOffer(
            protocol = PairingValidator.PROTOCOL,
            version = PairingValidator.VERSION,
            kind = PairingValidator.KIND,
            deviceId = identity.deviceId,
            publicKey = identity.publicKeyBase64Url,
            nonce = Base64Url.encode(nonce),
            expiresAt = nowEpochSeconds + PairingValidator.OFFER_LIFETIME_SECONDS,
            capabilities = capabilities,
        )
        val canonical = CanonicalPairingOfferBuilder.build(identity, offer)
        return LocalOffer(
            offer = offer,
            json = PairingJson.pretty.encodeToString(offer),
            canonical = canonical,
        )
    }
}
