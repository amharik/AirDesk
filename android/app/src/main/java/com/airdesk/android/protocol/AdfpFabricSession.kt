package com.airdesk.android.protocol

import AirDesk.Protocol.ControlHeader as FlatControlHeader
import AirDesk.Protocol.ControlMessage as FlatControlMessage
import AirDesk.Protocol.DisplaySession as FlatDisplaySession
import AirDesk.Protocol.Envelope as FlatEnvelope
import AirDesk.Protocol.FabricPayload as FlatFabricPayload
import AirDesk.Protocol.InputEvent as FlatInputEvent
import AirDesk.Protocol.MessagePayload as FlatMessagePayload
import AirDesk.Protocol.Qid as FlatQid
import AirDesk.Protocol.ResourceAttach as FlatResourceAttach
import AirDesk.Protocol.ResourceAttachResult as FlatResourceAttachResult
import AirDesk.Protocol.ResourceClunk as FlatResourceClunk
import AirDesk.Protocol.ResourceClunkResult as FlatResourceClunkResult
import AirDesk.Protocol.ResourceCompoundRequest as FlatResourceCompoundRequest
import AirDesk.Protocol.ResourceCompoundResult as FlatResourceCompoundResult
import AirDesk.Protocol.ResourceOpen as FlatResourceOpen
import AirDesk.Protocol.ResourceOpenResult as FlatResourceOpenResult
import AirDesk.Protocol.ResourceRead as FlatResourceRead
import AirDesk.Protocol.ResourceReadResult as FlatResourceReadResult
import AirDesk.Protocol.ResourceRpc as FlatResourceRpc
import AirDesk.Protocol.ResourceRpcPayload as FlatResourceRpcPayload
import AirDesk.Protocol.ResourceStat as FlatResourceStat
import AirDesk.Protocol.ResourceStatRequest as FlatResourceStatRequest
import AirDesk.Protocol.ResourceStatResult as FlatResourceStatResult
import AirDesk.Protocol.ResourceWalk as FlatResourceWalk
import AirDesk.Protocol.ResourceWalkResult as FlatResourceWalkResult
import AirDesk.Protocol.ResourceWstat as FlatResourceWstat
import AirDesk.Protocol.ResourceWstatResult as FlatResourceWstatResult
import AirDesk.Protocol.ResourceWrite as FlatResourceWrite
import AirDesk.Protocol.ResourceWriteResult as FlatResourceWriteResult
import AirDesk.Protocol.SyncRecord as FlatSyncRecord
import AirDesk.Protocol.Viewport as FlatViewport
import com.airdesk.android.fabric.FabricIncoming
import com.airdesk.android.fabric.IrohFabricChannel
import com.google.flatbuffers.FlatBufferBuilder
import java.nio.ByteBuffer
import java.nio.ByteOrder

data class AdfpInputEvent(
    val version: UInt = 1u,
    val type: UByte,
    val sessionId: String,
    val generation: UInt = 0u,
    val seq: UInt = 0u,
    val timestamp: ULong = 0u,
    val x: Float = 0f,
    val y: Float = 0f,
    val dx: Float = 0f,
    val dy: Float = 0f,
    val button: UByte = 0u,
    val clickCount: UByte = 1u,
    val key: String? = null,
    val code: String? = null,
    val modifiers: List<String> = emptyList(),
    val text: String? = null,
    val width: Float = 0f,
    val height: Float = 0f,
    val target: String? = null,
)

data class AdfpControlMessage(
    val version: UInt = 1u,
    val type: UByte,
    val sessionId: String,
    val generation: UInt = 0u,
    val seq: UInt = 0u,
    val timestamp: ULong = 0u,
    val appearance: String? = null,
    val message: String? = null,
    val action: String? = null,
    val width: Float = 0f,
    val height: Float = 0f,
    val code: String? = null,
)

data class AdfpViewport(
    val width: UInt,
    val height: UInt,
    val scale: Float = 1f,
    val orientation: String? = null,
)

data class AdfpDisplaySession(
    val workspaceId: String?,
    val displayId: String?,
    val viewport: AdfpViewport?,
    val profile: String?,
    val generation: UInt = 0u,
)

data class AdfpSyncRecord(
    val workspaceId: String?,
    val recordId: String?,
    val deviceId: String?,
    val userId: String?,
    val seq: ULong,
    val mergeClass: UByte,
    val payloadHash: ByteArray,
)

data class AdfpQid(
    val type: UByte,
    val version: UInt,
    val path: ULong,
)

data class AdfpResourceStat(
    val qid: AdfpQid,
    val mode: UInt,
    val length: ULong,
    val name: String?,
    val modifiedAtEpochMillis: ULong,
)

data class AdfpBlobHandle(
    val version: UInt = 1u,
    val algorithm: UByte = 1u,
    val digest: ByteArray,
    val length: ULong,
    val expiresAtEpochMillis: ULong = 0uL,
)

data class AdfpCompoundRequest(
    val requestId: ULong,
    val fid: UInt,
    val newFid: UInt,
    val wnames: List<String>,
    val openMode: UByte = 0u,
    val readOffset: ULong = 0uL,
    val readCount: UInt = 0u,
    val clunk: Boolean = true,
)

data class AdfpCompoundResult(
    val requestId: ULong,
    val status: UByte = 0u,
    val qid: AdfpQid? = null,
    val iounit: UInt = 65_536u,
    val data: ByteArray = ByteArray(0),
    val blob: AdfpBlobHandle? = null,
    val stat: AdfpResourceStat? = null,
    val clunkStatus: UByte = 0u,
)

sealed interface AdfpResourcePayload {
    data class Attach(
        val fid: UInt,
        val afid: UInt,
        val uname: String?,
        val aname: String?,
        val coseToken: ByteArray,
    ) : AdfpResourcePayload

