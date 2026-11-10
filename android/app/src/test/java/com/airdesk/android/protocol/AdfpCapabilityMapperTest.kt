package com.airdesk.android.protocol

import AirDesk.Protocol.Authorization as ProtocolAuthorization
import AirDesk.Protocol.Availability as ProtocolAvailability
import AirDesk.Protocol.SenderRole
import com.airdesk.android.capabilities.Authorization
import com.airdesk.android.capabilities.Availability
import com.airdesk.android.capabilities.CapabilityCatalog
import com.airdesk.android.capabilities.CapabilityDescriptor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AdfpCapabilityMapperTest {
    private val provider = "ad-device:" + "b".repeat(64)
    private val header = AdfpControlHeader(
        messageId = "capability-1",
        senderDeviceId = provider,
        senderRole = SenderRole.agent,
    )

    @Test
    fun mapsEveryAvailabilityValue() {
        val expectations = mapOf(
            Availability.AVAILABLE to ProtocolAvailability.available,
            Availability.BUSY to ProtocolAvailability.busy,
            Availability.RESTRICTED to ProtocolAvailability.restricted,
            Availability.UNAVAILABLE to ProtocolAvailability.unavailable,
        )
        expectations.forEach { (android, protocol) ->
            assertEquals(protocol, AdfpCapabilityMapper.availabilityToProtocol(android))
            assertEquals(android, AdfpCapabilityMapper.availabilityFromProtocol(protocol))
        }
    }

    @Test
    fun mapsEveryAuthorizationValueWithoutPairingGrants() {
        val expectations = mapOf(
            Authorization.UNGRANTED to ProtocolAuthorization.ungranted,
            Authorization.GRANTED to ProtocolAuthorization.granted,
            Authorization.DENIED to ProtocolAuthorization.denied,
            Authorization.REVOKED to ProtocolAuthorization.revoked,
        )
        expectations.forEach { (android, protocol) ->
            assertEquals(protocol, AdfpCapabilityMapper.authorizationToProtocol(android))
            assertEquals(android, AdfpCapabilityMapper.authorizationFromProtocol(protocol))
        }
    }

    @Test
    fun unmappedProtocolEnumValuesReturnNull() {
        assertNull(AdfpCapabilityMapper.availabilityFromProtocol(ProtocolAvailability.unknown))
        assertNull(AdfpCapabilityMapper.authorizationFromProtocol(ProtocolAuthorization.unknown))
        assertNull(AdfpCapabilityMapper.availabilityFromProtocol(99u))
        assertNull(AdfpCapabilityMapper.authorizationFromProtocol(99u))
    }

    @Test
    fun mapsAndroidDescriptorsAndRoundTripsAsPayload() {
        val camera = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = true,
            cameraPermissionGranted = false,
        ).first { it.capUri == "airdesk://media/camera/capture" }
        val mapped = AdfpCapabilityMapper.toProtocol(camera)

        assertEquals(camera.capUri, mapped.capUri)
        assertEquals(camera.version.toUInt(), mapped.version)
        assertEquals(provider, mapped.providerDeviceId)
        assertEquals(ProtocolAvailability.available, mapped.availability)
        assertEquals(ProtocolAuthorization.ungranted, mapped.authorization)
        assertEquals(camera.permissions, mapped.permissions)
        assertEquals(camera.execution, mapped.execution)
        assertEquals(camera.transport, mapped.transport)
        assertEquals(camera.constraints, mapped.constraints)

        val decoded = AdfpProtocol.decode(
            AdfpProtocol.encodeCapabilityDescriptor(header, mapped),
        ).payload as AdfpPayload.CapabilityDescriptor
        assertEquals(mapped, decoded.descriptor)
        assertEquals(Authorization.UNGRANTED, AdfpCapabilityMapper.authorizationFromProtocol(decoded.descriptor.authorization))
    }

    @Test
    fun seededCapabilitiesNeverMapToGranted() {
        val mapped = CapabilityCatalog.seed(
            providerDeviceId = provider,
            cameraHardware = true,
            cameraPermissionGranted = true,
        ).map(AdfpCapabilityMapper::toProtocol)

        assertTrue(mapped.isNotEmpty())
        assertTrue(mapped.none { it.authorization == ProtocolAuthorization.granted })
    }
}
