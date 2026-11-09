package com.airdesk.android.pairing

import com.airdesk.android.fabric.IrohFabricChannel
import com.airdesk.android.fabric.IrohFabricConnection
import com.airdesk.android.fabric.IrohFabricMessage
import com.airdesk.android.fabric.IrohFabricPeer
import java.io.Closeable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class AdPairIrohTransport(
    private val session: AdPairWireSession,
    private val peer: IrohFabricPeer,
) : Closeable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var connection: IrohFabricConnection? = null
    private var receiveJob: Job? = null

    var lastError: String? = null
        private set

    val state: AdPairWireSession.State get() = session.state
    val shortAuthenticationString: String? get() = session.shortAuthenticationString
    val remoteEndpointId: String? get() = connection?.remoteEndpointId

    suspend fun connect(
        ticket: String,
        expectedEndpointId: String? = null,
        initialMessage: ByteArray? = null,
        onUpdate: (AdPairIrohTransport) -> Unit = {},
    ) {
        val connected = peer.connect(ticket)
        if (expectedEndpointId != null && connected.remoteEndpointId != expectedEndpointId) {
            connected.close()
            throw AdPairCoordinatorException(
                AdPairCoordinatorError.BINDING_MISMATCH,
                "connected Iroh endpoint does not match the pairing binding",
            )
        }
        attach(connected, initialMessage, onUpdate)
    }

    suspend fun accept(
        initialMessage: ByteArray? = null,
        onUpdate: (AdPairIrohTransport) -> Unit = {},
    ): Boolean {
        val next = peer.incomingConnections.first()
        attach(next, initialMessage, onUpdate)
        return true
    }

    fun confirmShortAuthenticationString(entered: String): AdPairKeySchedule.Keys =
        session.confirmShortAuthenticationString(entered)

    override fun close() {
        receiveJob?.cancel()
        receiveJob = null
        connection?.close()
        connection = null
        scope.cancel()
    }

    private fun attach(
        connected: IrohFabricConnection,
        initialMessage: ByteArray?,
        onUpdate: (AdPairIrohTransport) -> Unit,
    ) {
        check(connection == null) { "pairing Iroh connection is already attached" }
        connection = connected
        receiveJob = scope.launch {
            try {
                if (initialMessage != null) {
                    connected.send(IrohFabricChannel.PAIRING, initialMessage)
                }
                connected.messages.collect { message ->
                    when (message) {
                        is IrohFabricMessage.Reliable -> {
                            if (message.channel == IrohFabricChannel.PAIRING) {
                                session.receive(message.payload)?.let {
                                    connected.send(IrohFabricChannel.PAIRING, it)
                                }
                            }
                        }
                        is IrohFabricMessage.Invalid -> lastError = message.reason
                        is IrohFabricMessage.Movement -> Unit
                    }
                    onUpdate(this@AdPairIrohTransport)
                }
            } catch (error: Exception) {
                lastError = error.message ?: error.javaClass.simpleName
                onUpdate(this@AdPairIrohTransport)
            }
        }
    }
}