    data class AttachResult(val fid: UInt, val qid: AdfpQid) : AdfpResourcePayload

    data class Walk(val fid: UInt, val newFid: UInt, val wnames: List<String>) : AdfpResourcePayload

    data class WalkResult(val wqids: List<AdfpQid>) : AdfpResourcePayload

    data class Open(val fid: UInt, val mode: UByte) : AdfpResourcePayload

    data class OpenResult(val qid: AdfpQid, val iounit: UInt) : AdfpResourcePayload

    data class Read(val fid: UInt, val offset: ULong, val count: UInt) : AdfpResourcePayload

    data class ReadResult(
        val data: ByteArray,
        val blob: AdfpBlobHandle? = null,
    ) : AdfpResourcePayload

    data class Write(val fid: UInt, val offset: ULong, val data: ByteArray) : AdfpResourcePayload

    data class WriteResult(val count: UInt) : AdfpResourcePayload

    data class Clunk(val fid: UInt) : AdfpResourcePayload

    data class ClunkResult(val status: UByte) : AdfpResourcePayload

    data class StatRequest(val fid: UInt) : AdfpResourcePayload

    data class StatResult(val stat: AdfpResourceStat) : AdfpResourcePayload

    data class Wstat(val fid: UInt, val stat: AdfpResourceStat) : AdfpResourcePayload

    data class WstatResult(val status: UByte) : AdfpResourcePayload

    data class CompoundRequest(val request: AdfpCompoundRequest) : AdfpResourcePayload

    data class CompoundResult(val result: AdfpCompoundResult) : AdfpResourcePayload
}

data class AdfpResourceRpc(val payload: AdfpResourcePayload) {
    val payloadType: UByte
        get() = when (payload) {
            is AdfpResourcePayload.Attach -> FlatResourceRpcPayload.ResourceAttach
            is AdfpResourcePayload.AttachResult -> FlatResourceRpcPayload.ResourceAttachResult
            is AdfpResourcePayload.Walk -> FlatResourceRpcPayload.ResourceWalk
            is AdfpResourcePayload.WalkResult -> FlatResourceRpcPayload.ResourceWalkResult
            is AdfpResourcePayload.Open -> FlatResourceRpcPayload.ResourceOpen
            is AdfpResourcePayload.OpenResult -> FlatResourceRpcPayload.ResourceOpenResult
            is AdfpResourcePayload.Read -> FlatResourceRpcPayload.ResourceRead
            is AdfpResourcePayload.ReadResult -> FlatResourceRpcPayload.ResourceReadResult
            is AdfpResourcePayload.Write -> FlatResourceRpcPayload.ResourceWrite
            is AdfpResourcePayload.WriteResult -> FlatResourceRpcPayload.ResourceWriteResult
            is AdfpResourcePayload.Clunk -> FlatResourceRpcPayload.ResourceClunk
            is AdfpResourcePayload.ClunkResult -> FlatResourceRpcPayload.ResourceClunkResult
            is AdfpResourcePayload.StatRequest -> FlatResourceRpcPayload.ResourceStatRequest
            is AdfpResourcePayload.StatResult -> FlatResourceRpcPayload.ResourceStatResult
            is AdfpResourcePayload.Wstat -> FlatResourceRpcPayload.ResourceWstat
            is AdfpResourcePayload.WstatResult -> FlatResourceRpcPayload.ResourceWstatResult
            is AdfpResourcePayload.CompoundRequest ->
                FlatResourceRpcPayload.ResourceCompoundRequest
            is AdfpResourcePayload.CompoundResult ->
                FlatResourceRpcPayload.ResourceCompoundResult
        }

    val opCode: UInt
        get() = when (payload) {
            is AdfpResourcePayload.Attach -> 100u
            is AdfpResourcePayload.AttachResult -> 101u
            is AdfpResourcePayload.Walk -> 102u
            is AdfpResourcePayload.WalkResult -> 103u
            is AdfpResourcePayload.Open -> 104u
            is AdfpResourcePayload.OpenResult -> 105u
            is AdfpResourcePayload.Read -> 106u
            is AdfpResourcePayload.ReadResult -> 107u
            is AdfpResourcePayload.Write -> 108u
            is AdfpResourcePayload.WriteResult -> 109u
            is AdfpResourcePayload.Clunk -> 110u
            is AdfpResourcePayload.ClunkResult -> 111u
            is AdfpResourcePayload.StatRequest -> 112u
            is AdfpResourcePayload.StatResult -> 113u
            is AdfpResourcePayload.Wstat -> 114u
            is AdfpResourcePayload.WstatResult -> 115u
            is AdfpResourcePayload.CompoundRequest -> 116u
            is AdfpResourcePayload.CompoundResult -> 117u
        }
}

sealed interface AdfpSessionPayload {
    data class Identity(val identity: AdfpDeviceIdentity) : AdfpSessionPayload
    data class CapabilityDescriptor(val descriptor: AdfpCapabilityDescriptor) : AdfpSessionPayload
    data class Input(val event: AdfpInputEvent) : AdfpSessionPayload
    data class Display(val session: AdfpDisplaySession) : AdfpSessionPayload
    data class Resource(val rpc: AdfpResourceRpc) : AdfpSessionPayload
    data class Sync(val record: AdfpSyncRecord) : AdfpSessionPayload
    data class Control(val message: AdfpControlMessage) : AdfpSessionPayload
}

class AdfpFabricSession {
    fun channelFor(payload: AdfpSessionPayload): IrohFabricChannel = when (payload) {
        is AdfpSessionPayload.Identity,
        is AdfpSessionPayload.CapabilityDescriptor,
        is AdfpSessionPayload.Control,
        -> IrohFabricChannel.CONTROL
        is AdfpSessionPayload.Input -> IrohFabricChannel.INPUT_EDGES
        is AdfpSessionPayload.Display -> IrohFabricChannel.DISPLAY
        is AdfpSessionPayload.Resource -> IrohFabricChannel.RESOURCE
        is AdfpSessionPayload.Sync -> IrohFabricChannel.SYNC
    }

