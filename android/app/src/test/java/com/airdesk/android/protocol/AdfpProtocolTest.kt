package com.airdesk.android.protocol

import AirDesk.Protocol.ChannelBindingKind
import AirDesk.Protocol.DeviceKind
import AirDesk.Protocol.Envelope
import AirDesk.Protocol.FabricPayload
import AirDesk.Protocol.SenderRole
import com.google.flatbuffers.FlatBufferBuilder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AdfpProtocolTest {
    private val deviceId = "ad-device:" + "a".repeat(64)
    private val nonce = ByteArray(32) { (it + 1).toByte() }
    private val expiresAt = 1_700_000_300_000UL
    private val identity = AdfpDeviceIdentity(
        version = 1u,
        kind = DeviceKind.phone,
        deviceId = deviceId,
        publicKey = "unpadded-base64url-spki",
        nonce = nonce,
        expiresAtEpochMillis = expiresAt,
        channelBindingKind = ChannelBindingKind.certificate_hash,
        channelBindingValue = "certificate-hash",
        capabilities = listOf("airdesk://display/output", "airdesk://health/status"),
    )
    private val offer = AdfpPairingOffer(
        identity = identity,
        offerNonce = nonce,
        expiresAtEpochMillis = expiresAt,
        channelBindingKind = ChannelBindingKind.certificate_hash,
        channelBindingValue = "certificate-hash",
        capabilities = listOf("airdesk://display/output", "airdesk://health/status"),
    )
    private val header = AdfpControlHeader(
        messageId = "message-1",
        senderDeviceId = deviceId,
        senderRole = SenderRole.agent,
        correlationId = "correlation-1",
        idempotencyKey = "idempotency-1",
        expiresAtEpochMillis = expiresAt,
        cancellationId = "cancel-1",
    )
    private val descriptor = AdfpCapabilityDescriptor(
        capUri = "airdesk://media/camera/capture",
        version = 1u,
        providerDeviceId = deviceId,
        availability = AirDesk.Protocol.Availability.restricted,
        authorization = AirDesk.Protocol.Authorization.ungranted,
        permissions = listOf("android.permission.CAMERA"),
        execution = "local",
        transport = "none",
        constraints = "{\"reason\":\"permission not granted\"}",
    )

    @Test
    fun pairingOfferRoundTripsHeaderIdentityAndOffer() {
        val bytes = AdfpProtocol.encodePairingOffer(header, offer)
        val decoded = AdfpProtocol.decode(bytes)

        assertEquals(AdfpProtocol.VERSION, decoded.version)
        assertEquals(header, decoded.header)
        val payload = decoded.payload as AdfpPayload.PairingOffer
        assertEquals(deviceId, payload.offer.identity.deviceId)
        assertEquals(identity.publicKey, payload.offer.identity.publicKey)
        assertEquals(identity.kind, payload.offer.identity.kind)
        assertEquals(expiresAt, payload.offer.expiresAtEpochMillis)
        assertEquals(offer.channelBindingKind, payload.offer.channelBindingKind)
        assertEquals(offer.channelBindingValue, payload.offer.channelBindingValue)
        assertArrayEquals(nonce, payload.offer.offerNonce)
        assertArrayEquals(nonce, payload.offer.identity.nonce)
        assertEquals(offer.capabilities, payload.offer.capabilities)
    }

    @Test
    fun deviceIdentityPayloadRoundTrips() {
        val bytes = AdfpProtocol.encodeDeviceIdentity(header, identity)
        val payload = AdfpProtocol.decode(bytes).payload as AdfpPayload.Identity

        assertEquals(deviceId, payload.identity.deviceId)
        assertEquals(identity.publicKey, payload.identity.publicKey)
        assertEquals(ChannelBindingKind.certificate_hash, payload.identity.channelBindingKind)
        assertEquals(identity.channelBindingValue, payload.identity.channelBindingValue)
        assertArrayEquals(nonce, payload.identity.nonce)
        assertEquals(identity.capabilities, payload.identity.capabilities)
    }

    @Test
    fun capabilityDescriptorPayloadRoundTrips() {
        val bytes = AdfpProtocol.encodeCapabilityDescriptor(header, descriptor)
        val decoded = AdfpProtocol.decode(bytes)
        val payload = decoded.payload as AdfpPayload.CapabilityDescriptor

        assertEquals(descriptor, payload.descriptor)
        assertEquals(header, decoded.header)
    }

    @Test
    fun rejectsEmptyEnvelope() {
        assertDecodeFails(AdfpError.EMPTY, ByteArray(0))
    }

    @Test
    fun rejectsOversizedEnvelope() {
        assertDecodeFails(AdfpError.OVERSIZED, ByteArray(AdfpProtocol.MAX_ENVELOPE_BYTES + 1))
    }

    @Test
    fun rejectsTruncatedEnvelope() {
        val valid = AdfpProtocol.encodePairingOffer(header, offer)
        assertDecodeFails(AdfpError.TRUNCATED, valid.copyOf(3))
        assertDecodeFailsAny(valid.copyOf(valid.size / 2))
    }

    @Test
    fun rejectsCorruptRootOffsetAsTruncated() {
        val valid = AdfpProtocol.encodePairingOffer(header, offer)
        val malformed = valid.copyOf()
        malformed[0] = 0x7f
        malformed[1] = 0x7f
        malformed[2] = 0x7f
        malformed[3] = 0x7f
        assertDecodeFails(AdfpError.TRUNCATED, malformed)
    }

    @Test
    fun rejectsMalformedEnvelopeWithoutHeader() {
        val builder = FlatBufferBuilder(256)
        val identityOffset = AirDesk.Protocol.DeviceIdentity.createDeviceIdentity(
            builder = builder,
            version = 1u,
            kind = DeviceKind.phone,
            deviceIdOffset = builder.createString(deviceId),
            publicKeyOffset = builder.createString(identity.publicKey),
            nonceOffset = builder.createByteVector(nonce),
            expiresAt = expiresAt,
            channelBindingKind = ChannelBindingKind.certificate_hash,
            channelBindingValueOffset = builder.createString("certificate-hash"),
            capabilitiesOffset = 0,
        )
        val offerOffset = AirDesk.Protocol.PairingOffer.createPairingOffer(
            builder = builder,
            identityOffset = identityOffset,
            offerNonceOffset = builder.createByteVector(nonce),
            expiresAt = expiresAt,
            channelBindingKind = ChannelBindingKind.certificate_hash,
            channelBindingValueOffset = builder.createString("certificate-hash"),
            capabilitiesOffset = 0,
        )
        Envelope.startEnvelope(builder)
        Envelope.addVersion(builder, 1u)
        Envelope.addFabricPayloadType(builder, FabricPayload.PairingOffer)
        Envelope.addFabricPayload(builder, offerOffset)
        val root = Envelope.endEnvelope(builder)
        Envelope.finishEnvelopeBuffer(builder, root)

        assertDecodeFails(AdfpError.MALFORMED, builder.sizedByteArray())
    }

    @Test
    fun rejectsWrongFileIdentifier() {
        val valid = AdfpProtocol.encodePairingOffer(header, offer)
        val wrong = valid.copyOf()
        wrong[4] = 'X'.code.toByte()
        assertDecodeFails(AdfpError.WRONG_FILE_IDENTIFIER, wrong)
    }

    @Test
    fun rejectsWrongEnvelopeVersion() {
        val wrongVersion = AdfpProtocol.encodePairingOffer(header, offer, version = 2u)
        assertDecodeFails(AdfpError.WRONG_VERSION, wrongVersion)
    }

    @Test
    fun sha256FingerprintMatchesEnvelopeBytes() {
        val bytes = AdfpProtocol.encodePairingOffer(header, offer)
        val expected = java.security.MessageDigest.getInstance("SHA-256").digest(bytes)
        assertArrayEquals(expected, AdfpProtocol.sha256(bytes))
        assertEquals(64, AdfpProtocol.sha256Hex(bytes).length)
        assertTrue(AdfpProtocol.sha256Hex(bytes).matches(Regex("^[0-9a-f]{64}$")))
    }

    private fun assertDecodeFails(expected: AdfpError, bytes: ByteArray) {
        try {
            AdfpProtocol.decode(bytes)
            fail("expected ${expected.name}")
        } catch (error: AdfpException) {
            assertEquals(expected, error.reason)
        }
    }

    private fun assertDecodeFailsAny(bytes: ByteArray) {
        try {
            AdfpProtocol.decode(bytes)
            fail("expected truncated envelope to be rejected")
        } catch (_: AdfpException) {
        }
    }
}
