package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AdPairWireSessionTest {
    private val binding = AdPairChannelBinding("certificate-hash", "cd".repeat(32))
    private val hostKeys = keyPair()
    private val controllerKeys = keyPair()

    @Test
    fun drivesFullWireExchangeAndSasGate() {
        val registry = PeerRegistry(MemoryStore())
        val host = AdPairWireSession(
            AdPairWireSession.Role.HOST,
            coordinator(hostKeys, AdPairCoordinator.Role.INITIATOR, registry),
        )
        val controller = AdPairWireSession(
            AdPairWireSession.Role.CONTROLLER,
            coordinator(controllerKeys, AdPairCoordinator.Role.RESPONDER, registry),
        )
        val challenge = host.startHost(AdPairCodec.MODE_PIN, binding, capabilities = listOf("display"))
        val response = controller.join(challenge.serialized, challenge.pin, capabilities = listOf("clipboard-read"))
        val share = host.receive(response)
        assertNotNull(share)
        val verifierResponse = controller.receive(share!!)
        assertNotNull(verifierResponse)
        val initiatorFinish = host.receive(verifierResponse!!)
        assertNotNull(initiatorFinish)
        val responderFinish = controller.receive(initiatorFinish!!)
        assertNotNull(responderFinish)
        assertEquals(AdPairWireSession.State.AWAITING_USER_VERIFICATION, host.state)
        assertEquals(AdPairWireSession.State.AWAITING_USER_VERIFICATION, controller.state)
        assertEquals(host.shortAuthenticationString, controller.shortAuthenticationString)
        assertTrue(host.shortAuthenticationString!!.matches(Regex("^[0-9]{6}$")))
        assertEquals(null, host.receive(responderFinish!!))

        val hostKeysResult = host.confirmShortAuthenticationString(host.shortAuthenticationString!!)
        val controllerKeysResult = controller.confirmShortAuthenticationString(controller.shortAuthenticationString!!)
        assertArrayEquals(hostKeysResult.transport.bytes, controllerKeysResult.transport.bytes)
        assertEquals(AdPairWireSession.State.COMPLETED, host.state)
        assertEquals(AdPairWireSession.State.COMPLETED, controller.state)
        assertTrue(registry.all().all { it.trusted })
    }

    @Test
    fun rejectsMismatchedSasAndOutOfOrderMessages() {
        val host = AdPairWireSession(
            AdPairWireSession.Role.HOST,
            coordinator(hostKeys, AdPairCoordinator.Role.INITIATOR),
        )
        val wrong = if (host.shortAuthenticationString == "000000") "000001" else "000000"
        try {
            host.receive(PairingWire.encode(PairingWire.response(ByteArray(8) { 1 })))
            fail("expected invalid state")
        } catch (error: AdPairWireException) {
            assertEquals(AdPairWireSession.State.FAILED, host.state)
        }

        val host2 = AdPairWireSession(
            AdPairWireSession.Role.HOST,
            coordinator(hostKeys, AdPairCoordinator.Role.INITIATOR),
        )
        val controller = AdPairWireSession(
            AdPairWireSession.Role.CONTROLLER,
            coordinator(controllerKeys, AdPairCoordinator.Role.RESPONDER),
        )
        val challenge = host2.startHost(AdPairCodec.MODE_QR_SECRET, binding)
        val response = controller.join(challenge.serialized)
        val share = host2.receive(response)!!
        val verifierResponse = controller.receive(share)!!
        val initiatorFinish = host2.receive(verifierResponse)!!
        controller.receive(initiatorFinish)!!
        try {
            host2.confirmShortAuthenticationString(wrong)
            fail("expected SAS mismatch")
        } catch (error: AdPairWireException) {
            assertEquals(AdPairWireSession.State.FAILED, host2.state)
        }
    }

    private fun coordinator(
        keys: KeyPair,
        role: AdPairCoordinator.Role,
        registry: PeerRegistry? = null,
    ): AdPairCoordinator {
        var counter = 1
        return AdPairCoordinator(
            role = role,
            deviceId = DeviceId.fromSpki(keys.public.encoded),
            publicKey = Base64Url.encode(keys.public.encoded),
            signer = AdPairSigner { data -> sign(keys, data) },
            verifier = AdPairSignatureVerifier { key, data, signature -> verify(key, data, signature) },
            registry = registry,
            now = { 5_000_000L },
            randomBytes = { count -> ByteArray(count) { (counter++ and 0xff).toByte() } },
        )
    }

    private class MemoryStore : KeyValueStore {
        private val values = mutableMapOf<String, String>()
        override fun getString(key: String): String? = values[key]
        override fun putString(key: String, value: String) {
            values[key] = value
        }
    }

    private fun keyPair(): KeyPair =
        KeyPairGenerator.getInstance("EC").apply { initialize(256) }.generateKeyPair()

    private fun sign(keys: KeyPair, data: ByteArray): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(keys.private)
            update(data)
            sign()
        }

    private fun verify(publicKey: String, data: ByteArray, signature: ByteArray): Boolean = try {
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(
                java.security.KeyFactory.getInstance("EC").generatePublic(
                    java.security.spec.X509EncodedKeySpec(Base64Url.decode(publicKey)),
                ),
            )
            update(data)
            verify(signature)
        }
    } catch (error: Exception) {
        false
    }
}
