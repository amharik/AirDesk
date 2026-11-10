package com.airdesk.android.workspace

import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidDesktopBridgeTest {
    private val sessionId = "session-1"
    private val generation = 7L

    private fun bridge(): AndroidDesktopBridge =
        AndroidDesktopBridge(sessionId, generation)

    private fun runtime(
        type: String,
        messageSessionId: String? = sessionId,
        messageGeneration: Long? = generation,
        extra: JsonObjectBuilder.() -> Unit = {},
    ): String = buildJsonObject {
        put("version", 1)
        put("type", type)
        if (messageSessionId != null) put("sessionId", messageSessionId)
        if (messageGeneration != null) put("generation", messageGeneration)
        extra()
    }.toString()

    private fun terminal(
        action: String,
        messageSessionId: String? = sessionId,
        extra: JsonObjectBuilder.() -> Unit = {},
    ): String = buildJsonObject {
        put("version", 1)
        put("action", action)
        if (messageSessionId != null) put("sessionId", messageSessionId)
        extra()
    }.toString()

    @Test
    fun acceptsReadyAndDispatchesValidatedRuntimeMessage() {
        val target = bridge()
        var received: AndroidBridgeMessage? = null
        target.onRuntimeMessage = { received = it }

        val result = target.receive(
            "runtime",
            runtime("ready") {
                put("width", 1280)
                put("height", 720)
                put("runtime", "wanixDesktop")
                put("unknown", "ignored")
            },
        )

        assertEquals(
            AndroidBridgeReceiveResult.Accepted(AndroidBridgeKind.RUNTIME, "ready"),
            result,
        )
        assertNotNull(received)
        assertEquals(1280.0, received?.width ?: 0.0, 0.0)
        assertEquals(720.0, received?.height ?: 0.0, 0.0)
    }

    @Test
    fun rejectsProtocolSessionGenerationAndSequenceViolations() {
        val target = bridge()
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.UNSUPPORTED_VERSION),
            target.receive("runtime", runtime("ready") { put("version", 2) }),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.UNSUPPORTED_TYPE),
            target.receive("runtime", runtime("unknown")),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_SESSION),
            target.receive("runtime", runtime("ready", messageSessionId = "other")),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_GENERATION),
            target.receive("runtime", runtime("ready", messageGeneration = 8)),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_SEQUENCE),
            target.receive("runtime", runtime("ack") { put("seq", -1) }),
        )
    }

    @Test
    fun rejectsInvalidRuntimeFields() {
        val target = bridge()
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_FIELD),
            target.receive("runtime", runtime("viewport") { put("width", 20_001) }),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_FIELD),
            target.receive("runtime", runtime("log") { put("level", "verbose") }),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.MESSAGE_TOO_LARGE),
            target.receive("runtime", runtime("error") { put("message", "x".repeat(4_001)) }),
        )
    }

    @Test
    fun rejectsMalformedAndUnknownMessages() {
        val target = bridge()
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.MALFORMED_PAYLOAD),
            target.receive("runtime", "{not-json"),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.UNKNOWN_KIND),
            target.receive("other", runtime("ready")),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.MESSAGE_TOO_LARGE),
            target.receive("runtime", "x".repeat(AndroidDesktopBridge.MAXIMUM_PAYLOAD_LENGTH + 1)),
        )
    }

    @Test
    fun acceptsAndDispatchesTerminalWriteAndResize() {
        val target = bridge()
        val received = mutableListOf<AndroidTerminalMessage>()
        target.onTerminalMessage = { received += it }

        assertEquals(
            AndroidBridgeReceiveResult.Accepted(AndroidBridgeKind.TERMINAL, "write"),
            target.receive(
                "terminal",
                terminal("write") { put("data", "aGVsbG8=") },
            ),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Accepted(AndroidBridgeKind.TERMINAL, "resize"),
            target.receive(
                "terminal",
                terminal("resize") {
                    put("columns", 80)
                    put("rows", 24)
                },
            ),
        )

        assertEquals(listOf("write", "resize"), received.map { it.action })
    }

    @Test
    fun rejectsInvalidTerminalPayloads() {
        val target = bridge()
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.UNSUPPORTED_ACTION),
            target.receive("terminal", terminal("inject")),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_FIELD),
            target.receive("terminal", terminal("write") { put("data", "not base64!") }),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_FIELD),
            target.receive("terminal", terminal("write")),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_FIELD),
            target.receive("terminal", terminal("resize") { put("columns", 0); put("rows", 24) }),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_SESSION),
            target.receive("terminal", terminal("start", messageSessionId = "other")),
        )
    }

    @Test
    fun acceptsTerminalStartAndStopWithoutPayloads() {
        val target = bridge()
        val received = mutableListOf<String?>()
        target.onTerminalMessage = { received += it.action }

        assertTrue(target.receive("terminal", terminal("start")) is AndroidBridgeReceiveResult.Accepted)
        assertTrue(target.receive("terminal", terminal("stop")) is AndroidBridgeReceiveResult.Accepted)
        assertEquals(listOf("start", "stop"), received)
    }

    @Test
    fun updatesSessionAndIgnoresMessagesFromThePreviousGeneration() {
        val target = bridge()
        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_GENERATION),
            target.receive("runtime", runtime("ready", messageGeneration = 8)),
        )

        target.updateSession("session-2", 8)

        assertEquals(
            AndroidBridgeReceiveResult.Rejected(AndroidBridgeRejection.INVALID_SESSION),
            target.receive("runtime", runtime("ready")),
        )
        assertEquals(
            AndroidBridgeReceiveResult.Accepted(AndroidBridgeKind.RUNTIME, "ready"),
            target.receive(
                "runtime",
                runtime("ready", messageSessionId = "session-2", messageGeneration = 8),
            ),
        )
    }

    @Test
    fun encodesControlMessagesWithIdentityAndOmitsNullFields() {
        val encoded = AndroidDesktopBridge.encodeControl(
            sessionId = "session-2",
            generation = 9,
            type = "terminalExit",
            fields = mapOf("message" to "unavailable", "data" to null),
        )

        assertTrue(encoded.contains("\"version\":1"))
        assertTrue(encoded.contains("\"type\":\"terminalExit\""))
        assertTrue(encoded.contains("\"sessionId\":\"session-2\""))
        assertTrue(encoded.contains("\"generation\":9"))
        assertTrue(encoded.contains("\"message\":\"unavailable\""))
        assertTrue(!encoded.contains("\"data\""))
        assertNull(AndroidBridgeKind.fromWire("cast"))
    }
}
