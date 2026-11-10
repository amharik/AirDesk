package com.airdesk.android.workspace

import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

enum class AndroidBridgeKind(val wire: String) {
    RUNTIME("runtime"),
    TERMINAL("terminal"),
    ;

    companion object {
        fun fromWire(value: String): AndroidBridgeKind? =
            entries.firstOrNull { it.wire == value }
    }
}

enum class AndroidBridgeRejection(val wire: String) {
    MALFORMED_PAYLOAD("malformed-payload"),
    UNKNOWN_KIND("unknown-kind"),
    UNSUPPORTED_VERSION("unsupported-version"),
    UNSUPPORTED_TYPE("unsupported-type"),
    UNSUPPORTED_ACTION("unsupported-action"),
    INVALID_SESSION("invalid-session"),
    INVALID_GENERATION("invalid-generation"),
    INVALID_SEQUENCE("invalid-sequence"),
    MESSAGE_TOO_LARGE("message-too-large"),
    INVALID_FIELD("invalid-field"),
}

sealed interface AndroidBridgeReceiveResult {
    data class Accepted(
        val kind: AndroidBridgeKind,
        val type: String,
    ) : AndroidBridgeReceiveResult

    data class Rejected(
        val reason: AndroidBridgeRejection,
    ) : AndroidBridgeReceiveResult
}

@Serializable
data class AndroidBridgeMessage(
    val version: Int? = null,
    val type: String? = null,
    val sessionId: String? = null,
    val generation: Long? = null,
    val seq: Int? = null,
    val timestamp: Double? = null,
    val runtime: String? = null,
    val level: String? = null,
    val message: String? = null,
    val width: Double? = null,
    val height: Double? = null,
    val code: String? = null,
    val action: String? = null,
    val appearance: String? = null,
)

@Serializable
data class AndroidTerminalMessage(
    val version: Int? = null,
    val sessionId: String? = null,
    val action: String? = null,
    val data: String? = null,
    val columns: Int? = null,
    val rows: Int? = null,
)

