package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyPair
import java.security.KeyPairGenerator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.encodeToString

class PairingValidatorTest {
    private val now = 1_700_000_000L
    private val keyPair: KeyPair = KeyPairGenerator.getInstance("EC").apply {
        initialize(256)
    }.generateKeyPair()
    private val spki = keyPair.public.encoded
    private val deviceId = DeviceId.fromSpki(spki)
    private val publicKey = Base64Url.encode(spki)

    @Test
    fun acceptsValidOffer() {
        val result = PairingValidator.validate(validJson(), now)
        assertTrue(result is PairingValidation.Valid)
        assertEquals(deviceId, (result as PairingValidation.Valid).offer.deviceId)
    }

    @Test
    fun rejectsExpiredOffer() {
        val result = PairingValidator.validate(validJson(expiresAt = now), now)
        assertRejected(result, PairingError.EXPIRED)
    }

    @Test
    fun rejectsOfferExpiryTooFarAway() {
        val result = PairingValidator.validate(validJson(expiresAt = now + 7200), now)
        assertRejected(result, PairingError.EXPIRY_TOO_FAR)
    }

    @Test
    fun rejectsWrongKind() {
        val result = PairingValidator.validate(validJson(kind = "pairing-response"), now)
        assertRejected(result, PairingError.WRONG_KIND)
    }

    @Test
    fun rejectsWrongVersion() {
        val result = PairingValidator.validate(validJson(version = "0.2"), now)
        assertRejected(result, PairingError.WRONG_VERSION)
    }

    @Test
    fun rejectsWrongProtocol() {
        val result = PairingValidator.validate(validJson(protocol = "other"), now)
        assertRejected(result, PairingError.WRONG_PROTOCOL)
    }

    @Test
    fun rejectsMalformedJson() {
        val result = PairingValidator.validate("{not-json", now)
        assertRejected(result, PairingError.MALFORMED)
    }

    @Test
    fun rejectsUnknownField() {
        val text = validJson().replaceFirst("\"protocol\"", "\"unknown\":true,\n  \"protocol\"")
        val result = PairingValidator.validate(text, now)
        assertRejected(result, PairingError.MALFORMED)
    }

    @Test
    fun rejectsInvalidPublicKey() {
        val result = PairingValidator.validate(
            validJson(publicKey = Base64Url.encode(byteArrayOf(1, 2, 3))),
            now,
        )
        assertRejected(result, PairingError.INVALID_PUBLIC_KEY)
    }

    @Test
    fun rejectsDeviceIdThatDoesNotMatchPublicKey() {
        val otherKey = KeyPairGenerator.getInstance("EC").apply {
            initialize(256)
        }.generateKeyPair().public.encoded
        val result = PairingValidator.validate(
            validJson(publicKey = Base64Url.encode(otherKey)),
            now,
        )
        assertRejected(result, PairingError.INVALID_DEVICE_ID)
    }

    @Test
    fun rejectsMalformedDeviceId() {
        val result = PairingValidator.validate(validJson(deviceId = "ad-device:abc"), now)
        assertRejected(result, PairingError.INVALID_DEVICE_ID)
    }

    @Test
    fun rejectsSelfPairing() {
        val result = PairingValidator.validate(validJson(), now, ownDeviceId = deviceId)
        assertRejected(result, PairingError.SELF_PAIRING)
    }

    @Test
    fun rejectsShortNonce() {
        val result = PairingValidator.validate(
            validJson(nonce = Base64Url.encode(byteArrayOf(1, 2, 3, 4))),
            now,
        )
        assertRejected(result, PairingError.INVALID_NONCE)
    }

    @Test
    fun rejectsInvalidCapabilityUri() {
        val result = PairingValidator.validate(
            validJson(capabilities = listOf("https://example.test/cap")),
            now,
        )
        assertRejected(result, PairingError.INVALID_CAPABILITY)
    }

    private fun validJson(
        protocol: String = "adfp",
        version: String = "0.1",
        kind: String = "pairing-offer",
        deviceId: String = this.deviceId,
        publicKey: String = this.publicKey,
        nonce: String = Base64Url.encode(ByteArray(32) { it.toByte() }),
        expiresAt: Long = now + 300,
        capabilities: List<String> = listOf("airdesk://health/status"),
    ): String = PairingJson.pretty.encodeToString(
        PairingOffer(
            protocol = protocol,
            version = version,
            kind = kind,
            deviceId = deviceId,
            publicKey = publicKey,
            nonce = nonce,
            expiresAt = expiresAt,
            capabilities = capabilities,
        ),
    )

    private fun assertRejected(result: PairingValidation, error: PairingError) {
        assertTrue(result is PairingValidation.Invalid)
        assertEquals(error, (result as PairingValidation.Invalid).error)
    }
}