    fun encode(payload: AdfpSessionPayload, header: AdfpControlHeader): ByteArray =
        encode(channelFor(payload), payload, header)

    fun encode(
        channel: IrohFabricChannel,
        payload: AdfpSessionPayload,
        header: AdfpControlHeader,
    ): ByteArray {
        requireAllowed(channel, payload)
        val bytes = when (payload) {
            is AdfpSessionPayload.Identity ->
                AdfpProtocol.encodeDeviceIdentity(header, payload.identity)
            is AdfpSessionPayload.CapabilityDescriptor ->
                AdfpProtocol.encodeCapabilityDescriptor(header, payload.descriptor)
            is AdfpSessionPayload.Input -> encodeInput(header, payload.event)
            is AdfpSessionPayload.Control -> encodeControl(header, payload.message)
            is AdfpSessionPayload.Display -> encodeDisplay(header, payload.session)
            is AdfpSessionPayload.Sync -> encodeSync(header, payload.record)
            is AdfpSessionPayload.Resource -> encodeResource(header, payload.rpc)
        }
        if (bytes.size > AdfpProtocol.MAX_ENVELOPE_BYTES) {
            throw AdfpException(
                AdfpError.OVERSIZED,
                "ADFP envelope is ${bytes.size} bytes; limit is ${AdfpProtocol.MAX_ENVELOPE_BYTES}",
            )
        }
        return bytes
    }

    fun decodeHeader(
        bytes: ByteArray,
        nowEpochMillis: ULong = System.currentTimeMillis().toULong(),
    ): AdfpControlHeader {
        val envelope = decodeEnvelope(bytes, nowEpochMillis)
        val header = envelope.header
            ?: throw AdfpException(AdfpError.MALFORMED, "ADFP envelope is missing a ControlHeader")
        return readHeader(header)
    }

    fun decode(
        channel: IrohFabricChannel,
        bytes: ByteArray,
        nowEpochMillis: ULong = System.currentTimeMillis().toULong(),
    ): AdfpSessionPayload {
        val envelope = decodeEnvelope(bytes, nowEpochMillis)
        val payload = try {
            when {
                envelope.fabricPayloadType == FlatFabricPayload.DeviceIdentity -> {
                    val decoded = AdfpProtocol.decode(bytes)
                    val identity = (decoded.payload as? AdfpPayload.Identity)?.identity
                        ?: throw AdfpException(AdfpError.MALFORMED, "DeviceIdentity payload is missing")
                    AdfpSessionPayload.Identity(identity)
                }
                envelope.fabricPayloadType == FlatFabricPayload.CapabilityDescriptor -> {
                    val decoded = AdfpProtocol.decode(bytes)
                    val descriptor = (decoded.payload as? AdfpPayload.CapabilityDescriptor)?.descriptor
                        ?: throw AdfpException(
                            AdfpError.MALFORMED,
                            "CapabilityDescriptor payload is missing",
                        )
                    AdfpSessionPayload.CapabilityDescriptor(descriptor)
                }
                envelope.payloadType == FlatMessagePayload.InputEvent -> {
                    val input = envelope.payload(FlatInputEvent()) as? FlatInputEvent
                        ?: throw AdfpException(AdfpError.MALFORMED, "InputEvent payload is missing")
                    AdfpSessionPayload.Input(readInput(input))
                }
                envelope.payloadType == FlatMessagePayload.ControlMessage -> {
                    val control = envelope.payload(FlatControlMessage()) as? FlatControlMessage
                        ?: throw AdfpException(AdfpError.MALFORMED, "ControlMessage payload is missing")
                    AdfpSessionPayload.Control(readControl(control))
                }
                envelope.fabricPayloadType == FlatFabricPayload.DisplaySession -> {
                    val display = envelope.fabricPayload(FlatDisplaySession()) as? FlatDisplaySession
                        ?: throw AdfpException(AdfpError.MALFORMED, "DisplaySession payload is missing")
                    AdfpSessionPayload.Display(readDisplay(display))
                }
                envelope.fabricPayloadType == FlatFabricPayload.SyncRecord -> {
                    val sync = envelope.fabricPayload(FlatSyncRecord()) as? FlatSyncRecord
                        ?: throw AdfpException(AdfpError.MALFORMED, "SyncRecord payload is missing")
                    AdfpSessionPayload.Sync(readSync(sync))
                }
                envelope.fabricPayloadType == FlatFabricPayload.ResourceRpc -> {
                    val rpc = envelope.fabricPayload(FlatResourceRpc()) as? FlatResourceRpc
                        ?: throw AdfpException(AdfpError.MALFORMED, "ResourceRpc payload is missing")
                    AdfpSessionPayload.Resource(readResource(rpc))
                }
                else -> throw AdfpException(
                    AdfpError.UNSUPPORTED_PAYLOAD,
                    "unsupported ADFP payload type " +
                        "${envelope.fabricPayloadType}/${envelope.payloadType}",
                )
            }
        } catch (error: AdfpException) {
            throw error
        } catch (error: Exception) {
            throw AdfpException(AdfpError.MALFORMED, "malformed ADFP payload", error)
        } catch (error: AssertionError) {
            throw AdfpException(AdfpError.MALFORMED, "malformed ADFP payload", error)
        }
        requireAllowed(channel, payload)
        return payload
    }

    fun dispatch(incoming: FabricIncoming): AdfpSessionPayload? = when (incoming) {
        is FabricIncoming.Reliable -> decode(incoming.channel, incoming.payload)
        is FabricIncoming.Movement -> null
        is FabricIncoming.Invalid -> throw AdfpException(
            AdfpError.MALFORMED,
            "invalid fabric frame: ${incoming.reason}",
        )
    }

