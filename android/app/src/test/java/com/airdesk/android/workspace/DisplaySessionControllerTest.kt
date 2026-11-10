package com.airdesk.android.workspace

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DisplaySessionControllerTest {
    private var now = 1_000L

    private fun controller(sessionId: String = "session-1"): DisplaySessionController =
        DisplaySessionController(sessionId = sessionId, now = { now })

    @Test
    fun reconnectPreservesIdentityAndAdvancesGeneration() {
        val target = controller()
        val first = target.beginLoad("  My workspace  ")
        now += 10
        val second = target.reconnect()

        assertEquals("session-1", first.sessionId)
        assertEquals("session-1", second.sessionId)
        assertEquals("My workspace", first.workspace)
        assertEquals("My workspace", second.workspace)
        assertEquals(1L, first.generation)
        assertEquals(2L, second.generation)
        assertEquals(DisplaySessionPhase.CONNECTING, target.snapshot().phase)
    }

    @Test
    fun readyAndViewportProduceTruthfulSnapshot() {
        val target = controller()
        target.beginLoad("Workspace")
        now += 5
        target.markReady(1280, 720)

        val ready = target.snapshot()
        assertEquals(DisplaySessionPhase.READY, ready.phase)
        assertEquals(DisplayViewport(1280, 720), ready.viewport)
        assertEquals("ready", ready.runtimeState)
        assertEquals(1_005L, ready.updatedAtEpochMillis)

        now += 5
        target.markViewport(800, 600)
        assertEquals(DisplayViewport(800, 600), target.snapshot().viewport)

        target.markViewport(0, 600)
        assertEquals(DisplayViewport(800, 600), target.snapshot().viewport)
    }

    @Test
    fun invalidReadyDimensionsDoNotInventAViewport() {
        val target = controller()
        target.beginLoad("Workspace")
        target.markReady(0, -1)

        assertEquals(DisplaySessionPhase.READY, target.snapshot().phase)
        assertNull(target.snapshot().viewport)
    }

    @Test
    fun runtimeErrorsDegradeReadySessionsAndFailConnectingSessions() {
        val ready = controller()
        ready.beginLoad("Workspace")
        ready.markReady(100, 100)
        ready.markRuntimeError("Runtime error\nwith details")
        assertEquals(DisplaySessionPhase.DEGRADED, ready.snapshot().phase)
        assertEquals("Runtime error with details", ready.snapshot().lastError)

        val connecting = controller("session-2")
        connecting.beginLoad("Workspace")
        connecting.markRuntimeError("Kernel failed")
        assertEquals(DisplaySessionPhase.FAILED, connecting.snapshot().phase)

        connecting.markRuntimeState("ready")
        assertEquals(DisplaySessionPhase.FAILED, connecting.snapshot().phase)
    }

    @Test
    fun terminalDiagnosticsSanitizeControlCharactersAndBoundLength() {
        val target = controller()
        target.beginLoad("Workspace")
        target.markTerminalStatus("line one\nline two\u0000" + "x".repeat(300))

        val status = target.snapshot().terminalStatus
        assertTrue(status?.startsWith("line one line two") == true)
        assertFalse(status?.contains("\n") == true)
        assertTrue((status?.length ?: 0) <= 180)
    }

    @Test
    fun bridgeRejectionDiagnosticsDoNotChangeLifecycle() {
        val target = controller()
        target.beginLoad("Workspace")
        target.markReady(100, 100)
        target.markBridgeRejection("terminal", "invalid-session")

        val snapshot = target.snapshot()
        assertEquals(DisplaySessionPhase.READY, snapshot.phase)
        assertEquals("terminal: invalid-session", snapshot.lastBridgeRejection)
    }

    @Test
    fun listenersReceiveSnapshotsAndCanBeRemoved() {
        val target = controller()
        val snapshots = mutableListOf<DisplaySessionSnapshot>()
        val listener: (DisplaySessionSnapshot) -> Unit = { snapshots += it }
        target.addListener(listener)

        target.beginLoad("Workspace")
        target.markReady(640, 480)
        assertEquals(2, snapshots.size)
        assertEquals(DisplaySessionPhase.READY, snapshots.last().phase)

        target.removeListener(listener)
        target.markStopped()
        assertEquals(2, snapshots.size)
        assertEquals(DisplaySessionPhase.STOPPED, target.snapshot().phase)
    }

    @Test
    fun rejectsInvalidSessionIdentifiers() {
        assertThrows(IllegalArgumentException::class.java) {
            DisplaySessionController(sessionId = " ")
        }
        assertThrows(IllegalArgumentException::class.java) {
            DisplaySessionController(sessionId = "x".repeat(65))
        }
    }
}
