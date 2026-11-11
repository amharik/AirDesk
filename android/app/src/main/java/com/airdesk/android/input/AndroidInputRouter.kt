package com.airdesk.android.input

class AndroidInputRouter(
    private val leases: InputLeaseRegistry,
    private val frameSink: (PackedMovementFrame) -> Unit = {},
    private val frameIntervalNanos: Long = 1_000_000_000L / 120L,
) {
    var cursorX: Double = 0.5
        private set
    var cursorY: Double = 0.5
        private set
    var viewportWidthPx: Double = 1.0
        private set
    var viewportHeightPx: Double = 1.0
        private set
    var buttonMask: Int = 0
        private set
    var sequence: Long = 0
        private set

    private var activeLease: InputLease? = null
    private var activeOwner: String? = null
    private var pendingX = 0.0
    private var pendingY = 0.0
    private var hasPending = false
    private var lastTickNanos: Long? = null

    val isActive: Boolean
        get() = activeLease != null

    val activeLeaseId: String?
        get() = activeLease?.leaseId

    fun setViewport(widthPx: Double, heightPx: Double) {
        if (!widthPx.isFinite() || !heightPx.isFinite() || widthPx <= 0 || heightPx <= 0) {
            return
        }
        viewportWidthPx = widthPx
        viewportHeightPx = heightPx
    }

    @Synchronized
    fun activate(leaseId: String, owner: String): InputLease {
        val current = activeLease
        if (current != null) {
            if (current.leaseId == leaseId && activeOwner == owner) return current
            throw InputLeaseException(
                InputLeaseErrorCode.LEASE_BUSY,
                "LeaseBusy: the input surface already has an active controller.",
            )
        }
        val candidate = leases.lease(leaseId)
            ?: throw InputLeaseException(
                InputLeaseErrorCode.LEASE_DENIED,
                "LeaseDenied: no matching input lease.",
            )
        val lease = leases.authorize(leaseId, owner, candidate.epochLow)
        activeLease = lease
        activeOwner = owner
        sequence = 0
        buttonMask = 0
        pendingX = 0.0
        pendingY = 0.0
        hasPending = false
        lastTickNanos = null
        return lease
    }

    @Synchronized
    fun submitMove(deltaXPixels: Double, deltaYPixels: Double): Boolean {
        val lease = activeLease ?: return false
        if (!deltaXPixels.isFinite() || !deltaYPixels.isFinite()) return false
        if (!validate(lease)) return false
        pendingX += deltaXPixels / viewportWidthPx
        pendingY += deltaYPixels / viewportHeightPx
        hasPending = true
        return true
    }

    @Synchronized
    fun setButton(button: Int, pressed: Boolean): Boolean {
        val lease = activeLease ?: return false
        if (button !in 0..2) return false
        if (!validate(lease)) return false
        buttonMask = if (pressed) {
            buttonMask or (1 shl button)
        } else {
            buttonMask and (1 shl button).inv()
        }
        hasPending = true
        return true
    }

    @Synchronized
    fun tick(timestampNanos: Long = System.nanoTime()): PackedMovementFrame? {
        val lease = activeLease ?: return null
        if (!validate(lease)) return null
        val elapsed = lastTickNanos?.let { timestampNanos - it } ?: frameIntervalNanos
        if (elapsed < frameIntervalNanos) return null
        lastTickNanos = timestampNanos
        if (!hasPending) return null

        cursorX = (cursorX + pendingX).coerceIn(0.0, 1.0)
        cursorY = (cursorY + pendingY).coerceIn(0.0, 1.0)
        pendingX = 0.0
        pendingY = 0.0
        hasPending = false
        return emit(buttonMask)
    }

    @Synchronized
    fun deactivate(): PackedMovementFrame? = cancel()

    @Synchronized
    fun cancel(): PackedMovementFrame? {
        val lease = activeLease ?: return null
        val frame = emit(0)
        buttonMask = 0
        pendingX = 0.0
        pendingY = 0.0
        hasPending = false
        lastTickNanos = null
        activeLease = null
        activeOwner?.let { leases.release(lease.leaseId, it) }
        activeOwner = null
        return frame
    }

    private fun validate(lease: InputLease): Boolean {
        return try {
            leases.validateActive(lease.leaseId, activeOwner ?: return false)
            true
        } catch (_: InputLeaseException) {
            cancel()
            false
        }
    }

    private fun emit(mask: Int): PackedMovementFrame {
        val lease = activeLease
            ?: throw IllegalStateException("cannot emit movement without an active lease")
        val frame = PackedMovementFrame(
            leaseEpochLow = lease.epochLow,
            seq = sequence,
            x = cursorX.toFloat(),
            y = cursorY.toFloat(),
            buttonMask = mask,
        )
        sequence = (sequence + 1L) and 0xffff_ffffL
        frameSink(frame)
        return frame
    }
}
