package com.airdesk.android.protocol

import com.airdesk.android.fabric.IrohFabricChannel
import java.io.File
import java.util.HexFormat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AdfpEnvelopeFixtureTest {
    private val session = AdfpFabricSession()
    private val root = Json.parseToJsonElement(fixtureFile().readText()).jsonObject
    private val now = root.getValue("nowEpochMillis").jsonPrimitive.content.toULong()
    private val cases = root.getValue("cases").jsonArray
    private val hex = HexFormat.of()

    @Test
    fun inputFixtureDecodesAndReencodes() {
        val bytes = caseBytes("input-key-down")
        val decoded = session.decode(IrohFabricChannel.INPUT_EDGES, bytes, now)
            as AdfpSessionPayload.Input
        val header = session.decodeHeader(bytes, now)

        assertEquals("message-1", header.messageId)
        assertEquals("device-controller-1", header.senderDeviceId)
        assertEquals(4_102_444_800_000UL, header.expiresAtEpochMillis)
        assertEquals("session-1", decoded.event.sessionId)
        assertEquals(6u.toUByte(), decoded.event.type)
        assertEquals(7u, decoded.event.generation)
        assertEquals(42u, decoded.event.seq)
        assertEquals(1_700_000_000_123UL, decoded.event.timestamp)
        assertEquals("a", decoded.event.key)
        assertEquals("KeyA", decoded.event.code)
        assertEquals(listOf("Shift"), decoded.event.modifiers)
        assertEquals("window-1", decoded.event.target)

        val actual = session.encode(IrohFabricChannel.INPUT_EDGES, decoded, header)
        assertEquals(decoded, session.decode(IrohFabricChannel.INPUT_EDGES, actual, now))
        assertEquals(header, session.decodeHeader(actual, now))
    }

    @Test
    fun controlFixtureDecodesAndReencodes() {
        val bytes = caseBytes("control-notice")
        val decoded = session.decode(IrohFabricChannel.CONTROL, bytes, now)
            as AdfpSessionPayload.Control
        val header = session.decodeHeader(bytes, now)

        assertEquals("session-1", decoded.message.sessionId)
        assertEquals(3u.toUByte(), decoded.message.type)
        assertEquals(43u, decoded.message.seq)
        assertEquals(1_700_000_000_124UL, decoded.message.timestamp)
        assertEquals("connected", decoded.message.message)
        assertEquals("focus", decoded.message.action)

        val actual = session.encode(IrohFabricChannel.CONTROL, decoded, header)
        assertEquals(decoded, session.decode(IrohFabricChannel.CONTROL, actual, now))
        assertEquals(header, session.decodeHeader(actual, now))
    }

    @Test
    fun invalidFixturesAreRejected() {
        val invalid = root.getValue("invalid").jsonArray
        for (item in invalid) {
            val entry = item.jsonObject
            val bytes = hex.parseHex(entry.getValue("hex").jsonPrimitive.content)
            val error = assertThrows(AdfpException::class.java) {
                session.decode(IrohFabricChannel.INPUT_EDGES, bytes, now)
            }
            when (entry.getValue("name").jsonPrimitive.content) {
                "wrong-file-identifier" ->
                    assertEquals(AdfpError.WRONG_FILE_IDENTIFIER, error.reason)
                "truncated" -> assertEquals(AdfpError.TRUNCATED, error.reason)
            }
        }
    }

    @Test
    fun expiredHeaderIsRejected() {
        val bytes = caseBytes("input-key-down")
        val error = assertThrows(AdfpException::class.java) {
            session.decodeHeader(bytes, 4_102_444_800_000UL)
        }
        assertEquals(AdfpError.HEADER_EXPIRED, error.reason)
    }

    private fun caseBytes(name: String): ByteArray {
        val item = cases.first { it.jsonObject.getValue("name").jsonPrimitive.content == name }
        return hex.parseHex(item.jsonObject.getValue("hex").jsonPrimitive.content)
    }

    private fun fixtureFile(): File {
        var directory = File(System.getProperty("user.dir") ?: ".")
        repeat(5) {
            val candidate = File(directory, "protocol/fixtures/adfp/envelope-v1.json")
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: return@repeat
        }
        error("could not find protocol/fixtures/adfp/envelope-v1.json from ${System.getProperty("user.dir")}")
    }
}
