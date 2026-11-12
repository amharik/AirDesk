package com.airdesk.android.workspace

enum class WindowProjectionTargetKind(val wire: String) {
    Cast("cast"),
    Browser("browser"),
    Android("android"),
}

enum class WindowProjectionState(val wire: String) {
    Projecting("projecting"),
    Reconnecting("reconnecting"),
    Restored("restored"),
    Released("released"),
    Failed("failed"),
}

enum class WindowProjectionFailureCode(val wire: String) {
    InvalidIdentity("invalid-identity"),
    InvalidTarget("invalid-target"),
    DuplicateWindow("duplicate-window"),
    TargetConflict("target-conflict"),
    NotFound("not-found"),
    IllegalState("illegal-state"),
    StaleGeneration("stale-generation"),
    StaleRevision("stale-revision"),
}

data class WindowProjectionIdentity(
    val windowId: String,
    val workspaceId: String,
    val title: String,
    val hostSessionId: String,
    val generation: Int,
)

data class WindowProjectionTarget(
    val targetId: String,
    val kind: WindowProjectionTargetKind,
    val displaySessionId: String,
)

data class WindowProjection(
    val identity: WindowProjectionIdentity,
    val target: WindowProjectionTarget,
    val state: WindowProjectionState,
    val surfaceRevision: Int,
    val computeLocation: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
    val lastError: String? = null,
)

data class WindowProjectionError(
    val code: WindowProjectionFailureCode,
    val message: String,
)

sealed class WindowProjectionResult {
    data class Success(val projection: WindowProjection) : WindowProjectionResult()
    data class Failure(val error: WindowProjectionError) : WindowProjectionResult()
}