    private fun requireAllowed(channel: IrohFabricChannel, payload: AdfpSessionPayload) {
        val allowed = when (payload) {
            is AdfpSessionPayload.Identity,
            is AdfpSessionPayload.CapabilityDescriptor,
            -> channel == IrohFabricChannel.CONTROL
            is AdfpSessionPayload.Control ->
                channel == IrohFabricChannel.CONTROL || channel == IrohFabricChannel.DISPLAY
            is AdfpSessionPayload.Input -> channel == IrohFabricChannel.INPUT_EDGES
            is AdfpSessionPayload.Display -> channel == IrohFabricChannel.DISPLAY
            is AdfpSessionPayload.Resource -> channel == IrohFabricChannel.RESOURCE
            is AdfpSessionPayload.Sync -> channel == IrohFabricChannel.SYNC
        }
        if (!allowed) {
            throw AdfpException(
                AdfpError.UNSUPPORTED_PAYLOAD,
                "${payload::class.simpleName} is not valid on channel ${channel.name}",
            )
        }
    }

    private fun encodeInput(header: AdfpControlHeader, event: AdfpInputEvent): ByteArray {
        val builder = FlatBufferBuilder(1024)
        val sessionIdOffset = builder.createString(event.sessionId)
        val keyOffset = event.key.stringOffset(builder)
        val codeOffset = event.code.stringOffset(builder)
        val textOffset = event.text.stringOffset(builder)
        val targetOffset = event.target.stringOffset(builder)
        val modifierOffsets = event.modifiers.map { builder.createString(it) }.toIntArray()
        val modifiersOffset = if (modifierOffsets.isEmpty()) {
            0
        } else {
            FlatInputEvent.createModifiersVector(builder, modifierOffsets)
        }
        val payloadOffset = FlatInputEvent.createInputEvent(
            builder = builder,
            version = event.version,
            type = event.type,
            sessionIdOffset = sessionIdOffset,
            generation = event.generation,
            seq = event.seq,
            timestamp = event.timestamp,
            x = event.x,
            y = event.y,
            dx = event.dx,
            dy = event.dy,
            button = event.button,
            clickCount = event.clickCount,
            keyOffset = keyOffset,
            codeOffset = codeOffset,
            modifiersOffset = modifiersOffset,
            textOffset = textOffset,
            width = event.width,
            height = event.height,
            targetOffset = targetOffset,
        )
        val headerOffset = buildHeader(builder, header)
        FlatEnvelope.startEnvelope(builder)
        FlatEnvelope.addVersion(builder, AdfpProtocol.VERSION)
        FlatEnvelope.addHeader(builder, headerOffset)
        FlatEnvelope.addPayloadType(builder, FlatMessagePayload.InputEvent)
        FlatEnvelope.addPayload(builder, payloadOffset)
        return finish(builder)
    }

    private fun encodeControl(header: AdfpControlHeader, message: AdfpControlMessage): ByteArray {
        val builder = FlatBufferBuilder(1024)
        val payloadOffset = FlatControlMessage.createControlMessage(
            builder = builder,
            version = message.version,
            type = message.type,
            sessionIdOffset = builder.createString(message.sessionId),
            generation = message.generation,
            seq = message.seq,
            timestamp = message.timestamp,
            appearanceOffset = message.appearance.stringOffset(builder),
            messageOffset = message.message.stringOffset(builder),
            actionOffset = message.action.stringOffset(builder),
            width = message.width,
            height = message.height,
            codeOffset = message.code.stringOffset(builder),
        )
        val headerOffset = buildHeader(builder, header)
        FlatEnvelope.startEnvelope(builder)
        FlatEnvelope.addVersion(builder, AdfpProtocol.VERSION)
        FlatEnvelope.addHeader(builder, headerOffset)
        FlatEnvelope.addPayloadType(builder, FlatMessagePayload.ControlMessage)
        FlatEnvelope.addPayload(builder, payloadOffset)
        return finish(builder)
    }

    private fun encodeDisplay(header: AdfpControlHeader, session: AdfpDisplaySession): ByteArray {
        val builder = FlatBufferBuilder(1024)
        val viewportOffset = session.viewport?.let {
            FlatViewport.createViewport(
                builder = builder,
                width = it.width,
                height = it.height,
                scale = it.scale,
                orientationOffset = it.orientation.stringOffset(builder),
            )
        } ?: 0
        val payloadOffset = FlatDisplaySession.createDisplaySession(
            builder = builder,
            workspaceIdOffset = session.workspaceId.stringOffset(builder),
            displayIdOffset = session.displayId.stringOffset(builder),
            viewportOffset = viewportOffset,
            profileOffset = session.profile.stringOffset(builder),
            generation = session.generation,
        )
        val headerOffset = buildHeader(builder, header)
        FlatEnvelope.startEnvelope(builder)
        FlatEnvelope.addVersion(builder, AdfpProtocol.VERSION)
        FlatEnvelope.addHeader(builder, headerOffset)
        FlatEnvelope.addFabricPayloadType(builder, FlatFabricPayload.DisplaySession)
        FlatEnvelope.addFabricPayload(builder, payloadOffset)
        return finish(builder)
    }

