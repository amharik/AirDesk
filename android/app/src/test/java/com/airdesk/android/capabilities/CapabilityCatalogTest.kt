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

        assertEquals(Availability.AVAILABLE, camera.availability)
        assertEquals(Authorization.UNGRANTED, camera.authorization)
        assertTrue(capabilities.all { it.authorization == Authorization.UNGRANTED })
    }

    @Test
    fun cameraPermissionDoesNotChangeAvailabilityOrGrantCapability() {
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
                "airdesk://fs/documents/read",
                "airdesk://fs/documents/write",
                "airdesk://health/status",
            ),
            capabilities.map { it.capUri }.toSet(),
        )
        assertTrue(capabilities.all { it.providerDeviceId == provider })
        assertTrue(capabilities.none { it.authorization == Authorization.GRANTED })
    }

    @Test
    fun documentsUseCanonicalReadAndWriteUrisWithoutBroadFilesystemAccess() {
        val documents = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = true,
            cameraPermissionGranted = false,
        ).filter { it.capUri.startsWith("airdesk://fs/") }

        assertEquals(
            listOf(
                CapabilityCatalog.DOCUMENTS_READ_CAP_URI,
                CapabilityCatalog.DOCUMENTS_WRITE_CAP_URI,
            ),
            documents.map { it.capUri },
        )
        assertTrue(documents.none { it.capUri == "airdesk://fs/read" })
        assertEquals(
            listOf("on-device-read", "on-device-write"),
            documents.map { it.execution },
        )
        assertTrue(documents.all { it.permissions.isEmpty() })
        assertTrue(documents.all {
            it.constraints.contains("\"scope\":\"app-documents\"") &&
                it.constraints.contains("\"userSelectedOnly\":true") &&
                it.constraints.contains("\"deviceWideAccess\":false")
        })
        assertTrue(documents.all { it.authorization == Authorization.UNGRANTED })
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
