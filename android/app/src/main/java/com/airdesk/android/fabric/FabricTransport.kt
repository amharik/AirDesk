package com.airdesk.android.fabric

import java.io.Closeable
import kotlinx.coroutines.flow.Flow

data class FabricTransportEndpointInfo(
    val endpointId: String,
    val ticket: String,
    val directAddresses: List<String>,
    val relayUrl: String?,
    val relayPolicy: String,
)

data class FabricTransportPath(
    val id: String,
    val remoteAddress: String,
    val isSelected: Boolean,
    val isDirectIp: Boolean,
    val isRelay: Boolean,
    val rttMillis: ULong,
)

data class FabricTransportConnectionDiagnostics(
    val remoteEndpointId: String,
    val paths: List<FabricTransportPath>,
) {
    val selectedPath: FabricTransportPath? get() = paths.firstOrNull { it.isSelected }
    val isUsingRelay: Boolean get() = selectedPath?.isRelay == true
}

data class FabricTransportDiagnostics(
    val endpoint: FabricTransportEndpointInfo?,
    val connections: List<FabricTransportConnectionDiagnostics>,
    val lastError: String? = null,
)

sealed interface FabricIncoming {
    data class Reliable(val channel: IrohFabricChannel, val payload: ByteArray) : FabricIncoming
    data class Movement(val payload: ByteArray) : FabricIncoming
    data class Invalid(val reason: String) : FabricIncoming
}

interface FabricConnection : Closeable {
    val remoteEndpointId: String
    val incoming: Flow<FabricIncoming>

    suspend fun sendReliable(channel: IrohFabricChannel, payload: ByteArray)

    suspend fun sendMovement(payload: ByteArray)

    fun diagnostics(): FabricTransportConnectionDiagnostics
}

interface FabricTransport : Closeable {
    suspend fun start(): FabricTransportEndpointInfo

    suspend fun connect(ticket: String): FabricConnection

    suspend fun accept(): FabricConnection

    fun endpointInfo(): FabricTransportEndpointInfo?

    fun diagnostics(): FabricTransportDiagnostics
}
