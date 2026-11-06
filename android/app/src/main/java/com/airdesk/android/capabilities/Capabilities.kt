package com.airdesk.android.capabilities

enum class Availability {
    AVAILABLE,
    BUSY,
    RESTRICTED,
    UNAVAILABLE,
}

enum class Authorization {
    UNGRANTED,
    GRANTED,
    DENIED,
    REVOKED,
}

data class CapabilityDescriptor(
    val capUri: String,
    val providerDeviceId: String,
    val label: String,
    val summary: String,
    val availability: Availability,
    val authorization: Authorization,
    val permissions: List<String>,
    val note: String,
)

object CapabilityCatalog {
    const val CAMERA_PERMISSION = "android.permission.CAMERA"

    fun seed(
        providerDeviceId: String,
        cameraHardware: Boolean,
        cameraPermissionGranted: Boolean,
    ): List<CapabilityDescriptor> {
        val cameraAvailability = when {
            !cameraHardware -> Availability.UNAVAILABLE
            !cameraPermissionGranted -> Availability.RESTRICTED
            else -> Availability.AVAILABLE
        }
        return listOf(
            CapabilityDescriptor(
                capUri = "airdesk://display/output",
                providerDeviceId = providerDeviceId,
                label = "Display output",
                summary = "Local DesktopShell presentation surface.",
                availability = Availability.AVAILABLE,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                note = "Local WebView presentation works; remote display transport is deferred.",
            ),
            CapabilityDescriptor(
                capUri = "airdesk://input/pointer",
                providerDeviceId = providerDeviceId,
                label = "Pointer input",
                summary = "Touch and pointer events on the local presentation.",
                availability = Availability.AVAILABLE,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                note = "Local surface only; ADFP input routing is not connected.",
            ),
            CapabilityDescriptor(
                capUri = "airdesk://input/keyboard",
                providerDeviceId = providerDeviceId,
                label = "Keyboard input",
                summary = "Local text input surface.",
                availability = Availability.RESTRICTED,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                note = "Local text input exists; remote keyboard transport is not connected.",
            ),
            CapabilityDescriptor(
                capUri = "airdesk://media/camera/capture",
                providerDeviceId = providerDeviceId,
                label = "Camera capture",
                summary = "Camera permission and hardware state reported truthfully.",
                availability = cameraAvailability,
                authorization = Authorization.UNGRANTED,
                permissions = listOf(CAMERA_PERMISSION),
                note = if (cameraPermissionGranted) {
                    "Camera permission granted; capture transport is not implemented in this baseline."
                } else {
                    "Camera permission not granted; availability is restricted, not authorized."
                },
            ),
            CapabilityDescriptor(
                capUri = "airdesk://fs/read",
                providerDeviceId = providerDeviceId,
                label = "Files read",
                summary = "Scoped app-private documents only.",
                availability = Availability.RESTRICTED,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                note = "No device-wide filesystem. Remote file transport is not implemented.",
            ),
            CapabilityDescriptor(
                capUri = "airdesk://health/status",
                providerDeviceId = providerDeviceId,
                label = "Health",
                summary = "Local identity, capability and permission diagnostics.",
                availability = Availability.AVAILABLE,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                note = "Health is displayed locally; remote health subscription is deferred.",
            ),
        )
    }
}
