package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AdPairCoordinatorTest {
    private val binding = AdPairChannelBinding("certificate-hash", "ab".repeat(32))
    private val initiatorKeys = keyPair()
    private val responderKeys = keyPair()

    @Test
    fun completesPinPairingWithMatchingKeysAndSignatures() {
        val store = MemoryStore()
        val registry = PeerRegistry(store)
        val initiator = coordinator(initiatorKeys, AdPairCoordinator.Role.INITIATOR, registry)
        val responder = coordinator(responderKeys, AdPairCoordinator.Role.RESPONDER, registry)

        val start = initiator.startInitiator(
            mode = AdPairCodec.MODE_PIN,
            channelBinding = binding,
            capabilities = listOf("display"),
            endpointHint = "iroh://initiator",
        )
        val joined = responder.joinResponder(
            code = start.challenge.serialized,
            pin = start.challenge.pin,
            capabilities = listOf("clipboard-read"),
            endpointHint = "iroh://responder",
        )
        val shareP = initiator.acceptResponse(joined.responseData)
        val response = responder.respond(shareP)
        val initiatorResult = initiator.finishInitiator(
            responderShare = response.share,
            responderConfirmation = response.confirmation,
            responderSignature = response.signature,
        )
        val responderResult = responder.finishResponder(
            initiatorConfirmation = initiatorResult.initiatorConfirmation,
            initiatorSignature = initiatorResult.initiatorSignature,
        )

        assertEquals(AdPairCoordinator.State.COMPLETED, initiator.state)
        assertEquals(AdPairCoordinator.State.COMPLETED, responder.state)
        assertArrayEquals(initiatorResult.transcript, responderResult.transcript)
        assertArrayEquals(initiatorResult.transcriptHash, responderResult.transcriptHash)
        assertEquals(initiatorResult.shortAuthenticationString, responderResult.shortAuthenticationString)
        assertArrayEquals(
            initiatorResult.sessionKeys.transport.bytes,
            responderResult.sessionKeys.transport.bytes,
        )
        assertEquals(listOf("clipboard-read", "display"), initiatorResult.capabilities)
        assertEquals(2, registry.all().size)
        assertTrue(verify(initiatorKeys, initiatorResult.transcript, initiatorResult.initiatorSignature))
        assertTrue(verify(responderKeys, initiatorResult.transcript, initiatorResult.responderSignature))
    }

    @Test
    fun completesQrSecretPairing() {
        val initiator = coordinator(initiatorKeys, AdPairCoordinator.Role.INITIATOR, null)
        val responder = coordinator(responderKeys, AdPairCoordinator.Role.RESPONDER, null)
        val start = initiator.startInitiator(AdPairCodec.MODE_QR_SECRET, binding)
        val joined = responder.joinResponder(start.challenge.serialized)
        val shareP = initiator.acceptResponse(joined.responseData)
        val response = responder.respond(shareP)
        val initiatorResult = initiator.finishInitiator(
            response.share,
            response.confirmation,
            response.signature,
        )
        val responderResult = responder.finishResponder(
            initiatorResult.initiatorConfirmation,
            initiatorResult.initiatorSignature,
        )
        assertArrayEquals(initiatorResult.transcriptHash, responderResult.transcriptHash)
        assertArrayEquals(initiatorResult.sessionKeys.transport.bytes, responderResult.sessionKeys.transport.bytes)
    }

    @Test
    fun wrongPinFailsClosed() {
        val initiator = coordinator(initiatorKeys, AdPairCoordinator.Role.INITIATOR, null)
        val responder = coordinator(responderKeys, AdPairCoordinator.Role.RESPONDER, null)
        val start = initiator.startInitiator(AdPairCodec.MODE_PIN, binding)
        val wrongPin = if (start.challenge.pin == "000000") "000001" else "000000"
        val joined = responder.joinResponder(start.challenge.serialized, pin = wrongPin)
        val shareP = initiator.acceptResponse(joined.responseData)
        val response = responder.respond(shareP)
        try {
            initiator.finishInitiator(response.share, response.confirmation, response.signature)
            fail("expected confirmation mismatch")
        } catch (error: Spake2PlusP256.Spake2PlusException) {
            assertEquals(Spake2PlusP256.ErrorCode.CONFIRMATION_MISMATCH, error.code)
        }
    }

    @Test
    fun rejectsSelfPairingAndTamperedResponse() {
        val self = coordinator(initiatorKeys, AdPairCoordinator.Role.RESPONDER, null)
        try {
            self.joinResponder(
                AdPairCodec.createPinChallenge(
                    AdPairOffer(
                        deviceId = deviceId(initiatorKeys),
                        publicKey = publicKey(initiatorKeys),
                        nonce = com.airdesk.android.util.Base64Url.encode(ByteArray(32) { 7 }),
                        expiresAt = 2_000_000,
                        channelBinding = binding,
                    ),
                    1_000_000,
                ).serialized,
                pin = "123456",
            )
            fail("expected self pairing rejection")
        } catch (error: AdPairCodeException) {
            assertEquals(AdPairCodeErrorCode.INVALID_CODE, error.code)
        }

        val initiator = coordinator(initiatorKeys, AdPairCoordinator.Role.INITIATOR, null)
        val responder = coordinator(responderKeys, AdPairCoordinator.Role.RESPONDER, null)
        val start = initiator.startInitiator(AdPairCodec.MODE_QR_SECRET, binding)
        val joined = responder.joinResponder(start.challenge.serialized)
        val tampered = joined.responseData.toString(Charsets.UTF_8).replace("\"type\":\"response\"", "\"type\":\"offer\"")
        expectCoordinator(AdPairCoordinatorError.UNEXPECTED_TYPE) {
            initiator.acceptResponse(tampered.toByteArray(Charsets.UTF_8))
        }
    }

    @Test
    fun rejectsInvalidBinding() {
        val initiator = coordinator(initiatorKeys, AdPairCoordinator.Role.INITIATOR, null)
        expectCoordinator(AdPairCoordinatorError.INVALID_BINDING) {
            initiator.startInitiator(
                AdPairCodec.MODE_QR_SECRET,
                AdPairChannelBinding("certificate-hash", "not-a-hash"),
            )
        }
    }

    private fun coordinator(
        keys: KeyPair,
        role: AdPairCoordinator.Role,
        registry: PeerRegistry?,
    ): AdPairCoordinator {
        var counter = 1
        return AdPairCoordinator(
            role = role,
            deviceId = deviceId(keys),
            publicKey = publicKey(keys),
            signer = AdPairSigner { data -> sign(keys, data) },
            verifier = AdPairSignatureVerifier { key, data, signature -> verify(key, data, signature) },
            registry = registry,
            peerDisplayLabel = "test peer",
            now = { 1_000_000L },
            randomBytes = { count -> ByteArray(count) { (counter++ and 0xff).toByte() } },
        )
    }

    private fun keyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()

    private fun deviceId(keys: KeyPair): String = DeviceId.fromSpki(keys.public.encoded)

    private fun publicKey(keys: KeyPair): String =
        com.airdesk.android.util.Base64Url.encode(keys.public.encoded)

    private fun sign(keys: KeyPair, data: ByteArray): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(keys.private)
            update(data)
            sign()
        }

    private fun verify(keys: KeyPair, data: ByteArray, signature: ByteArray): Boolean =
        verify(publicKey(keys), data, signature)

    private fun verify(publicKey: String, data: ByteArray, signature: ByteArray): Boolean = try {
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(
                java.security.KeyFactory.getInstance("EC").generatePublic(
                    java.security.spec.X509EncodedKeySpec(
                        com.airdesk.android.util.Base64Url.decode(publicKey),
                    ),
                ),
            )
            update(data)
            verify(signature)
        }
    } catch (error: Exception) {
        false
    }

    private fun expectCode(code: AdPairCoordinatorError, block: () -> Unit) {
        try {
            block()
            fail("expected ${code.name}")
        } catch (error: AdPairCoordinatorException) {
            assertEquals(code, error.code)
        }
    }

    private fun expectCoordinator(code: AdPairCoordinatorError, block: () -> Unit) =
        expectCode(code, block)

    private class MemoryStore : KeyValueStore {
        private val values = mutableMapOf<String, String>()
        override fun getString(key: String): String? = values[key]
        override fun putString(key: String, value: String) {
            values[key] = value
        }
    }
}
