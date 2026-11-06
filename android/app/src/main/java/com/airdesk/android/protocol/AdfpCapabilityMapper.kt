package com.airdesk.android.protocol

import AirDesk.Protocol.Availability as ProtocolAvailability
import AirDesk.Protocol.Authorization as ProtocolAuthorization
import com.airdesk.android.capabilities.Authorization
import com.airdesk.android.capabilities.Availability
import com.airdesk.android.capabilities.CapabilityDescriptor as AndroidCapabilityDescriptor

object AdfpCapabilityMapper {
    const val CAPABILITY_VERSION: UInt = 1u

    fun toProtocol(descriptor: AndroidCapabilityDescriptor): AdfpCapabilityDescriptor =
        AdfpCapabilityDescriptor(
            capUri = descriptor.capUri,
            version = CAPABILITY_VERSION,
            providerDeviceId = descriptor.providerDeviceId,
            availability = availabilityToProtocol(descriptor.availability),
            authorization = authorizationToProtocol(descriptor.authorization),
            permissions = descriptor.permissions,
            execution = null,
            transport = null,
            constraints = descriptor.note,
        )

    fun availabilityToProtocol(value: Availability): UByte = when (value) {
        Availability.AVAILABLE -> ProtocolAvailability.available
        Availability.BUSY -> ProtocolAvailability.busy
        Availability.RESTRICTED -> ProtocolAvailability.restricted
        Availability.UNAVAILABLE -> ProtocolAvailability.unavailable
    }

    fun authorizationToProtocol(value: Authorization): UByte = when (value) {
        Authorization.UNGRANTED -> ProtocolAuthorization.ungranted
        Authorization.GRANTED -> ProtocolAuthorization.granted
        Authorization.DENIED -> ProtocolAuthorization.denied
        Authorization.REVOKED -> ProtocolAuthorization.revoked
    }

    fun availabilityFromProtocol(value: UByte): Availability? = when (value) {
        ProtocolAvailability.available -> Availability.AVAILABLE
        ProtocolAvailability.busy -> Availability.BUSY
        ProtocolAvailability.restricted -> Availability.RESTRICTED
        ProtocolAvailability.unavailable -> Availability.UNAVAILABLE
        else -> null
    }

    fun authorizationFromProtocol(value: UByte): Authorization? = when (value) {
        ProtocolAuthorization.ungranted -> Authorization.UNGRANTED
        ProtocolAuthorization.granted -> Authorization.GRANTED
        ProtocolAuthorization.denied -> Authorization.DENIED
        ProtocolAuthorization.revoked -> Authorization.REVOKED
        else -> null
    }
}
