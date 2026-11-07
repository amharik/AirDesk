package com.airdesk.android.capabilities

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CapabilityRegistryTest {
    private val capUri = "airdesk://media/camera/capture"

    private fun descriptor(
        capUri: String = this.capUri,
        version: Int = 1,
        providerDeviceId: String = "dev-a",
        permissions: List<String> = listOf("android.permission.CAMERA"),
        execution: String = "on-device-capture",
        transport: String = "websocket",
        constraints: String = "{\"streaming\":false}",
        availability: Availability = Availability.AVAILABLE,
        authorization: Authorization = Authorization.GRANTED,
        label: String = "Camera capture",
        summary: String = "Camera permission and hardware state.",
        note: String = "Capture streaming is not implemented.",
    ): CapabilityDescriptor = CapabilityDescriptor(
        capUri = capUri,
        version = version,
        providerDeviceId = providerDeviceId,
        label = label,
        summary = summary,
        availability = availability,
        authorization = authorization,
        permissions = permissions,
        execution = execution,
        transport = transport,
        constraints = constraints,
        note = note,
    )

    private fun assertInvalid(
        expected: CapabilityRegistryError.Code,
        registry: CapabilityRegistry,
        descriptor: CapabilityDescriptor,
    ) {
        val error = assertThrows(CapabilityRegistryError::class.java) {
            registry.register(descriptor)
        }
        assertEquals(expected, error.code)
    }

    @Test
    fun registersReplacesAndSortsDescriptors() {
        val registry = CapabilityRegistry()
        assertTrue(registry.register(descriptor()))
        assertEquals(1, registry.size)
        assertFalse(registry.register(descriptor(constraints = "{\"streaming\":true}")))
        assertEquals(1, registry.size)
        assertEquals(
            "{\"streaming\":true}",
            registry.descriptor("dev-a", capUri, 1)?.constraints,
        )

        assertTrue(
            registry.register(
                descriptor(capUri = "airdesk://display/output", providerDeviceId = "dev-b"),
            ),
        )
        assertTrue(
            registry.register(
                descriptor(capUri = "airdesk://display/output", providerDeviceId = "dev-a"),
            ),
        )

        val descriptors = registry.descriptors()
        assertEquals(
            listOf(
                "airdesk://display/output",
                "airdesk://display/output",
                "airdesk://media/camera/capture",
            ),
            descriptors.map { it.capUri },
        )
        assertEquals(listOf("dev-a", "dev-b"), descriptors.take(2).map { it.providerDeviceId })
    }

    @Test
    fun rejectsMalformedDescriptors() {
        val registry = CapabilityRegistry()
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_PROVIDER_DEVICE_ID,
            registry,
            descriptor(providerDeviceId = " "),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_CAP_URI,
            registry,
            descriptor(capUri = "https://media/camera/capture"),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_CAP_URI,
            registry,
            descriptor(capUri = "airdesk://media//capture"),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_VERSION,
            registry,
            descriptor(version = 0),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_PERMISSIONS,
            registry,
            descriptor(permissions = listOf("camera", "camera")),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_PERMISSIONS,
            registry,
            descriptor(permissions = listOf(" ")),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_EXECUTION,
            registry,
            descriptor(execution = ""),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_TRANSPORT,
            registry,
            descriptor(transport = ""),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_CONSTRAINTS,
            registry,
            descriptor(constraints = "not-json"),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_CONSTRAINTS,
            registry,
            descriptor(constraints = "[]"),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_CONSTRAINTS,
            registry,
            descriptor(constraints = "{\"nested\":{\"enabled\":true}}"),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_CONSTRAINTS,
            registry,
            descriptor(constraints = "{\"values\":[1,2]}"),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_LABEL,
            registry,
            descriptor(label = ""),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_SUMMARY,
            registry,
            descriptor(summary = ""),
        )
        assertInvalid(
            CapabilityRegistryError.Code.INVALID_NOTE,
            registry,
            descriptor(note = ""),
        )
        assertEquals(0, registry.size)
    }

    @Test
    fun keepsAvailabilityAndAuthorizationIndependent() {
        val registry = CapabilityRegistry()
        registry.register(descriptor())

        assertTrue(registry.updateAvailability("dev-a", capUri, 1, Availability.BUSY))
        assertEquals(Availability.BUSY, registry.descriptors().first().availability)
        assertEquals(Authorization.GRANTED, registry.descriptors().first().authorization)

        assertTrue(registry.updateAuthorization("dev-a", capUri, 1, Authorization.REVOKED))
        assertEquals(Availability.BUSY, registry.descriptors().first().availability)
        assertEquals(Authorization.REVOKED, registry.descriptors().first().authorization)

        assertFalse(registry.updateAvailability("dev-b", capUri, 1, Availability.BUSY))
        assertFalse(registry.updateAuthorization("dev-a", capUri, 2, Authorization.GRANTED))
    }

    @Test
    fun removesByVersionAndClearsRegistry() {
        val registry = CapabilityRegistry()
        registry.register(descriptor(version = 1))
        registry.register(descriptor(version = 2))

        assertEquals(1, registry.remove("dev-a", capUri, 1))
        assertEquals(1, registry.size)
        assertEquals(1, registry.remove("dev-a", capUri))
        assertEquals(0, registry.size)
        assertNull(registry.descriptor("dev-a", capUri, 2))

        registry.register(descriptor())
        registry.clear()
        assertEquals(0, registry.size)
    }
}
