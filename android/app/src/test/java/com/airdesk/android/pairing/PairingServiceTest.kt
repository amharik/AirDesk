package com.airdesk.android.pairing

import com.airdesk.android.identity.DeviceId
import com.airdesk.android.util.Base64Url
import java.security.KeyPairGenerator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.serialization.encodeToString

class PairingServiceTest {
    private val now = 1_700_000_000L
    private val keyPair = KeyPairGenerator.getInstance("EC").apply {
        initialize(256)
    }.generateKeyPair()
    private val spki = keyPair.public.encoded
    private val peerDeviceId = DeviceId.fromSpki(spki)
    private val offerJson = PairingJson.pretty.encodeToString(
        PairingOffer(
            protocol = PairingValidator.PROTOCOL,
            version = PairingValidator.VERSION,
            kind = PairingValidator.KIND,
            deviceId = peerDeviceId,
            publicKey = Base64Url.encode(spki),
            nonce = Base64Url.encode(ByteArray(32) { (it + 1).toByte() }),
            expiresAt = now + 300,
            capabilities = listOf("airdesk://health/status"),
        ),
    )

    @Test
    fun acceptsValidOfferAndPersistsPeer() {
        val fixture = fixture()
        val result = fixture.service.accept(offerJson, ownDeviceId = null, label = "Test peer")

        assertTrue(result is PairingResult.Accepted)
        val peers = fixture.registry.all()
        assertEquals(1, peers.size)
        assertEquals(peerDeviceId, peers.single().deviceId)
        assertEquals("Test peer", peers.single().displayName)
        assertTrue(fixture.nonces.contains((result as PairingResult.Accepted).offer.nonce))
    }

    @Test
    fun rejectsReplayedOfferNonce() {
        val fixture = fixture()
        assertTrue(fixture.service.accept(offerJson, ownDeviceId = null) is PairingResult.Accepted)

        val replay = fixture.service.accept(offerJson, ownDeviceId = null)
        assertTrue(replay is PairingResult.Rejected)
        assertEquals(PairingError.REPLAYED, (replay as PairingResult.Rejected).error)
        assertEquals(1, fixture.registry.all().size)
    }

    @Test
    fun expiredOfferIsRejectedAndNotRecorded() {
        val fixture = fixture(clock = { now + 301 })
        val result = fixture.service.accept(offerJson, ownDeviceId = null)

        assertTrue(result is PairingResult.Rejected)
        assertEquals(PairingError.EXPIRED, (result as PairingResult.Rejected).error)
        assertTrue(fixture.registry.all().isEmpty())
    }

    @Test
    fun revokingPeerMarksRecordAndKeepsHistory() {
        val fixture = fixture()
        fixture.service.accept(offerJson, ownDeviceId = null)

        assertTrue(fixture.registry.revoke(peerDeviceId, now + 10))
        val peer = fixture.registry.find(peerDeviceId)
        assertNotNull(peer)
        assertTrue(peer!!.revoked)
        assertEquals(now + 10, peer.revokedAtEpochSeconds)
        assertTrue(fixture.registry.active().isEmpty())
    }

    @Test
    fun revokingUnknownPeerReturnsFalse() {
        val fixture = fixture()
        assertFalse(fixture.registry.revoke("ad-device:" + "0".repeat(64), now))
    }

    private fun fixture(clock: () -> Long = { now }): Fixture {
        val store = MapStore()
        val registry = PeerRegistry(store)
        val nonces = NonceStore(store)
        return Fixture(
            store = store,
            registry = registry,
            nonces = nonces,
            service = PairingService(registry, nonces, clock),
        )
    }

    private data class Fixture(
        val store: KeyValueStore,
        val registry: PeerRegistry,
        val nonces: NonceStore,
        val service: PairingService,
    )

    private class MapStore : KeyValueStore {
        private val values = mutableMapOf<String, String>()
        override fun getString(key: String): String? = values[key]
        override fun putString(key: String, value: String) {
            values[key] = value
        }
    }
}
