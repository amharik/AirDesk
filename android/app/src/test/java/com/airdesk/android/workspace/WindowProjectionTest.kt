package com.airdesk.android.workspace

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WindowProjectionTest {
    private val identity = WindowProjectionIdentity(
        windowId = "window-editor",
        workspaceId = "workspace-alpha",
        title = "Editor",
        hostSessionId = "session-host",
        generation = 1,
    )
    private val castTarget = WindowProjectionTarget(
        targetId = "cast-studio",
        kind = WindowProjectionTargetKind.Cast,
        displaySessionId = "display-cast",
    )

    @Test
    fun projectsOnHostAndRecordsSurfaceRevisions() {
        val registry = registry()
        val started = projection(registry.begin(identity, castTarget))

        assertEquals(WindowProjectionState.Projecting, started.state)
        assertEquals("host", started.computeLocation)
        assertEquals(0, started.surfaceRevision)

        val surface = projection(registry.acknowledgeSurface(identity.windowId, 4))
        assertEquals(4, surface.surfaceRevision)
    }

    @Test
    fun reconnectRestoresWindowIdentityOnAnotherTarget() {
        val registry = registry()
        projection(registry.begin(identity, castTarget))
        projection(registry.acknowledgeSurface(identity.windowId, 2))
        val disconnected = projection(registry.disconnect(identity.windowId, "network"))

        assertEquals(WindowProjectionState.Reconnecting, disconnected.state)
        assertEquals(2, disconnected.surfaceRevision)

        val browserTarget = WindowProjectionTarget(
            targetId = "browser-laptop",
            kind = WindowProjectionTargetKind.Browser,
            displaySessionId = "display-browser",
        )
        val resumed = projection(registry.resume(identity.windowId, browserTarget, 2))

        assertEquals(WindowProjectionState.Restored, resumed.state)
        assertEquals(identity.windowId, resumed.identity.windowId)
        assertEquals(identity.workspaceId, resumed.identity.workspaceId)
        assertEquals(identity.hostSessionId, resumed.identity.hostSessionId)
        assertEquals(2, resumed.identity.generation)
        assertEquals(browserTarget, resumed.target)
        assertEquals("host", resumed.computeLocation)
        assertEquals(2, resumed.surfaceRevision)
    }

    @Test
    fun rejectsDuplicateWindowsAndTargetConflicts() {
        val registry = registry()
        projection(registry.begin(identity, castTarget))

        val duplicate = failure(
            registry.begin(
                identity,
                WindowProjectionTarget("android-phone", WindowProjectionTargetKind.Android, "display-android"),
            ),
        )
        assertEquals(WindowProjectionFailureCode.DuplicateWindow, duplicate.code)

        val conflict = failure(
            registry.begin(
                identity.copy(windowId = "window-terminal", title = "Terminal"),
                castTarget,
            ),
        )
        assertEquals(WindowProjectionFailureCode.TargetConflict, conflict.code)
    }

    @Test
    fun rejectsStaleGenerationAndRevision() {
        val registry = registry()
        projection(registry.begin(identity, castTarget))
        projection(registry.acknowledgeSurface(identity.windowId, 5))

        val staleSurface = failure(registry.acknowledgeSurface(identity.windowId, 5))
        assertEquals(WindowProjectionFailureCode.StaleRevision, staleSurface.code)

        projection(registry.disconnect(identity.windowId, "network"))
        val staleGeneration = failure(registry.resume(identity.windowId, castTarget, 0))
        assertEquals(WindowProjectionFailureCode.StaleGeneration, staleGeneration.code)
    }

    @Test
    fun releaseClearsProjectionAndAllowsReuse() {
        val registry = registry()
        projection(registry.begin(identity, castTarget))
        val released = projection(registry.release(identity.windowId))

        assertEquals(WindowProjectionState.Released, released.state)
        assertTrue(registry.list().isEmpty())
        projection(registry.begin(identity, castTarget))
    }

    private fun registry(): WindowProjectionRegistry {
        var now = 1_000L
        return WindowProjectionRegistry {
            now += 1
            now
        }
    }

    private fun projection(result: WindowProjectionResult): WindowProjection =
        when (result) {
            is WindowProjectionResult.Success -> result.projection
            is WindowProjectionResult.Failure -> error(result.error.message)
        }

    private fun failure(result: WindowProjectionResult): WindowProjectionError =
        when (result) {
            is WindowProjectionResult.Success -> error("expected failure")
            is WindowProjectionResult.Failure -> result.error
        }
}
