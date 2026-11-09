package com.airdesk.android.fabric

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class IrohFabricTransportAdapterTest {
    private val endpoint = IrohFabricEndpointInfo(
        endpointId = "endpoint-1",
        ticket = "ticket-1",
        directAddresses = listOf("192.0.2.10:4433"),
        relayUrl = null,
        relayPolicy = "direct-only",
    )

    @Test
    fun startMapsEndpointInfoAndDiagnostics() = runBlocking {
        val backend = FakePeerBackend(endpoint)
        val adapter = adapter(backend)

        val info = adapter.start()
        val diagnostics = adapter.diagnostics()

        assertEquals("endpoint-1", info.endpointId)
        assertEquals("ticket-1", info.ticket)
        assertEquals(listOf("192.0.2.10:4433"), info.directAddresses)
        assertEquals("direct-only", info.relayPolicy)
        assertEquals(info, diagnostics.endpoint)
        assertTrue(backend.started)
        adapter.close()
    }

    @Test
    fun endpointInfoFallsBackToBackendBeforeStart() = runBlocking {
        val backend = FakePeerBackend(endpoint)
        val adapter = adapter(backend)

        assertEquals("endpoint-1", adapter.endpointInfo()?.endpointId)
        assertFalse(backend.started)
        adapter.close()
    }

    @Test
    fun connectRegistersConnectionAndMapsAcceptedMessages() = runBlocking {
        val connectionBackend = FakeConnectionBackend(
            messages = flowOf(
                IrohFabricMessage.Reliable(IrohFabricChannel.RESOURCE, byteArrayOf(1, 2)),
                IrohFabricMessage.Movement(ByteArray(16) { 3 }),
            ),
        )
        val backend = FakePeerBackend(endpoint, connectionBackend)
        val adapter = adapter(backend)

        val connection = adapter.connect("ticket-1")
        val messages = connection.incoming.take(2).toList()
        val reliable = messages[0] as FabricIncoming.Reliable
        val movement = messages[1] as FabricIncoming.Movement

        assertArrayEquals(byteArrayOf(1, 2), reliable.payload)
        assertEquals(IrohFabricChannel.RESOURCE, reliable.channel)
        assertArrayEquals(ByteArray(16) { 3 }, movement.payload)
        assertEquals(1, adapter.diagnostics().connections.size)
        assertEquals("ticket-1", backend.lastTicket)
        adapter.close()
    }

    @Test
    fun invalidIncomingIsExposedAndRecorded() = runBlocking {
        val backend = FakePeerBackend(
            endpoint,
            FakeConnectionBackend(messages = flowOf(IrohFabricMessage.Invalid("bad frame"))),
        )
        val adapter = adapter(backend)
        val connection = adapter.connect("ticket-1")

        val invalid = connection.incoming.first() as FabricIncoming.Invalid

        assertEquals("bad frame", invalid.reason)
        assertEquals("bad frame", adapter.diagnostics().lastError)
        adapter.close()
    }

    @Test
    fun connectionDiagnosticsMapRelaySelection() = runBlocking {
        val backend = FakePeerBackend(
            endpoint,
            FakeConnectionBackend(
                diagnostics = IrohFabricConnectionDiagnostics(
                    remoteEndpointId = "peer-1",
                    paths = listOf(
                        IrohFabricPath("direct", "192.0.2.20:4433", false, true, false, 12u),
                        IrohFabricPath("relay", "relay.example:443", true, false, true, 48u),
                    ),
                ),
            ),
        )
        val adapter = adapter(backend)
        val connection = adapter.connect("ticket-1")

        val diagnostics = connection.diagnostics()

        assertEquals("peer-1", diagnostics.remoteEndpointId)
        assertEquals("relay", diagnostics.selectedPath?.id)
        assertTrue(diagnostics.isUsingRelay)
        assertEquals(48uL, diagnostics.paths[1].rttMillis)
        adapter.close()
    }

    @Test
    fun sendReliableRejectsMovementAndOversizedPayloads() = runBlocking {
        val connectionBackend = FakeConnectionBackend()
        val backend = FakePeerBackend(endpoint, connectionBackend)
        val adapter = adapter(backend)
        val connection = adapter.connect("ticket-1")

        assertThrows(IrohFabricException::class.java) {
            runBlocking { connection.sendReliable(IrohFabricChannel.MOVEMENT, ByteArray(1)) }
        }
        assertThrows(IrohFabricException::class.java) {
            runBlocking {
                connection.sendReliable(
                    IrohFabricChannel.RESOURCE,
                    ByteArray(IrohFabricFrame.MAXIMUM_RELIABLE_PAYLOAD + 1),
                )
            }
        }
        assertTrue(connectionBackend.sent.isEmpty())
        adapter.close()
    }

    @Test
    fun movementRequiresExactlySixteenBytes() = runBlocking {
        val connectionBackend = FakeConnectionBackend()
        val backend = FakePeerBackend(endpoint, connectionBackend)
        val adapter = adapter(backend)
        val connection = adapter.connect("ticket-1")

        assertThrows(IrohFabricException::class.java) {
            runBlocking { connection.sendMovement(ByteArray(15)) }
        }
        connection.sendMovement(ByteArray(16) { 7 })

        val sent = connectionBackend.sent.single()
        assertEquals(IrohFabricChannel.MOVEMENT, sent.first)
        assertArrayEquals(ByteArray(16) { 7 }, sent.second)
        adapter.close()
    }

    @Test
    fun closingConnectionUnregistersIt() = runBlocking {
        val backend = FakePeerBackend(endpoint, FakeConnectionBackend())
        val adapter = adapter(backend)
        val connection = adapter.connect("ticket-1")

        connection.close()

        assertTrue(adapter.diagnostics().connections.isEmpty())
        adapter.close()
    }

    @Test
    fun adapterRejectsUseAfterClose() = runBlocking {
        val backend = FakePeerBackend(endpoint, FakeConnectionBackend())
        val adapter = adapter(backend)

        adapter.close()

        assertThrows(IllegalStateException::class.java) {
            runBlocking { adapter.start() }
        }
        assertThrows(IllegalStateException::class.java) {
            runBlocking { adapter.connect("ticket-1") }
        }
        assertThrows(IllegalStateException::class.java) {
            runBlocking { adapter.accept() }
        }
        assertNull(adapter.endpointInfo())
        assertTrue(backend.closed)
    }

    @Test
    fun ownerCloseClosesConnection() = runBlocking {
        val connectionBackend = FakeConnectionBackend()
        val backend = FakePeerBackend(endpoint, connectionBackend)
        val adapter = adapter(backend)
        val connection = adapter.connect("ticket-1")

        adapter.close()

        assertTrue(connectionBackend.closed)
        assertTrue(adapter.diagnostics().connections.isEmpty())
    }

    @Test
    fun selectedPathAndRelayAreNullWithoutConnections() {
        val diagnostics = FabricTransportDiagnostics(endpoint = null, connections = emptyList())

        assertNull(diagnostics.lastError)
        assertTrue(diagnostics.connections.isEmpty())
    }

    private fun adapter(backend: FabricPeerBackend): IrohFabricTransportAdapter =
        IrohFabricTransportAdapter(
            backend = backend,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        )

    private class FakePeerBackend(
        private val info: IrohFabricEndpointInfo,
        private val connection: FakeConnectionBackend = FakeConnectionBackend(),
    ) : FabricPeerBackend {
        var started = false
        var closed = false
        var lastTicket: String? = null

        override suspend fun start(): IrohFabricEndpointInfo {
            started = true
            return info
        }

        override suspend fun connect(ticket: String): FabricConnectionBackend {
            lastTicket = ticket
            return connection
        }

        override suspend fun accept(): FabricConnectionBackend = connection

        override fun endpointInfo(): IrohFabricEndpointInfo = info

        override fun close() {
            closed = true
        }
    }

    private class FakeConnectionBackend(
        override val remoteEndpointId: String = "peer-1",
        override val messages: Flow<IrohFabricMessage> = emptyFlow(),
        private val diagnostics: IrohFabricConnectionDiagnostics =
            IrohFabricConnectionDiagnostics(remoteEndpointId, emptyList()),
    ) : FabricConnectionBackend {
        val sent = mutableListOf<Pair<IrohFabricChannel, ByteArray>>()
        var closed = false

        override suspend fun send(channel: IrohFabricChannel, payload: ByteArray) {
            sent += channel to payload
        }

        override fun diagnostics(): IrohFabricConnectionDiagnostics = diagnostics

        override fun close() {
            closed = true
        }
    }
}
