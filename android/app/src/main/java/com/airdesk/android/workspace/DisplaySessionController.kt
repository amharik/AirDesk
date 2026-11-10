package com.airdesk.android.workspace

import com.airdesk.android.display.AndroidCodecSelection
import com.airdesk.android.display.AndroidDisplayCaptureState
import com.airdesk.android.display.AndroidDisplayStreamMetrics
import com.airdesk.android.display.AndroidVideoCodec
import java.util.UUID

enum class DisplaySessionPhase(val wire: String) {
    IDLE("idle"),
    CONNECTING("connecting"),
    READY("ready"),
    DEGRADED("degraded"),
    FAILED("failed"),
    STOPPED("stopped"),
}

data class DisplayViewport(
    val width: Int,
    val height: Int,
)

data class DisplaySessionHandshake(
    val sessionId: String,
    val generation: Long,
    val workspace: String,
)

data class DisplayStreamSnapshot(
    val state: AndroidDisplayCaptureState,
    val codec: AndroidVideoCodec,
    val codecName: String,
    val hardwareAccelerated: Boolean,
    val fallback: Boolean,
    val softwareFallback: Boolean,
    val width: Int,
    val height: Int,
    val metrics: AndroidDisplayStreamMetrics,
    val lastError: String?,
)

data class DisplaySessionSnapshot(
    val sessionId: String,
    val generation: Long,
    val workspace: String,
    val phase: DisplaySessionPhase,
    val viewport: DisplayViewport?,
    val runtimeState: String?,
    val lastError: String?,
    val terminalStatus: String?,
    val lastBridgeRejection: String?,
    val updatedAtEpochMillis: Long,
    val displayStream: DisplayStreamSnapshot? = null,
)

class DisplaySessionController(
    sessionId: String = UUID.randomUUID().toString(),
    private val now: () -> Long = System::currentTimeMillis,
) {
    init {
        require(sessionId.isNotBlank() && sessionId.length <= 64) {
            "session id must be non-blank and at most 64 characters"
        }
    }

    val sessionId: String = sessionId

    private val listeners = LinkedHashSet<(DisplaySessionSnapshot) -> Unit>()
    private var generation = 0L
    private var workspace = "Android workspace"
    private var phase = DisplaySessionPhase.IDLE
    private var viewport: DisplayViewport? = null
    private var runtimeState: String? = null
    private var lastError: String? = null
    private var terminalStatus: String? = null
    private var lastBridgeRejection: String? = null
    private var displayStream: DisplayStreamSnapshot? = null
    private var updatedAtEpochMillis = now()

    val currentGeneration: Long
        get() = generation

    fun addListener(listener: (DisplaySessionSnapshot) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (DisplaySessionSnapshot) -> Unit) {
        listeners.remove(listener)
    }

    fun beginLoad(workspaceName: String): DisplaySessionHandshake {
        workspace = clean(workspaceName, 128).ifBlank { "Android workspace" }
        generation += 1
        phase = DisplaySessionPhase.CONNECTING
        viewport = null
        runtimeState = null
        lastError = null
        terminalStatus = "Terminal bridge awaiting desktop readiness"
        lastBridgeRejection = null
        publish()
        return DisplaySessionHandshake(sessionId, generation, workspace)
    }

    fun reconnect(): DisplaySessionHandshake = beginLoad(workspace)

    fun markReady(width: Int?, height: Int?) {
        if (width != null && height != null && validDimension(width) && validDimension(height)) {
            viewport = DisplayViewport(width, height)
        }
        phase = DisplaySessionPhase.READY
        runtimeState = "ready"
        lastError = null
        publish()
    }

    fun markViewport(width: Int, height: Int) {
        if (!validDimension(width) || !validDimension(height)) return
        viewport = DisplayViewport(width, height)
        publish()
    }

    fun markRuntimeState(state: String) {
        val normalized = clean(state, 80)
        if (normalized.isEmpty()) return
        runtimeState = normalized
        if (normalized == "ready" && phase == DisplaySessionPhase.CONNECTING) {
            phase = DisplaySessionPhase.READY
        }
        publish()
    }

    fun markRuntimeError(message: String) {
        phase = when (phase) {
            DisplaySessionPhase.READY, DisplaySessionPhase.DEGRADED -> DisplaySessionPhase.DEGRADED
            else -> DisplaySessionPhase.FAILED
        }
        lastError = clean(message, 4_000).ifBlank { "Desktop shell reported an error" }
        publish()
    }

    fun markFailure(message: String) {
        phase = DisplaySessionPhase.FAILED
        lastError = clean(message, 4_000).ifBlank { "Desktop session failed" }
        publish()
    }

    fun markBridgeRejection(kind: String, reason: String) {
        lastBridgeRejection = clean("$kind: $reason", 128)
        publish()
    }

    fun markTerminalStatus(status: String) {
        terminalStatus = clean(status, 180)
        publish()
    }

    fun markDisplayStarting(
        selection: AndroidCodecSelection,
        width: Int,
        height: Int,
    ) {
        if (!validDimension(width) || !validDimension(height)) return
        displayStream = DisplayStreamSnapshot(
            state = AndroidDisplayCaptureState.STARTING,
            codec = selection.codec,
            codecName = clean(selection.codecName, 160),
            hardwareAccelerated = selection.hardwareAccelerated,
            fallback = selection.fallback,
            softwareFallback = selection.softwareFallback,
            width = width,
            height = height,
            metrics = AndroidDisplayStreamMetrics(),
            lastError = null,
        )
        publish()
    }

    fun markDisplayRunning() {
        val current = displayStream ?: return
        displayStream = current.copy(
            state = AndroidDisplayCaptureState.RUNNING,
            lastError = null,
        )
        publish()
    }

    fun updateDisplayMetrics(metrics: AndroidDisplayStreamMetrics) {
        val current = displayStream ?: return
        if (current.metrics == metrics) return
        displayStream = current.copy(metrics = metrics)
        publish()
    }

    fun markDisplayStopped() {
        val current = displayStream ?: return
        if (current.state == AndroidDisplayCaptureState.STOPPED ||
            current.state == AndroidDisplayCaptureState.FAILED
        ) {
            return
        }
        displayStream = current.copy(state = AndroidDisplayCaptureState.STOPPED)
        publish()
    }

    fun markDisplayFailed(message: String) {
        val current = displayStream ?: return
        displayStream = current.copy(
            state = AndroidDisplayCaptureState.FAILED,
            lastError = clean(message, 240).ifBlank { "Display stream failed" },
        )
        publish()
    }

    fun markStopped() {
        phase = DisplaySessionPhase.STOPPED
        runtimeState = "stopped"
        publish()
    }

    fun snapshot(): DisplaySessionSnapshot = DisplaySessionSnapshot(
        sessionId = sessionId,
        generation = generation,
        workspace = workspace,
        phase = phase,
        viewport = viewport,
        runtimeState = runtimeState,
        lastError = lastError,
        terminalStatus = terminalStatus,
        lastBridgeRejection = lastBridgeRejection,
        updatedAtEpochMillis = updatedAtEpochMillis,
        displayStream = displayStream,
    )

    private fun publish() {
        updatedAtEpochMillis = now()
        val snapshot = snapshot()
        listeners.toList().forEach { listener ->
            runCatching { listener(snapshot) }
        }
    }

    private fun validDimension(value: Int): Boolean = value in 1..20_000

    private fun clean(value: String, maximum: Int): String =
        value
            .replace(Regex("[\\u0000-\\u001f\\u007f]"), " ")
            .trim()
            .take(maximum)
}
