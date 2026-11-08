package com.airdesk.android.pairing

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString

class PeerRegistry(
    private val store: KeyValueStore,
) {
    fun all(): List<PeerRecord> {
        val raw = store.getString(KEY_PEERS) ?: return emptyList()
        return runCatching {
            PairingJson.strict.decodeFromString<List<PeerRecord>>(raw)
        }.getOrDefault(emptyList())
    }

    fun active(): List<PeerRecord> = all().filterNot { it.revoked }

    fun find(deviceId: String): PeerRecord? = all().firstOrNull { it.deviceId == deviceId }

    fun upsert(peer: PeerRecord): PeerRecord {
        val peers = all().toMutableList()
        val index = peers.indexOfFirst { it.deviceId == peer.deviceId }
        if (index >= 0) {
            peers[index] = peer
        } else {
            peers.add(peer)
        }
        save(peers)
        return peer
    }

    fun trust(deviceId: String): Boolean {
        val peers = all().toMutableList()
        val index = peers.indexOfFirst { it.deviceId == deviceId }
        if (index < 0 || peers[index].revoked) return false
        peers[index] = peers[index].copy(trusted = true)
        save(peers)
        return true
    }

    fun revoke(deviceId: String, nowEpochSeconds: Long): Boolean {
        val peers = all().toMutableList()
        val index = peers.indexOfFirst { it.deviceId == deviceId }
        if (index < 0) return false
        peers[index] = peers[index].copy(
            revoked = true,
            revokedAtEpochSeconds = nowEpochSeconds,
        )
        save(peers)
        return true
    }

    private fun save(peers: List<PeerRecord>) {
        store.putString(KEY_PEERS, PairingJson.pretty.encodeToString(peers))
    }

    companion object {
        private const val KEY_PEERS = "peers"
    }
}

class NonceStore(
    private val store: KeyValueStore,
) {
    fun contains(nonce: String): Boolean = read().contains(nonce)

    fun consume(nonce: String) {
        val nonces = read().toMutableList()
        if (nonce in nonces) return
        nonces.add(nonce)
        store.putString(KEY_NONCES, PairingJson.pretty.encodeToString(nonces.takeLast(MAX_NONCES)))
    }

    private fun read(): List<String> {
        val raw = store.getString(KEY_NONCES) ?: return emptyList()
        return runCatching {
            PairingJson.strict.decodeFromString<List<String>>(raw)
        }.getOrDefault(emptyList())
    }

    companion object {
        private const val KEY_NONCES = "pairing_consumed_nonces"
        private const val MAX_NONCES = 256
    }
}