    private fun encodeSync(header: AdfpControlHeader, record: AdfpSyncRecord): ByteArray {
        val builder = FlatBufferBuilder(1024)
        val hashOffset = if (record.payloadHash.isEmpty()) {
            0
        } else {
            builder.startVector(1, record.payloadHash.size, 1)
            for (index in record.payloadHash.indices.reversed()) {
                builder.addByte(record.payloadHash[index])
            }
            builder.endVector()
        }
        val payloadOffset = FlatSyncRecord.createSyncRecord(
            builder = builder,
            workspaceIdOffset = record.workspaceId.stringOffset(builder),
            recordIdOffset = record.recordId.stringOffset(builder),
            deviceIdOffset = record.deviceId.stringOffset(builder),
            userIdOffset = record.userId.stringOffset(builder),
            seq = record.seq,
            mergeClass = record.mergeClass,
            payloadHashOffset = hashOffset,
        )
        val headerOffset = buildHeader(builder, header)
        FlatEnvelope.startEnvelope(builder)
        FlatEnvelope.addVersion(builder, AdfpProtocol.VERSION)
        FlatEnvelope.addHeader(builder, headerOffset)
        FlatEnvelope.addFabricPayloadType(builder, FlatFabricPayload.SyncRecord)
        FlatEnvelope.addFabricPayload(builder, payloadOffset)
        return finish(builder)
    }

    private fun encodeResource(header: AdfpControlHeader, rpc: AdfpResourceRpc): ByteArray {
        val builder = FlatBufferBuilder(1024)
        val payloadOffset = when (val payload = rpc.payload) {
            is AdfpResourcePayload.Attach -> FlatResourceAttach.createResourceAttach(
                builder = builder,
                fid = payload.fid,
                afid = payload.afid,
                unameOffset = payload.uname.stringOffset(builder),
                anameOffset = payload.aname.stringOffset(builder),
                coseTokenOffset = builder.createByteVector(payload.coseToken),
            )
            is AdfpResourcePayload.AttachResult -> {
                FlatResourceAttachResult.startResourceAttachResult(builder)
                FlatResourceAttachResult.addFid(builder, payload.fid)
                FlatResourceAttachResult.addQid(builder, payload.qid.write(builder))
                FlatResourceAttachResult.endResourceAttachResult(builder)
            }
            is AdfpResourcePayload.Walk -> {
                val nameOffsets = payload.wnames.map { builder.createString(it) }.toIntArray()
                val namesOffset = if (nameOffsets.isEmpty()) {
                    0
                } else {
                    FlatResourceWalk.createWnamesVector(builder, nameOffsets)
                }
                FlatResourceWalk.createResourceWalk(builder, payload.fid, payload.newFid, namesOffset)
            }
            is AdfpResourcePayload.WalkResult -> {
                val qidsOffset = if (payload.wqids.isEmpty()) {
                    0
                } else {
                    FlatResourceWalkResult.startWqidsVector(builder, payload.wqids.size)
                    for (qid in payload.wqids.asReversed()) {
                        qid.write(builder)
                    }
                    builder.endVector()
                }
                FlatResourceWalkResult.createResourceWalkResult(builder, qidsOffset)
            }
            is AdfpResourcePayload.Open ->
                FlatResourceOpen.createResourceOpen(builder, payload.fid, payload.mode)
            is AdfpResourcePayload.OpenResult -> {
                FlatResourceOpenResult.startResourceOpenResult(builder)
                FlatResourceOpenResult.addQid(builder, payload.qid.write(builder))
                FlatResourceOpenResult.addIounit(builder, payload.iounit)
                FlatResourceOpenResult.endResourceOpenResult(builder)
            }
            is AdfpResourcePayload.Read ->
                FlatResourceRead.createResourceRead(builder, payload.fid, payload.offset, payload.count)
            is AdfpResourcePayload.ReadResult ->
                ResourceCompoundCodec.writeReadResult(builder, payload)
            is AdfpResourcePayload.Write -> {
                val dataOffset = payload.data.writeByteVector(builder)
                FlatResourceWrite.createResourceWrite(
                    builder,
                    payload.fid,
                    payload.offset,
                    dataOffset,
                )
            }
            is AdfpResourcePayload.WriteResult ->
                FlatResourceWriteResult.createResourceWriteResult(builder, payload.count)
            is AdfpResourcePayload.Clunk ->
                FlatResourceClunk.createResourceClunk(builder, payload.fid)
            is AdfpResourcePayload.ClunkResult ->
                FlatResourceClunkResult.createResourceClunkResult(builder, payload.status)
            is AdfpResourcePayload.StatRequest ->
                FlatResourceStatRequest.createResourceStatRequest(builder, payload.fid)
            is AdfpResourcePayload.StatResult -> {
                val statOffset = payload.stat.write(builder)
                FlatResourceStatResult.createResourceStatResult(builder, statOffset)
            }
            is AdfpResourcePayload.Wstat -> {
                val statOffset = payload.stat.write(builder)
                FlatResourceWstat.createResourceWstat(builder, payload.fid, statOffset)
            }
            is AdfpResourcePayload.WstatResult ->
                FlatResourceWstatResult.createResourceWstatResult(builder, payload.status)
            is AdfpResourcePayload.CompoundRequest ->
                ResourceCompoundCodec.writeCompoundRequest(builder, payload.request)
            is AdfpResourcePayload.CompoundResult ->
                ResourceCompoundCodec.writeCompoundResult(builder, payload.result)
        }
        val rpcOffset = FlatResourceRpc.createResourceRpc(
            builder = builder,
            payloadType = rpc.payloadType,
            payloadOffset = payloadOffset,
            opCode = rpc.opCode,
        )
        val headerOffset = buildHeader(builder, header)
        FlatEnvelope.startEnvelope(builder)
        FlatEnvelope.addVersion(builder, AdfpProtocol.VERSION)
        FlatEnvelope.addHeader(builder, headerOffset)
        FlatEnvelope.addFabricPayloadType(builder, FlatFabricPayload.ResourceRpc)
        FlatEnvelope.addFabricPayload(builder, rpcOffset)
        return finish(builder)
    }

