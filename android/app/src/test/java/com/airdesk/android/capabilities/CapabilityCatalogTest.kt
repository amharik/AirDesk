package com.airdesk.android.capabilities

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CapabilityCatalogTest {
    private val provider = "ad-device:" + "a".repeat(64)

    @Test
    fun availabilityAndAuthorizationAreSeparateAxes() {
        val capabilities = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = true,
            cameraPermissionGranted = false,
        )
        val camera = capabilities.first { it.capUri == "airdesk://media/camera/capture" }

        assertEquals(Availability.RESTRICTED, camera.availability)
        assertEquals(Authorization.UNGRANTED, camera.authorization)
        assertTrue(capabilities.all { it.authorization == Authorization.UNGRANTED })
    }

    @Test
    fun cameraAvailabilityReflectsPermissionWithoutGrantingIt() {
        val withPermission = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = true,
            cameraPermissionGranted = true,
        ).first { it.capUri == "airdesk://media/camera/capture" }
        assertEquals(Availability.AVAILABLE, withPermission.availability)
        assertEquals(Authorization.UNGRANTED, withPermission.authorization)

        val withoutHardware = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = false,
            cameraPermissionGranted = true,
        ).first { it.capUri == "airdesk://media/camera/capture" }
        assertEquals(Availability.UNAVAILABLE, withoutHardware.availability)
        assertEquals(Authorization.UNGRANTED, withoutHardware.authorization)
    }

    @Test
    fun seedsExpectedCapabilityUrisAndNeverClaimsGrants() {
        val capabilities = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = true,
            cameraPermissionGranted = true,
        )
        assertEquals(
            setOf(
                "airdesk://display/output",
                "airdesk://input/pointer",
                "airdesk://input/keyboard",
                "airdesk://media/camera/capture",
                "airdesk://fs/read",
                "airdesk://health/status",
            ),
            capabilities.map { it.capUri }.toSet(),
        )
        assertTrue(capabilities.all { it.providerDeviceId == provider })
        assertTrue(capabilities.none { it.authorization == Authorization.GRANTED })
    }

    @Test
    fun availableCapabilityIsNotAutomaticallyGranted() {
        val display = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = false,
            cameraPermissionGranted = false,
        ).first { it.capUri == "airdesk://display/output" }

        assertEquals(Availability.AVAILABLE, display.availability)
        assertEquals(Authorization.UNGRANTED, display.authorization)
    }
}
