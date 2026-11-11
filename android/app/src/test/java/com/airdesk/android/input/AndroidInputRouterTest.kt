package com.airdesk.android.input

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidInputRouterTest {
    private var nowMillis = 1_000L
    private val registry = InputLeaseRegistry(now = { nowMillis })
    private val frames = mutableListOf<PackedMovementFrame>()
    private val router = AndroidInputRouter(registry, frameSink = { frames.add(it) })
    private val interval = 1_000_000_000L / 120L

    @Test
    fun localCursorEmitsAtMostOnePackedFramePer120HzInterval() {
        val lease = lease()
        registry.grant(lease)
        router.setViewport(1_000.0, 1_000.0)
        router.activate(lease.leaseId, lease.controllerDeviceId)

        var timestamp = 0L
        repeat(240) {
            assertTrue(router.submitMove(1.0, 0.0))
            timestamp += (interval + 1) / 2
            router.tick(timestamp)
        }

        assertEquals(120, frames.size)
        assertEquals(120L, router.sequence)
        assertEquals(0.739, router.cursorX, 0.0001)
        assertEquals(0.5, router.cursorY, 0.0001)
        val decoded = PackedMovementFrame.decode(frames.last().encode())
        assertEquals(7, decoded.leaseEpochLow)
        assertEquals(0.739f, decoded.x, 0.0001f)
        assertEquals(0.5f, decoded.y, 0.0001f)
        assertEquals(119L, decoded.seq)
    }

    @Test
    fun onlyOneControllerCanOwnTheInputSurface() {
        val first = lease(leaseId = "lease-a", controller = "controller-a")
        val second = lease(leaseId = "lease-b", controller = "controller-b")
        registry.grant(first)
        registry.grant(second)
        router.activate(first.leaseId, first.controllerDeviceId)

        val busy = assertThrows(InputLeaseException::class.java) {
            router.activate(second.leaseId, second.controllerDeviceId)
        }
        assertEquals(InputLeaseErrorCode.LEASE_BUSY, busy.code)
        assertEquals("controller-a", registry.activeOwner())

        router.deactivate()
        router.activate(second.leaseId, second.controllerDeviceId)
        assertEquals("controller-b", registry.activeOwner())
    }

    @Test
    fun revocationEmitsReleaseAndClearsStuckButtons() {
        val lease = lease()
        registry.grant(lease)
        router.activate(lease.leaseId, lease.controllerDeviceId)
        assertTrue(router.setButton(0, pressed = true))
        router.submitMove(10.0, 10.0)
        val pressed = router.tick(interval)!!
        assertEquals(1, pressed.buttonMask)

        registry.revoke(lease.leaseId)
        assertNull(router.tick(interval * 2))
        assertFalse(router.isActive)
        assertEquals(0, frames.last().buttonMask)
        assertNull(registry.activeOwner())
    }

    @Test
    fun expiryAndDeactivateReleaseHeldButtons() {
        val expiring = lease(expiresAt = 2_000L)
        registry.grant(expiring)
        router.activate(expiring.leaseId, expiring.controllerDeviceId)
        router.setButton(0, pressed = true)
        router.submitMove(5.0, 5.0)
        router.tick(interval)

        nowMillis = 2_000L
        assertNull(router.tick(interval * 2))
        assertFalse(router.isActive)
        assertEquals(0, frames.last().buttonMask)

        val second = lease(leaseId = "lease-2")
        registry.grant(second)
        router.activate(second.leaseId, second.controllerDeviceId)
        router.setButton(1, pressed = true)
        val release = router.deactivate()!!
        assertEquals(0, release.buttonMask)
        assertFalse(router.isActive)
        assertFalse(registry.isActive(second.leaseId, second.controllerDeviceId))
    }

    @Test
    fun inactiveRouterRejectsMoveAndEpochMismatchIsDenied() {
        assertFalse(router.submitMove(1.0, 1.0))
        assertNull(router.tick(interval))

        val lease = lease()
        registry.grant(lease)
        val mismatch = assertThrows(InputLeaseException::class.java) {
            registry.authorize(lease.leaseId, lease.controllerDeviceId, lease.epochLow + 1)
        }
        assertEquals(InputLeaseErrorCode.LEASE_DENIED, mismatch.code)

        val wrongOwner = assertThrows(InputLeaseException::class.java) {
            registry.authorize(lease.leaseId, "controller-b", lease.epochLow)
        }
        assertEquals(InputLeaseErrorCode.LEASE_DENIED, wrongOwner.code)
    }

    private fun lease(
        leaseId: String = "lease-1",
        controller: String = "controller-a",
        expiresAt: Long? = null,
    ): InputLease = InputLease(
        leaseId = leaseId,
        controllerDeviceId = controller,
        workspaceId = "workspace-1",
        applicationId = "com.example.editor",
        sessionId = "session-1",
        epochLow = 7,
        issuedAtEpochMillis = 1_000L,
        expiresAtEpochMillis = expiresAt,
        auditId = "audit-$leaseId",
    )
}
