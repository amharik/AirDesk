package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyFactory
import java.security.interfaces.ECPublicKey
import java.security.spec.X509EncodedKeySpec
import kotlinx.serialization.decodeFromString

object PairingValidator {
    const val PROTOCOL = "adfp"
    const val VERSION = "0.1"
    const val KIND = "pairing-offer"
    const val OFFER_LIFETIME_SECONDS = 300L
    private const val MAX_FUTURE_SECONDS = 3600L
    private const val MIN_NONCE_BYTES = 16
    private const val MAX_NONCE_BYTES = 64
    private const val MAX_CAPABILITIES = 64
    private val capabilityShape = Regex("^airdesk://[A-Za-z0-9._~/-]{1,200}$")

    fun validate(
        text: String,
        nowEpochSeconds: Long,
        ownDeviceId: String? = null,
    ): PairingValidation {
        val offer = try {
            PairingJson.strict.decodeFromString<PairingOffer>(text)
        } catch (error: Exception) {
            return invalid(PairingError.MALFORMED, "Offer is not valid adfp 0.1 pairing JSON")
        }

        if (offer.protocol != PROTOCOL) {
            return invalid(PairingError.WRONG_PROTOCOL, "protocol must be $PROTOCOL")
        }
        if (offer.version != VERSION) {
            return invalid(PairingError.WRONG_VERSION, "version must be $VERSION")
        }
        if (offer.kind != KIND) {
            return invalid(PairingError.WRONG_KIND, "kind must be $KIND")
        }
        if (!DeviceId.isValid(offer.deviceId)) {
            return invalid(PairingError.INVALID_DEVICE_ID, "deviceId must be ad-device: + 64 lowercase hex characters")
        }
        if (ownDeviceId != null && offer.deviceId == ownDeviceId) {
            return invalid(PairingError.SELF_PAIRING, "refusing to pair this device with itself")
        }

        val spki = try {
            Base64Url.decode(offer.publicKey)
        } catch (error: Exception) {
            return invalid(PairingError.INVALID_PUBLIC_KEY, "publicKey must be unpadded base64url")
        }
        val publicKey = try {
            KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(spki)) as? ECPublicKey
        } catch (error: Exception) {
            null
        } ?: return invalid(PairingError.INVALID_PUBLIC_KEY, "publicKey must be an X.509 EC public key")
        if (publicKey.params.curve.field.fieldSize != 256) {
            return invalid(PairingError.INVALID_PUBLIC_KEY, "publicKey must use P-256")
        }
        if (DeviceId.fromSpki(spki) != offer.deviceId) {
            return invalid(PairingError.INVALID_DEVICE_ID, "deviceId does not match the public key")
        }

        val nonce = try {
            Base64Url.decode(offer.nonce)
        } catch (error: Exception) {
            return invalid(PairingError.INVALID_NONCE, "nonce must be unpadded base64url")
        }
        if (nonce.size !in MIN_NONCE_BYTES..MAX_NONCE_BYTES) {
            return invalid(PairingError.INVALID_NONCE, "nonce must be 16-64 bytes")
        }

        if (offer.expiresAt <= nowEpochSeconds) {
            return invalid(PairingError.EXPIRED, "offer expired at ${offer.expiresAt}")
        }
        if (offer.expiresAt > nowEpochSeconds + MAX_FUTURE_SECONDS) {
            return invalid(PairingError.EXPIRY_TOO_FAR, "offer expiry is more than one hour away")
        }

        if (offer.capabilities.size > MAX_CAPABILITIES) {
            return invalid(PairingError.INVALID_CAPABILITY, "too many capabilities")
        }
        if (offer.capabilities.any { !capabilityShape.matches(it) }) {
            return invalid(PairingError.INVALID_CAPABILITY, "capabilities must be airdesk:// URIs")
        }
        if (offer.capabilities.toSet().size != offer.capabilities.size) {
            return invalid(PairingError.INVALID_CAPABILITY, "capabilities must not contain duplicates")
        }

        return PairingValidation.Valid(offer, spki)
    }

    private fun invalid(error: PairingError, message: String): PairingValidation =
        PairingValidation.Invalid(error, message)
}
