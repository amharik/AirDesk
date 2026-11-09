package com.airdesk.android.fabric

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

internal interface FabricPeerBackend {
    suspend fun start(): IrohFabricEndpointInfo
    suspend fun connect(ticket: String): FabricConnectionBackend
    suspend fun accept(): FabricConnectionBackend
    fun endpointInfo(): IrohFabricEndpointInfo
    fun close()
}

internal interface FabricConnectionBackend {
    val remoteEndpointId: String
    val messages: Flow<IrohFabricMessage>
    suspend fun send(channel: IrohFabricChannel, payload: ByteArray)
    fun diagnostics(): IrohFabricConnectionDiagnostics
    fun close()
}

internal class IrohFabricPeerBackend(
    private val peer: IrohFabricPeer,
) : FabricPeerBackend {
    override suspend fun start(): IrohFabricEndpointInfo = peer.start()

    override suspend fun connect(ticket: String): FabricConnectionBackend =
        IrohFabricConnectionBackend(peer.connect(ticket))

    override suspend fun accept(): FabricConnectionBackend =
        IrohFabricConnectionBackend(peer.incomingConnections.first())

    override fun endpointInfo(): IrohFabricEndpointInfo = peer.endpointInfo()

    override fun close() = peer.close()
}

internal class IrohFabricConnectionBackend(
    private val connection: IrohFabricConnection,
) : FabricConnectionBackend {
    override val remoteEndpointId: String get() = connection.remoteEndpointId
    override val messages: Flow<IrohFabricMessage> get() = connection.messages

    override suspend fun send(channel: IrohFabricChannel, payload: ByteArray) =
        connection.send(channel, payload)

    override fun diagnostics(): IrohFabricConnectionDiagnostics = connection.diagnostics()

    override fun close() = connection.close()
}

class IrohFabricTransportAdapter internal constructor(
    private val backend: FabricPeerBackend,
    private val scope: CoroutineScope,
) : FabricTransport {
    constructor(peer: IrohFabricPeer) : this(
        backend = IrohFabricPeerBackend(peer),
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
    )

    private val connections = ConcurrentHashMap<String, IrohFabricConnectionAdapter>()
    private var endpoint: FabricTransportEndpointInfo? = null

    @Volatile
    private var lastError: String? = null

    @Volatile
    private var closed = false

    override suspend fun start(): FabricTransportEndpointInfo {
        check(!closed) { "fabric transport is closed" }
        val info = backend.start().toTransportInfo()
        endpoint = info
        lastError = null
        return info
    }

    override suspend fun connect(ticket: String): FabricConnection {
        check(!closed) { "fabric transport is closed" }
        return register(IrohFabricConnectionAdapter(backend.connect(ticket), this))
    }

    override suspend fun accept(): FabricConnection {
        check(!closed) { "fabric transport is closed" }
        return register(IrohFabricConnectionAdapter(backend.accept(), this))
    }

    override fun endpointInfo(): FabricTransportEndpointInfo? {
        if (closed) return null
        endpoint?.let { return it }
        return runCatching { backend.endpointInfo().toTransportInfo() }
            .onSuccess { endpoint = it }
            .getOrNull()
    }

    override fun diagnostics(): FabricTransportDiagnostics = FabricTransportDiagnostics(
        endpoint = endpointInfo(),
        connections = connections.values
            .map { it.diagnostics() }
            .sortedBy { it.remoteEndpointId },
        lastError = lastError,
    )

    override fun close() {
        if (closed) return
        closed = true
        connections.values.forEach { it.close() }
        connections.clear()
        backend.close()
        endpoint = null
        scope.cancel()
    }

    internal fun register(connection: IrohFabricConnectionAdapter): FabricConnection {
        if (closed) {
            connection.close()
            throw IrohFabricException("fabric transport is closed")
        }
        connections[connection.remoteEndpointId] = connection
        return connection
    }

    internal fun unregister(connection: IrohFabricConnectionAdapter) {
        connections.remove(connection.remoteEndpointId)
    }

    internal fun recordError(reason: String) {
        lastError = reason
    }

    private fun IrohFabricEndpointInfo.toTransportInfo(): FabricTransportEndpointInfo =
        FabricTransportEndpointInfo(
            endpointId = endpointId,
            ticket = ticket,
            directAddresses = directAddresses,
            relayUrl = relayUrl,
            relayPolicy = relayPolicy,
        )
}

internal class IrohFabricConnectionAdapter(
    private val backend: FabricConnectionBackend,
    private val owner: IrohFabricTransportAdapter? = null,
) : FabricConnection {
    override val remoteEndpointId: String = backend.remoteEndpointId

    override val incoming: Flow<FabricIncoming> = backend.messages.map { message ->
        when (message) {
            is IrohFabricMessage.Reliable -> FabricIncoming.Reliable(message.channel, message.payload)
            is IrohFabricMessage.Movement -> FabricIncoming.Movement(message.payload)
            is IrohFabricMessage.Invalid -> {
                owner?.recordError(message.reason)
                FabricIncoming.Invalid(message.reason)
            }
        }
    }

    override suspend fun sendReliable(channel: IrohFabricChannel, payload: ByteArray) {
        if (!channel.isReliable) {
            throw IrohFabricException("movement must use datagrams")
        }
        if (payload.size > IrohFabricFrame.MAXIMUM_RELIABLE_PAYLOAD) {
            throw IrohFabricException("reliable frame exceeds the 1 MiB limit")
        }
        backend.send(channel, payload)
    }

    override suspend fun sendMovement(payload: ByteArray) {
        if (payload.size != IrohFabricFrame.MOVEMENT_PAYLOAD_SIZE) {
            throw IrohFabricException("movement datagrams must be exactly 16 bytes")
        }
        backend.send(IrohFabricChannel.MOVEMENT, payload)
    }

    override fun diagnostics(): FabricTransportConnectionDiagnostics {
        val diagnostics = backend.diagnostics()
        return FabricTransportConnectionDiagnostics(
            remoteEndpointId = diagnostics.remoteEndpointId,
            paths = diagnostics.paths.map {
                FabricTransportPath(
                    id = it.id,
                    remoteAddress = it.remoteAddress,
                    isSelected = it.isSelected,
                    isDirectIp = it.isDirectIp,
                    isRelay = it.isRelay,
                    rttMillis = it.rttMillis,
                )
            },
        )
    }

    override fun close() {
        backend.close()
        owner?.unregister(this)
    }
}