    private fun readInput(input: FlatInputEvent): AdfpInputEvent = AdfpInputEvent(
        version = input.version,
        type = input.type,
        sessionId = requiredString(input.sessionId, "InputEvent.sessionId", 256),
        generation = input.generation,
        seq = input.seq,
        timestamp = input.timestamp,
        x = input.x,
        y = input.y,
        dx = input.dx,
        dy = input.dy,
        button = input.button,
        clickCount = input.clickCount,
        key = optionalString(input.key, "InputEvent.key", 256),
        code = optionalString(input.code, "InputEvent.code", 256),
        modifiers = stringVector("InputEvent.modifiers", input.modifiersLength) {
            input.modifiers(it)
        },
        text = optionalString(input.text, "InputEvent.text", 4096),
        width = input.width,
        height = input.height,
        target = optionalString(input.target, "InputEvent.target", 256),
    )

    private fun readControl(control: FlatControlMessage): AdfpControlMessage = AdfpControlMessage(
        version = control.version,
        type = control.type,
        sessionId = requiredString(control.sessionId, "ControlMessage.sessionId", 256),
        generation = control.generation,
        seq = control.seq,
        timestamp = control.timestamp,
        appearance = optionalString(control.appearance, "ControlMessage.appearance", 256),
        message = optionalString(control.message, "ControlMessage.message", 4096),
        action = optionalString(control.action, "ControlMessage.action", 256),
        width = control.width,
        height = control.height,
        code = optionalString(control.code, "ControlMessage.code", 256),
    )

    private fun readDisplay(display: FlatDisplaySession): AdfpDisplaySession =
        AdfpDisplaySession(
            workspaceId = optionalString(display.workspaceId, "DisplaySession.workspaceId", 128),
            displayId = optionalString(display.displayId, "DisplaySession.displayId", 128),
            viewport = display.viewport?.let {
                AdfpViewport(
                    width = it.width,
                    height = it.height,
                    scale = it.scale,
                    orientation = optionalString(
                        it.orientation,
                        "Viewport.orientation",
                        32,
                    ),
                )
            },
            profile = optionalString(display.profile, "DisplaySession.profile", 128),
            generation = display.generation,
        )

    private fun readSync(sync: FlatSyncRecord): AdfpSyncRecord {
        if (sync.payloadHashLength > 1024) {
            throw AdfpException(AdfpError.MALFORMED, "SyncRecord.payloadHash is too large")
        }
        return AdfpSyncRecord(
            workspaceId = optionalString(sync.workspaceId, "SyncRecord.workspaceId", 128),
            recordId = optionalString(sync.recordId, "SyncRecord.recordId", 128),
            deviceId = optionalString(sync.deviceId, "SyncRecord.deviceId", 128),
            userId = optionalString(sync.userId, "SyncRecord.userId", 128),
            seq = sync.seq,
            mergeClass = sync.mergeClass,
            payloadHash = ByteArray(sync.payloadHashLength) { sync.payloadHash(it).toByte() },
        )
    }

