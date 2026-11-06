package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalOfferFactoryTest {
    @Test
    fun localOfferHasFiveMinuteExpiryAndValidProtocolShape() {
        val keyPair = KeyPairGenerator.getInstance("EC").apply {
            initialize(256)
        }.generateKeyPair()
        val spki = keyPair.public.encoded
        val identity = DeviceIdentity(
            alias = "airdesk.device.p256",
            deviceId = DeviceId.fromSpki(spki),
            displayName = "Test device",
            publicKeyBase64Url = Base64Url.encode(spki),
            publicKeySpki = spki,
            createdAtEpochMillis = 0,
            keyAlgorithm = "EC",
            privateKeyExtractable = false,
        )
        val now = 1_700_000_000L
        val local = LocalOfferFactory.create(
            identity = identity,
            capabilities = listOf("airdesk://display/output", "airdesk://health/status"),
            nowEpochSeconds = now,
        )

        assertEquals(PairingValidator.PROTOCOL, local.offer.protocol)
        assertEquals(PairingValidator.VERSION, local.offer.version)
        assertEquals(PairingValidator.KIND, local.offer.kind)
        assertEquals(identity.deviceId, local.offer.deviceId)
        assertEquals(now + 300, local.offer.expiresAt)
        assertEquals(32, Base64Url.decode(local.offer.nonce).size)
        assertTrue(PairingValidator.validate(local.json, now) is PairingValidation.Valid)
    }
}