class WindowProjectionRegistry(
    private val nowEpochMillis: () -> Long = { System.currentTimeMillis() },
) {
    private val projections = mutableMapOf<String, WindowProjection>()
    private val targets = mutableMapOf<String, String>()

    fun begin(
        identity: WindowProjectionIdentity,
        target: WindowProjectionTarget,
    ): WindowProjectionResult {
        if (!isValid(identity)) {
            return failure(WindowProjectionFailureCode.InvalidIdentity, "Window identity is invalid.")
        }
        if (!isValid(target)) {
            return failure(WindowProjectionFailureCode.InvalidTarget, "Projection target is invalid.")
        }
        val existing = projections[identity.windowId]
        if (existing != null &&
            existing.state != WindowProjectionState.Released &&
            existing.state != WindowProjectionState.Failed
        ) {
            return failure(
                WindowProjectionFailureCode.DuplicateWindow,
                "Window ${identity.windowId} is already projecting.",
            )
        }
        val owner = targets[target.displaySessionId]
        if (owner != null && owner != identity.windowId) {
            return failure(
                WindowProjectionFailureCode.TargetConflict,
                "Display ${target.displaySessionId} is already projecting window $owner.",
            )
        }
        val timestamp = nowEpochMillis()
        val projection = WindowProjection(
            identity = identity,
            target = target,
            state = WindowProjectionState.Projecting,
            surfaceRevision = 0,
            computeLocation = "host",
            createdAtEpochMillis = timestamp,
            updatedAtEpochMillis = timestamp,
        )
        projections[identity.windowId] = projection
        targets[target.displaySessionId] = identity.windowId
        return WindowProjectionResult.Success(projection)
    }

    fun acknowledgeSurface(windowId: String, revision: Int): WindowProjectionResult {
        val projection = projections[windowId] ?: return notFound(windowId)
        if (projection.state != WindowProjectionState.Projecting &&
            projection.state != WindowProjectionState.Restored
        ) {
            return failure(
                WindowProjectionFailureCode.IllegalState,
                "Window $windowId cannot accept surfaces while ${projection.state.wire}.",
            )
        }
        if (revision < 1) {
            return failure(
                WindowProjectionFailureCode.StaleRevision,
                "Surface revision must be a positive integer.",
            )
        }
        if (revision <= projection.surfaceRevision) {
            return failure(
                WindowProjectionFailureCode.StaleRevision,
                "Surface revision $revision is not newer than ${projection.surfaceRevision}.",
            )
        }
        val updated = projection.copy(
            surfaceRevision = revision,
            updatedAtEpochMillis = nowEpochMillis(),
        )
        projections[windowId] = updated
        return WindowProjectionResult.Success(updated)
    }

    fun disconnect(windowId: String, reason: String): WindowProjectionResult {
        val projection = projections[windowId] ?: return notFound(windowId)
        if (projection.state == WindowProjectionState.Reconnecting) {
            return WindowProjectionResult.Success(projection)
        }
        if (projection.state != WindowProjectionState.Projecting &&
            projection.state != WindowProjectionState.Restored
        ) {
            return failure(
                WindowProjectionFailureCode.IllegalState,
                "Window $windowId cannot disconnect from ${projection.state.wire}.",
            )
        }
        val updated = projection.copy(
            state = WindowProjectionState.Reconnecting,
            lastError = reason,
            updatedAtEpochMillis = nowEpochMillis(),
        )
        projections[windowId] = updated
        return WindowProjectionResult.Success(updated)
    }

    fun resume(
        windowId: String,
        target: WindowProjectionTarget,
        generation: Int,
    ): WindowProjectionResult {
        val projection = projections[windowId] ?: return notFound(windowId)
        if (projection.state != WindowProjectionState.Reconnecting) {
            return failure(
                WindowProjectionFailureCode.IllegalState,
                "Window $windowId is not reconnecting.",
            )
        }
        if (!isValid(target)) {
            return failure(WindowProjectionFailureCode.InvalidTarget, "Projection target is invalid.")
        }
        if (generation < projection.identity.generation) {
            return failure(
                WindowProjectionFailureCode.StaleGeneration,
                "Reconnect generation is stale.",
            )
        }
        val owner = targets[target.displaySessionId]
        if (owner != null && owner != windowId) {
            return failure(
                WindowProjectionFailureCode.TargetConflict,
                "Display ${target.displaySessionId} is already projecting window $owner.",
            )
        }
        if (target.displaySessionId != projection.target.displaySessionId) {
            targets.remove(projection.target.displaySessionId)
            targets[target.displaySessionId] = windowId
        }
        val updated = projection.copy(
            identity = projection.identity.copy(generation = generation),
            target = target,
            state = WindowProjectionState.Restored,
            lastError = null,
            updatedAtEpochMillis = nowEpochMillis(),
        )
        projections[windowId] = updated
        return WindowProjectionResult.Success(updated)
    }

    fun release(windowId: String): WindowProjectionResult {
        val projection = projections[windowId] ?: return notFound(windowId)
        if (projection.state == WindowProjectionState.Released) {
            return WindowProjectionResult.Success(projection)
        }
        targets.remove(projection.target.displaySessionId)
        val updated = projection.copy(
            state = WindowProjectionState.Released,
            updatedAtEpochMillis = nowEpochMillis(),
        )
        projections[windowId] = updated
        return WindowProjectionResult.Success(updated)
    }

    fun fail(windowId: String, reason: String): WindowProjectionResult {
        val projection = projections[windowId] ?: return notFound(windowId)
        targets.remove(projection.target.displaySessionId)
        val updated = projection.copy(
            state = WindowProjectionState.Failed,
            lastError = reason,
            updatedAtEpochMillis = nowEpochMillis(),
        )
        projections[windowId] = updated
        return WindowProjectionResult.Success(updated)
    }

    fun get(windowId: String): WindowProjection? = projections[windowId]

    fun list(): List<WindowProjection> =
        projections.values
            .filter { it.state != WindowProjectionState.Released }
            .sortedBy { it.identity.windowId }

    private fun notFound(windowId: String): WindowProjectionResult =
        failure(WindowProjectionFailureCode.NotFound, "Window $windowId is not projecting.")

    private fun failure(
        code: WindowProjectionFailureCode,
        message: String,
    ): WindowProjectionResult = WindowProjectionResult.Failure(WindowProjectionError(code, message))

    private fun isValid(identity: WindowProjectionIdentity): Boolean =
        isValidIdentifier(identity.windowId) &&
            isValidIdentifier(identity.workspaceId) &&
            isValidIdentifier(identity.hostSessionId) &&
            identity.title.trim().isNotEmpty() &&
            identity.title.length <= 256 &&
            identity.generation >= 0

    private fun isValid(target: WindowProjectionTarget): Boolean =
        WindowProjectionTargetKind.entries.contains(target.kind) &&
            isValidIdentifier(target.targetId) &&
            isValidIdentifier(target.displaySessionId)

    private fun isValidIdentifier(value: String): Boolean =
        IDENTIFIER.matches(value)

    private companion object {
        val IDENTIFIER = Regex("^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
    }
}