class AndroidDesktopBridge(
    sessionId: String = "",
    generation: Long = 0,
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = false
        allowSpecialFloatingPointValues = false
    }

    private var sessionId = sessionId
    private var generation = generation

    var onRuntimeMessage: ((AndroidBridgeMessage) -> Unit)? = null
    var onTerminalMessage: ((AndroidTerminalMessage) -> Unit)? = null

    fun updateSession(sessionId: String, generation: Long) {
        this.sessionId = sessionId
        this.generation = generation
    }

    fun receive(kind: String, payload: String): AndroidBridgeReceiveResult {
        if (payload.length > MAXIMUM_PAYLOAD_LENGTH) {
            return rejected(AndroidBridgeRejection.MESSAGE_TOO_LARGE)
        }
        val bridgeKind = AndroidBridgeKind.fromWire(kind)
            ?: return rejected(AndroidBridgeRejection.UNKNOWN_KIND)
        return when (bridgeKind) {
            AndroidBridgeKind.RUNTIME -> receiveRuntime(payload)
            AndroidBridgeKind.TERMINAL -> receiveTerminal(payload)
        }
    }

    private fun receiveRuntime(payload: String): AndroidBridgeReceiveResult {
        val message = decode<AndroidBridgeMessage>(payload)
            ?: return rejected(AndroidBridgeRejection.MALFORMED_PAYLOAD)
        if (message.version != VERSION) {
            return rejected(AndroidBridgeRejection.UNSUPPORTED_VERSION)
        }
        val type = message.type
        if (type == null || type !in RUNTIME_TYPES) {
            return rejected(AndroidBridgeRejection.UNSUPPORTED_TYPE)
        }
        invalidSession(message.sessionId)?.let { return rejected(it) }
        invalidGeneration(message.generation)?.let { return rejected(it) }
        if (message.seq != null && message.seq < 0) {
            return rejected(AndroidBridgeRejection.INVALID_SEQUENCE)
        }
        if (message.timestamp != null && !message.timestamp.isFinite()) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.sessionId != null && message.sessionId.length > MAXIMUM_SESSION_LENGTH) {
            return rejected(AndroidBridgeRejection.INVALID_SESSION)
        }
        if (message.message != null && message.message.length > MAXIMUM_MESSAGE_LENGTH) {
            return rejected(AndroidBridgeRejection.MESSAGE_TOO_LARGE)
        }
        if (message.runtime != null && message.runtime.length > 64) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.level != null && message.level !in LOG_LEVELS) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.width != null && !validDimension(message.width)) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.height != null && !validDimension(message.height)) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.action != null && message.action.length > 128) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.code != null && message.code.length > 128) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        if (message.appearance != null && message.appearance.length > 32) {
            return rejected(AndroidBridgeRejection.INVALID_FIELD)
        }
        onRuntimeMessage?.invoke(message)
        return AndroidBridgeReceiveResult.Accepted(AndroidBridgeKind.RUNTIME, type)
    }

    private fun receiveTerminal(payload: String): AndroidBridgeReceiveResult {
        val message = decode<AndroidTerminalMessage>(payload)
            ?: return rejected(AndroidBridgeRejection.MALFORMED_PAYLOAD)
        if (message.version != VERSION) {
            return rejected(AndroidBridgeRejection.UNSUPPORTED_VERSION)
        }
        val action = message.action
        if (action == null || action !in TERMINAL_ACTIONS) {
            return rejected(AndroidBridgeRejection.UNSUPPORTED_ACTION)
        }
        invalidSession(message.sessionId)?.let { return rejected(it) }
        if (message.sessionId != null && message.sessionId.length > MAXIMUM_SESSION_LENGTH) {
            return rejected(AndroidBridgeRejection.INVALID_SESSION)
        }
        when (action) {
            "write" -> {
                val data = message.data
                if (data.isNullOrEmpty() || data.length > MAXIMUM_TERMINAL_DATA_LENGTH) {
                    return rejected(AndroidBridgeRejection.INVALID_FIELD)
                }
                if (runCatching { Base64.getDecoder().decode(data) }.isFailure) {
                    return rejected(AndroidBridgeRejection.INVALID_FIELD)
                }
            }
            "resize" -> {
                if (message.columns == null || message.columns !in 1..1_000) {
                    return rejected(AndroidBridgeRejection.INVALID_FIELD)
                }
                if (message.rows == null || message.rows !in 1..1_000) {
                    return rejected(AndroidBridgeRejection.INVALID_FIELD)
                }
            }
        }
        onTerminalMessage?.invoke(message)
        return AndroidBridgeReceiveResult.Accepted(AndroidBridgeKind.TERMINAL, action)
    }

    private inline fun <reified T> decode(payload: String): T? =
        runCatching { json.decodeFromString<T>(payload) }.getOrNull()

    private fun invalidSession(candidate: String?): AndroidBridgeRejection? =
        if (candidate != null && candidate != sessionId) {
            AndroidBridgeRejection.INVALID_SESSION
        } else {
            null
        }

    private fun invalidGeneration(candidate: Long?): AndroidBridgeRejection? =
        if (candidate != null && candidate != generation) {
            AndroidBridgeRejection.INVALID_GENERATION
        } else {
            null
        }

    private fun validDimension(value: Double): Boolean =
        value.isFinite() && value >= 0 && value <= 20_000

    private fun rejected(reason: AndroidBridgeRejection): AndroidBridgeReceiveResult.Rejected =
        AndroidBridgeReceiveResult.Rejected(reason)

    companion object {
        const val VERSION = 1
        const val MAXIMUM_SESSION_LENGTH = 64
        const val MAXIMUM_MESSAGE_LENGTH = 4_000
        const val MAXIMUM_TERMINAL_DATA_LENGTH = 131_072
        const val MAXIMUM_PAYLOAD_LENGTH = 200_000

        private val RUNTIME_TYPES = setOf(
            "ready",
            "ack",
            "log",
            "state",
            "error",
            "viewport",
            "action",
            "notice",
        )
        private val TERMINAL_ACTIONS = setOf("start", "write", "resize", "stop")
        private val LOG_LEVELS = setOf("debug", "info", "warn", "error")

        fun encodeControl(
            sessionId: String,
            generation: Long,
            type: String,
            fields: Map<String, String?> = emptyMap(),
        ): String = buildJsonObject {
            put("version", VERSION)
            put("type", type)
            put("sessionId", sessionId)
            put("generation", generation)
            fields.forEach { (key, value) ->
                if (value != null) put(key, value)
            }
        }.toString()
    }
}
