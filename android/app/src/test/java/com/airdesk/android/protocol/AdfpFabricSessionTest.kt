package com.airdesk.android.protocol

import AirDesk.Protocol.SenderRole
import com.airdesk.android.fabric.FabricIncoming
import com.airdesk.android.fabric.IrohFabricChannel
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AdfpFabricSessionTest {
    private val session = AdfpFabricSession()
    private val header = AdfpControlHeader(
        messageId = "message-1",
        senderDeviceId = "ad-device:" + "a".repeat(64),
        senderRole = SenderRole.agent,
        correlationId = "correlation-1",
        idempotencyKey = "idempotency-1",
        expiresAtEpochMillis = 4_102_444_800_000UL,
        cancellationId = "cancel-1",
    )

    @Test
    fun inputRoundTripsOnInputChannel() {
        val event = AdfpInputEvent(
            type = 1u,
            sessionId = "session-1",
            generation = 2u,
            seq = 3u,
            timestamp = 4uL,
            x = 12.5f,
            y = 24.5f,
            key = "a",
            code = "KeyA",
            modifiers = listOf("Meta", "Shift"),
            text = "a",
            target = "window-1",
        )
        val payload = AdfpSessionPayload.Input(event)

        val bytes = session.encode(payload, header)
        val decoded = session.decode(IrohFabricChannel.INPUT_EDGES, bytes)

        assertEquals(IrohFabricChannel.INPUT_EDGES, session.channelFor(payload))
        assertEquals(payload, decoded)
        assertEquals(header, session.decodeHeader(bytes))
    }

    @Test
    fun controlRoundTripsOnControlAndDisplayChannels() {
        val payload = AdfpSessionPayload.Control(
            AdfpControlMessage(
                type = 2u,
                sessionId = "session-1",
                appearance = "dark",
                message = "connected",
                action = "focus",
                width = 390f,
                height = 844f,
                code = "ok",
            ),
        )
        val bytes = session.encode(IrohFabricChannel.DISPLAY, payload, header)

        assertEquals(payload, session.decode(IrohFabricChannel.CONTROL, bytes))
        assertEquals(payload, session.decode(IrohFabricChannel.DISPLAY, bytes))
    }

    @Test
    fun displayRoundTripsViewport() {
        val payload = AdfpSessionPayload.Display(
            AdfpDisplaySession(
                workspaceId = "workspace-1",
                displayId = "display-1",
                viewport = AdfpViewport(
                    width = 1440u,
                    height = 900u,
                    scale = 2f,
                    orientation = "landscape",
                ),
                profile = "remote",
                generation = 5u,
            ),
        )

        val bytes = session.encode(payload, header)
        val decoded = session.decode(IrohFabricChannel.DISPLAY, bytes)

        assertEquals(payload, decoded)
    }

    @Test
    fun syncRoundTripsPayloadHash() {
        val payload = AdfpSessionPayload.Sync(
            AdfpSyncRecord(
                workspaceId = "workspace-1",
                recordId = "record-1",
                deviceId = header.senderDeviceId,
                userId = "user-1",
                seq = 9uL,
                mergeClass = 2u,
                payloadHash = ByteArray(32) { (it + 1).toByte() },
            ),
        )

        val bytes = session.encode(payload, header)
        val decoded = session.decode(IrohFabricChannel.SYNC, bytes) as AdfpSessionPayload.Sync

        assertEquals(payload.record.workspaceId, decoded.record.workspaceId)
        assertEquals(payload.record.recordId, decoded.record.recordId)
        assertEquals(payload.record.deviceId, decoded.record.deviceId)
        assertEquals(payload.record.userId, decoded.record.userId)
        assertEquals(payload.record.seq, decoded.record.seq)
        assertEquals(payload.record.mergeClass, decoded.record.mergeClass)
        assertArrayEquals(payload.record.payloadHash, decoded.record.payloadHash)
    }

    @Test
    fun resourceRoundTripsReadAndWalk() {
        val read = AdfpSessionPayload.Resource(
            AdfpResourceRpc(
                AdfpResourcePayload.ReadResult(ByteArray(4) { (it + 1).toByte() }),
            ),
        )
        val walk = AdfpSessionPayload.Resource(
            AdfpResourceRpc(
                AdfpResourcePayload.WalkResult(
                    listOf(
                        AdfpQid(type = 1u, version = 2u, path = 3uL),
                        AdfpQid(type = 4u, version = 5u, path = 6uL),
                    ),
                ),
            ),
        )

        val decodedRead = session.decode(
            IrohFabricChannel.RESOURCE,
            session.encode(read, header),
        ) as AdfpSessionPayload.Resource
        val decodedWalk = session.decode(
            IrohFabricChannel.RESOURCE,
            session.encode(walk, header),
        ) as AdfpSessionPayload.Resource

        assertArrayEquals(
            ByteArray(4) { (it + 1).toByte() },
            (decodedRead.rpc.payload as AdfpResourcePayload.ReadResult).data,
        )
        assertEquals(walk.rpc.payload, decodedWalk.rpc.payload)
    }

    @Test
    fun encodeRejectsPayloadOnWrongChannel() {
        val payload = AdfpSessionPayload.Input(
            AdfpInputEvent(type = 1u, sessionId = "session-1"),
        )

        val error = assertThrows(AdfpException::class.java) {
            session.encode(IrohFabricChannel.CONTROL, payload, header)
        }

        assertEquals(AdfpError.UNSUPPORTED_PAYLOAD, error.reason)
    }

    @Test
    fun decodeRejectsPayloadOnWrongChannel() {
        val bytes = session.encode(
            AdfpSessionPayload.Input(AdfpInputEvent(type = 1u, sessionId = "session-1")),
            header,
        )

        val error = assertThrows(AdfpException::class.java) {
            session.decode(IrohFabricChannel.RESOURCE, bytes)
        }

        assertEquals(AdfpError.UNSUPPORTED_PAYLOAD, error.reason)
    }

    @Test
    fun dispatchRoutesReliableFramesAndIgnoresMovement() {
        val payload = AdfpSessionPayload.Sync(
            AdfpSyncRecord(
                workspaceId = null,
                recordId = "record-1",
                deviceId = null,
                userId = null,
                seq = 1uL,
                mergeClass = 0u,
                payloadHash = byteArrayOf(),
            ),
        )
        val bytes = session.encode(payload, header)
        val dispatched = session.dispatch(
            FabricIncoming.Reliable(IrohFabricChannel.SYNC, bytes),
        ) as AdfpSessionPayload.Sync

        assertEquals(payload.record.recordId, dispatched.record.recordId)
        assertEquals(payload.record.seq, dispatched.record.seq)
        assertArrayEquals(payload.record.payloadHash, dispatched.record.payloadHash)
        assertEquals(null, session.dispatch(FabricIncoming.Movement(ByteArray(16))))
    }

    @Test
    fun dispatchRejectsInvalidFabricFrames() {
        val error = assertThrows(AdfpException::class.java) {
            session.dispatch(FabricIncoming.Invalid("bad frame"))
        }

        assertEquals(AdfpError.MALFORMED, error.reason)
        assertTrue(error.message!!.contains("bad frame"))
    }
}