    private fun readResource(rpc: FlatResourceRpc): AdfpResourceRpc {
        val payload = when (rpc.payloadType) {
            FlatResourceRpcPayload.ResourceAttach -> {
                val attach = rpc.payload(FlatResourceAttach()) as? FlatResourceAttach
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceAttach payload is missing")
                if (attach.coseTokenLength > 65_536) {
                    throw AdfpException(AdfpError.MALFORMED, "ResourceAttach.coseToken is too large")
                }
                AdfpResourcePayload.Attach(
                    fid = attach.fid,
                    afid = attach.afid,
                    uname = optionalString(attach.uname, "ResourceAttach.uname", 128),
                    aname = optionalString(attach.aname, "ResourceAttach.aname", 128),
                    coseToken = ByteArray(attach.coseTokenLength) {
                        attach.coseToken(it).toByte()
                    },
                )
            }
            FlatResourceRpcPayload.ResourceAttachResult -> {
                val result = rpc.payload(FlatResourceAttachResult()) as? FlatResourceAttachResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceAttachResult payload is missing",
                    )
                AdfpResourcePayload.AttachResult(
                    fid = result.fid,
                    qid = result.qid.read(),
                )
            }
            FlatResourceRpcPayload.ResourceWalk -> {
                val walk = rpc.payload(FlatResourceWalk()) as? FlatResourceWalk
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceWalk payload is missing")
                AdfpResourcePayload.Walk(
                    fid = walk.fid,
                    newFid = walk.newFid,
                    wnames = stringVector("ResourceWalk.wnames", walk.wnamesLength) {
                        walk.wnames(it)
                    },
                )
            }
            FlatResourceRpcPayload.ResourceWalkResult -> {
                val result = rpc.payload(FlatResourceWalkResult()) as? FlatResourceWalkResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceWalkResult payload is missing",
                    )
                if (result.wqidsLength > 256) {
                    throw AdfpException(AdfpError.MALFORMED, "ResourceWalkResult has too many qids")
                }
                AdfpResourcePayload.WalkResult(
                    wqids = List(result.wqidsLength) { index ->
                        result.wqids(index)?.read()
                            ?: throw AdfpException(
                                AdfpError.MALFORMED,
                                "ResourceWalkResult contains a null qid",
                            )
                    },
                )
            }
            FlatResourceRpcPayload.ResourceOpen -> {
                val open = rpc.payload(FlatResourceOpen()) as? FlatResourceOpen
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceOpen payload is missing")
                AdfpResourcePayload.Open(open.fid, open.mode)
            }
            FlatResourceRpcPayload.ResourceOpenResult -> {
                val result = rpc.payload(FlatResourceOpenResult()) as? FlatResourceOpenResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceOpenResult payload is missing",
                    )
                AdfpResourcePayload.OpenResult(result.qid.read(), result.iounit)
            }
            FlatResourceRpcPayload.ResourceRead -> {
                val read = rpc.payload(FlatResourceRead()) as? FlatResourceRead
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceRead payload is missing")
                AdfpResourcePayload.Read(read.fid, read.offset, read.count)
            }
            FlatResourceRpcPayload.ResourceReadResult -> {
                val result = rpc.payload(FlatResourceReadResult()) as? FlatResourceReadResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceReadResult payload is missing",
                    )
                ResourceCompoundCodec.readReadResult(result)
            }
            FlatResourceRpcPayload.ResourceWrite -> {
                val write = rpc.payload(FlatResourceWrite()) as? FlatResourceWrite
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceWrite payload is missing")
                if (write.dataLength > 1_048_576) {
                    throw AdfpException(AdfpError.MALFORMED, "ResourceWrite.data is too large")
                }
                AdfpResourcePayload.Write(
                    fid = write.fid,
                    offset = write.offset,
                    data = ByteArray(write.dataLength) { write.data(it).toByte() },
                )
            }
            FlatResourceRpcPayload.ResourceWriteResult -> {
                val result = rpc.payload(FlatResourceWriteResult()) as? FlatResourceWriteResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceWriteResult payload is missing",
                    )
                AdfpResourcePayload.WriteResult(result.count)
            }
            FlatResourceRpcPayload.ResourceClunk -> {
                val clunk = rpc.payload(FlatResourceClunk()) as? FlatResourceClunk
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceClunk payload is missing")
                AdfpResourcePayload.Clunk(clunk.fid)
            }
            FlatResourceRpcPayload.ResourceClunkResult -> {
                val result = rpc.payload(FlatResourceClunkResult()) as? FlatResourceClunkResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceClunkResult payload is missing",
                    )
                AdfpResourcePayload.ClunkResult(result.status)
            }
            FlatResourceRpcPayload.ResourceStatRequest -> {
                val request = rpc.payload(FlatResourceStatRequest()) as? FlatResourceStatRequest
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceStatRequest payload is missing",
                    )
                AdfpResourcePayload.StatRequest(request.fid)
            }
            FlatResourceRpcPayload.ResourceStatResult -> {
                val result = rpc.payload(FlatResourceStatResult()) as? FlatResourceStatResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceStatResult payload is missing",
                    )
                AdfpResourcePayload.StatResult(
                    result.stat?.read()
                        ?: throw AdfpException(
                            AdfpError.MALFORMED,
                            "ResourceStatResult.stat is missing",
                        ),
                )
            }
            FlatResourceRpcPayload.ResourceWstat -> {
                val wstat = rpc.payload(FlatResourceWstat()) as? FlatResourceWstat
                    ?: throw AdfpException(AdfpError.MALFORMED, "ResourceWstat payload is missing")
                AdfpResourcePayload.Wstat(
                    fid = wstat.fid,
                    stat = wstat.stat?.read()
                        ?: throw AdfpException(AdfpError.MALFORMED, "ResourceWstat.stat is missing"),
                )
            }
            FlatResourceRpcPayload.ResourceWstatResult -> {
                val result = rpc.payload(FlatResourceWstatResult()) as? FlatResourceWstatResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceWstatResult payload is missing",
                    )
                AdfpResourcePayload.WstatResult(result.status)
            }
            FlatResourceRpcPayload.ResourceCompoundRequest -> {
                val request = rpc.payload(FlatResourceCompoundRequest())
                    as? FlatResourceCompoundRequest
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceCompoundRequest payload is missing",
                    )
                AdfpResourcePayload.CompoundRequest(
                    ResourceCompoundCodec.readCompoundRequest(request),
                )
            }
            FlatResourceRpcPayload.ResourceCompoundResult -> {
                val result = rpc.payload(FlatResourceCompoundResult())
                    as? FlatResourceCompoundResult
                    ?: throw AdfpException(
                        AdfpError.MALFORMED,
                        "ResourceCompoundResult payload is missing",
                    )
                AdfpResourcePayload.CompoundResult(
                    ResourceCompoundCodec.readCompoundResult(result),
                )
            }
            else -> throw AdfpException(
                AdfpError.UNSUPPORTED_PAYLOAD,
                "unsupported ResourceRpc payload type ${rpc.payloadType}",
            )
        }
        val decoded = AdfpResourceRpc(payload)
        if (decoded.payloadType != rpc.payloadType || decoded.opCode != rpc.opCode) {
            throw AdfpException(
                AdfpError.MALFORMED,
                "ResourceRpc payload type and op code do not match",
            )
        }
        return decoded
    }

    private fun decodeEnvelope(bytes: ByteArray, nowEpochMillis: ULong): FlatEnvelope {
        if (bytes.isEmpty()) {
            throw AdfpException(AdfpError.EMPTY, "ADFP envelope is empty")
        }
        if (bytes.size > AdfpProtocol.MAX_ENVELOPE_BYTES) {
            throw AdfpException(
                AdfpError.OVERSIZED,
                "ADFP envelope is ${bytes.size} bytes; limit is ${AdfpProtocol.MAX_ENVELOPE_BYTES}",
            )
        }
        if (bytes.size < 8) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope is shorter than a FlatBuffers root")
        }
        val identifier = AdfpProtocol.FILE_IDENTIFIER.toByteArray(Charsets.US_ASCII)
        if (bytes[4] != identifier[0] ||
            bytes[5] != identifier[1] ||
            bytes[6] != identifier[2] ||
            bytes[7] != identifier[3]
        ) {
            throw AdfpException(
                AdfpError.WRONG_FILE_IDENTIFIER,
                "ADFP envelope file identifier must be ${AdfpProtocol.FILE_IDENTIFIER}",
            )
        }
        val root = readInt(bytes, 0)
        if (root < 8 || root + 4 > bytes.size) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope root offset is out of range")
        }
        val vtableStart = root - readInt(bytes, root)
        if (vtableStart < 0 || vtableStart + 4 > bytes.size) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope vtable is out of range")
        }
        val vtableSize = readShort(bytes, vtableStart)
        if (vtableSize < 4 || vtableStart + vtableSize > bytes.size) {
            throw AdfpException(AdfpError.TRUNCATED, "ADFP envelope vtable is truncated")
        }
        return try {
            val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val envelope = FlatEnvelope.getRootAsEnvelope(buffer)
            if (envelope.version != AdfpProtocol.VERSION) {
                throw AdfpException(
                    AdfpError.WRONG_VERSION,
                    "unsupported ADFP envelope version ${envelope.version}; " +
                        "expected ${AdfpProtocol.VERSION}",
                )
            }
            val header = envelope.header
                ?: throw AdfpException(AdfpError.MALFORMED, "ADFP envelope is missing a ControlHeader")
            val decodedHeader = readHeader(header)
            if (decodedHeader.expiresAtEpochMillis != 0UL &&
                decodedHeader.expiresAtEpochMillis <= nowEpochMillis
            ) {
                throw AdfpException(
                    AdfpError.HEADER_EXPIRED,
                    "ADFP envelope header expired at ${decodedHeader.expiresAtEpochMillis}",
                )
            }
            envelope
        } catch (error: AdfpException) {
            throw error
        } catch (error: Exception) {
            throw AdfpException(AdfpError.MALFORMED, "malformed ADFP envelope", error)
        } catch (error: AssertionError) {
            throw AdfpException(AdfpError.MALFORMED, "malformed ADFP envelope", error)
        }
    }

    private fun readInt(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or
            ((bytes[offset + 1].toInt() and 0xff) shl 8) or
            ((bytes[offset + 2].toInt() and 0xff) shl 16) or
            ((bytes[offset + 3].toInt() and 0xff) shl 24)

    private fun readShort(bytes: ByteArray, offset: Int): Int =
        (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)

    private fun readHeader(header: FlatControlHeader): AdfpControlHeader = AdfpControlHeader(
        messageId = requiredString(header.messageId, "ControlHeader.messageId", 128),
        senderDeviceId = requiredString(
            header.senderDeviceId,
            "ControlHeader.senderDeviceId",
            128,
        ),
        senderRole = header.senderRole,
        correlationId = optionalString(
            header.correlationId,
            "ControlHeader.correlationId",
            128,
        ),
        idempotencyKey = optionalString(
            header.idempotencyKey,
            "ControlHeader.idempotencyKey",
            128,
        ),
        expiresAtEpochMillis = header.expiresAt,
        cancellationId = optionalString(
            header.cancellationId,
            "ControlHeader.cancellationId",
            128,
        ),
    )

    private fun buildHeader(builder: FlatBufferBuilder, header: AdfpControlHeader): Int =
        FlatControlHeader.createControlHeader(
            builder = builder,
            messageIdOffset = builder.createString(header.messageId),
            senderDeviceIdOffset = builder.createString(header.senderDeviceId),
            senderRole = header.senderRole,
            correlationIdOffset = header.correlationId.stringOffset(builder),
            idempotencyKeyOffset = header.idempotencyKey.stringOffset(builder),
            expiresAt = header.expiresAtEpochMillis,
            cancellationIdOffset = header.cancellationId.stringOffset(builder),
        )

    private fun finish(builder: FlatBufferBuilder): ByteArray {
        val root = FlatEnvelope.endEnvelope(builder)
        FlatEnvelope.finishEnvelopeBuffer(builder, root)
        return builder.sizedByteArray()
    }

    private fun String?.stringOffset(builder: FlatBufferBuilder): Int =
        if (this == null) 0 else builder.createString(this)

    private fun ByteArray.writeByteVector(builder: FlatBufferBuilder): Int {
        if (isEmpty()) return 0
        builder.startVector(1, size, 1)
        for (index in indices.reversed()) {
            builder.addByte(this[index])
        }
        return builder.endVector()
    }

    private fun AdfpQid.write(builder: FlatBufferBuilder): Int =
        FlatQid.createQid(builder, type, version, path)

    private fun FlatQid?.read(): AdfpQid = this?.let {
        AdfpQid(type = it.type, version = it.version, path = it.path)
    } ?: throw AdfpException(AdfpError.MALFORMED, "Qid is missing")

    private fun FlatResourceStat.read(): AdfpResourceStat = AdfpResourceStat(
        qid = qid.read(),
        mode = mode,
        length = length,
        name = optionalString(name, "ResourceStat.name", 256),
        modifiedAtEpochMillis = modifiedAt,
    )

    private fun AdfpResourceStat.write(builder: FlatBufferBuilder): Int {
        FlatResourceStat.startResourceStat(builder)
        FlatResourceStat.addQid(builder, qid.write(builder))
        FlatResourceStat.addMode(builder, mode)
        FlatResourceStat.addLength(builder, length)
        FlatResourceStat.addName(builder, name.stringOffset(builder))
        FlatResourceStat.addModifiedAt(builder, modifiedAtEpochMillis)
        return FlatResourceStat.endResourceStat(builder)
    }

    private fun stringVector(
        field: String,
        length: Int,
        value: (Int) -> String?,
    ): List<String> {
        if (length > 256) {
            throw AdfpException(AdfpError.MALFORMED, "$field has too many entries")
        }
        return List(length) { index ->
            value(index) ?: throw AdfpException(AdfpError.MALFORMED, "$field contains a null entry")
        }
    }

    private fun requiredString(value: String?, field: String, maxBytes: Int): String {
        val result = value ?: throw AdfpException(AdfpError.MALFORMED, "$field is missing")
        if (result.toByteArray(Charsets.UTF_8).size > maxBytes) {
            throw AdfpException(AdfpError.MALFORMED, "$field exceeds $maxBytes bytes")
        }
        return result
    }

    private fun optionalString(value: String?, field: String, maxBytes: Int): String? {
        if (value == null) return null
        if (value.toByteArray(Charsets.UTF_8).size > maxBytes) {
            throw AdfpException(AdfpError.MALFORMED, "$field exceeds $maxBytes bytes")
        }
        return value
    }
}
