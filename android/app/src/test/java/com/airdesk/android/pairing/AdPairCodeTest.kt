package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AdPairCodeTest {
    private val now = 1_700_000_000_000L
    private val keyPair = KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()
    private val spki = keyPair.public.encoded
    private val deviceId = DeviceId.fromSpki(spki)
    private val channelBinding = AdPairChannelBinding(
        kind = "certificate-hash",
        value = "ab".repeat(32),
    )

    private fun offer(
        expiresAt: Long = now + 60_000,
        nonce: ByteArray = ByteArray(32) { (it + 1).toByte() },
    ) = AdPairOffer(
        deviceId = deviceId,
        publicKey = Base64Url.encode(spki),
        nonce = Base64Url.encode(nonce),
        expiresAt = expiresAt,
        capabilities = listOf("display", "clipboard-read"),
        channelBinding = channelBinding,
    )

    private fun deterministicBytes(): (Int) -> ByteArray {
        var counter = 1
        return { count -> ByteArray(count) { (counter++ and 0xff).toByte() } }
    }

    @Test
    fun passwordRegistrationMatchesCrossPlatformVector() {
        val salt = ByteArray(32) { it.toByte() }
        val registration = Spake2PlusRegistration.create(
            password = "correct horse battery staple",
            salt = salt,
            idProver = "client".toByteArray(),
            idVerifier = "server".toByteArray(),
        )

        assertEquals(
            "b0ed4ba1a99c347e760babddd3847a9bbec14679eff683f533b4b30c6f51d942",
            DeviceId.hexLowercase(registration.w0),
        )
        assertEquals(
            "2617ed2ba8d280416fdf1a179ec1a6a103cf1309867dfeb90153bf88c7b26acd",
            DeviceId.hexLowercase(registration.w1),
        )
        assertEquals(65, registration.L.size)
        assertEquals(0x04.toByte(), registration.L[0])
        assertArrayEquals(Spake2PlusRegistration.registrationRecord(registration.w1), registration.L)
    }

    @Test
    fun pinChallengeRoundTripsAndDerivesRegistration() {
        val challenge = AdPairCodec.createPinChallenge(offer(), now, deterministicBytes())
        assertEquals(6, challenge.pin?.length)
        assertTrue(challenge.pin!!.all { it in '0'..'9' })
        assertNull(challenge.secret)

        val parsed = AdPairCodec.parse(challenge.serialized, now, AdPairCodec.MODE_PIN)
        assertEquals(AdPairCodec.MODE_PIN, parsed.mode)
        assertNull(parsed.secret)

        val registration = AdPairCodec.deriveRegistration(
            code = parsed,
            pin = challenge.pin,
            initiatorDeviceId = "ad-device:" + "1".repeat(64),
            responderDeviceId = deviceId,
        )
        assertEquals(32, registration.w0.size)
        assertEquals(32, registration.w1.size)
    }

    @Test
    fun qrChallengeRoundTripsAndDerivesRegistration() {
        val challenge = AdPairCodec.createQrSecretChallenge(offer(), now, deterministicBytes())
        assertNull(challenge.pin)
        assertEquals(32, challenge.secret?.size)

        val parsed = AdPairCodec.parse(challenge.serialized, now, AdPairCodec.MODE_QR_SECRET)
        assertEquals(AdPairCodec.MODE_QR_SECRET, parsed.mode)
        assertNotEquals(challenge.secret, null)

        val registration = AdPairCodec.deriveRegistration(
            code = parsed,
            pin = null,
            initiatorDeviceId = "ad-device:" + "1".repeat(64),
            responderDeviceId = deviceId,
        )
        assertEquals(32, registration.w1.size)
    }

    @Test
    fun parseRejectsWrongModeExpiredAndTamperedDevice() {
        val challenge = AdPairCodec.createPinChallenge(offer(), now, deterministicBytes())
        assertCode(AdPairCodeErrorCode.INVALID_MODE) {
            AdPairCodec.parse(challenge.serialized, now, AdPairCodec.MODE_QR_SECRET)
        }
        assertCode(AdPairCodeErrorCode.EXPIRED_CODE) {
            AdPairCodec.parse(challenge.serialized, now + 60_000)
        }

        val codeJson = String(Base64Url.decode(challenge.serialized.removePrefix(AdPairCodec.PREFIX)))
        val tampered = AdPairCodec.PREFIX + Base64Url.encode(
            codeJson.replace(deviceId, "ad-device:" + "0".repeat(64)).toByteArray(),
        )
        assertCode(AdPairCodeErrorCode.INVALID_CODE) {
            AdPairCodec.parse(tampered, now)
        }
    }

    @Test
    fun parseRejectsUnknownFields() {
        val challenge = AdPairCodec.createPinChallenge(offer(), now, deterministicBytes())
        val json = String(Base64Url.decode(challenge.serialized.removePrefix(AdPairCodec.PREFIX)))
        val withUnknown = AdPairCodec.PREFIX + Base64Url.encode(
            json.replaceFirst("{", "{\"unexpected\":true,").toByteArray(),
        )
        assertCode(AdPairCodeErrorCode.MALFORMED_CODE) {
            AdPairCodec.parse(withUnknown, now)
        }
    }

    @Test
    fun pinGuardLocksAfterMaximumFailures() {
        var clock = now
        val guard = AdPairPinAttemptGuard(maxAttempts = 2, now = { clock })
        val expiresAt = now + 60_000
        guard.assertAllowed("pair", expiresAt)
        assertEquals(1, guard.recordFailure("pair", expiresAt))
        assertEquals(0, guard.recordFailure("pair", expiresAt))
        assertCode(AdPairCodeErrorCode.PIN_LOCKED) {
            guard.assertAllowed("pair", expiresAt)
        }
        clock = expiresAt + 1
        guard.assertAllowed("pair", expiresAt + 60_000)
    }

    private fun assertCode(expected: AdPairCodeErrorCode, block: () -> Unit) {
        try {
            block()
            fail("expected $expected")
        } catch (error: AdPairCodeException) {
            assertEquals(expected, error.code)
        }
    }
}
