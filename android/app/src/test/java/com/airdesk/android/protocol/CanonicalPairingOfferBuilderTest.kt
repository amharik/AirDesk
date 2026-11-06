package com.airdesk.android.protocol

import AirDesk.Protocol.ChannelBindingKind
import com.airdesk.android.identity.DeviceId
import com.airdesk.android.identity.DeviceIdentity
import com.airdesk.android.pairing.PairingOffer
import com.airdesk.android.pairing.PairingValidator
import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class CanonicalPairingOfferBuilderTest {
    private val now = 1_700_000_000L
    private val keyPair = KeyPairGenerator.getInstance("EC").apply {
        initialize(256)
    }.generateKeyPair()
    private val spki = keyPair.public.encoded
    private val identity = DeviceIdentity(
        alias = "airdesk.device.p256",
        deviceId = DeviceId.fromSpki(spki),
        displayName = "Test device",
        publicKeyBase64Url = Base64Url.encode(spki),
        publicKeySpki = spki,
        createdAtEpochMillis = 0,
        keyAlgorithm = "EC",
        privateKeyExtractable = false,
    )
    private val offer = PairingOffer(
        protocol = PairingValidator.PROTOCOL,
        version = PairingValidator.VERSION,
        kind = PairingValidator.KIND,
        deviceId = identity.deviceId,
        publicKey = identity.publicKeyBase64Url,
        nonce = Base64Url.encode(ByteArray(32) { (it + 7).toByte() }),
        expiresAt = now + PairingValidator.OFFER_LIFETIME_SECONDS,
        capabilities = listOf("airdesk://display/output", "airdesk://health/status"),
    )

    @Test
    fun buildsDeterministicCanonicalBytesAndStableHash() {
        val first = CanonicalPairingOfferBuilder.build(identity, offer)
        val second = CanonicalPairingOfferBuilder.build(identity, offer)

        assertArrayEquals(first.bytes, second.bytes)
        assertEquals(first.sha256Hex, second.sha256Hex)
        assertEquals(AdfpProtocol.sha256Hex(first.bytes), first.sha256Hex)
        assertTrue(first.bytes.size < AdfpProtocol.MAX_ENVELOPE_BYTES)
        assertEquals(AdfpProtocol.VERSION, first.envelope.version)
    }

    @Test
    fun canonicalOfferCarriesCertificateHashBindingAndIdentity() {
        val canonical = CanonicalPairingOfferBuilder.build(identity, offer)
        val payload = canonical.envelope.payload as AdfpPayload.PairingOffer

        assertEquals(ChannelBindingKind.certificate_hash, payload.offer.channelBindingKind)
        assertEquals(AdfpProtocol.sha256Hex(spki), payload.offer.channelBindingValue)
        assertEquals(ChannelBindingKind.certificate_hash, payload.offer.identity.channelBindingKind)
        assertEquals(identity.deviceId, payload.offer.identity.deviceId)
        assertEquals(identity.publicKeyBase64Url, payload.offer.identity.publicKey)
        assertEquals((now + PairingValidator.OFFER_LIFETIME_SECONDS) * 1000L, payload.offer.expiresAtEpochMillis.toLong())
        assertEquals(offer.capabilities, payload.offer.capabilities)
        assertEquals(identity.deviceId, canonical.envelope.header.senderDeviceId)
    }

    @Test
    fun selfTestDecodesAndReencodesCanonicalEnvelope() {
        val canonical = CanonicalPairingOfferBuilder.build(identity, offer)
        val result = AdfpProtocol.selfTest(canonical)

        assertTrue(result.detail, result.ok)
    }

    @Test
    fun rejectsCanonicalOfferLargerThanOneMebibyte() {
        val hugeOffer = offer.copy(
            capabilities = List(6000) { index -> "airdesk://oversized/$index/" + "x".repeat(180) },
        )
        try {
            CanonicalPairingOfferBuilder.build(identity, hugeOffer)
            fail("expected oversized canonical offer to be rejected")
        } catch (error: AdfpException) {
            assertEquals(AdfpError.OVERSIZED, error.reason)
        }
    }
}
