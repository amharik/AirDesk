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
    val version: Int = 1,
    val providerDeviceId: String,
    val label: String,
    val summary: String,
    val availability: Availability,
    val authorization: Authorization,
    val permissions: List<String>,
    val execution: String = "",
    val transport: String = "",
    val constraints: String = "{}",
    val note: String,
    val authorizationRef: String? = null,
)

object CapabilityCatalog {
    const val CAMERA_PERMISSION = "android.permission.CAMERA"
    const val DOCUMENTS_READ_CAP_URI = "airdesk://fs/documents/read"
    const val DOCUMENTS_WRITE_CAP_URI = "airdesk://fs/documents/write"

    fun seed(
        providerDeviceId: String,
        cameraHardware: Boolean,
        cameraPermissionGranted: Boolean,
    ): List<CapabilityDescriptor> {
        val cameraAvailability = if (cameraHardware) {
            Availability.AVAILABLE
        } else {
            Availability.UNAVAILABLE
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
                execution = "local-presentation",
                transport = "local-webview",
                constraints = "{\"presentation\":\"local\",\"remoteTransport\":false}",
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
                execution = "local-input",
                transport = "local-surface-bridge",
                constraints = "{\"scope\":\"presentation-surface\",\"remoteInput\":false}",
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
                execution = "local-input",
                transport = "local-surface-bridge",
                constraints = "{\"scope\":\"presentation-surface\",\"remoteInput\":false}",
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
                execution = "on-device-capture",
                transport = "none",
                constraints = "{\"hardwareAvailable\":$cameraHardware,\"streaming\":false,\"remoteInvocation\":false}",
                note = if (cameraPermissionGranted) {
                    "Camera permission granted; capability authorization still requires an explicit grant."
                } else {
                    "Camera permission not granted; availability is unchanged and capability remains ungranted."
                },
            ),
            CapabilityDescriptor(
                capUri = DOCUMENTS_READ_CAP_URI,
                providerDeviceId = providerDeviceId,
                label = "Documents read",
                summary = "App-scoped documents and user-selected files only.",
                availability = Availability.RESTRICTED,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                execution = "on-device-read",
                transport = "none",
                constraints = "{\"scope\":\"app-documents\",\"userSelectedOnly\":true,\"deviceWideAccess\":false,\"remoteTransfer\":false}",
                note = "No device-wide filesystem. Remote file transfer is not implemented.",
            ),
            CapabilityDescriptor(
                capUri = DOCUMENTS_WRITE_CAP_URI,
                providerDeviceId = providerDeviceId,
                label = "Documents write",
                summary = "App-scoped document writes and user-selected files only.",
                availability = Availability.RESTRICTED,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                execution = "on-device-write",
                transport = "none",
                constraints = "{\"scope\":\"app-documents\",\"userSelectedOnly\":true,\"deviceWideAccess\":false,\"remoteTransfer\":false}",
                note = "No device-wide filesystem. Remote write transfer is not implemented.",
            ),
            CapabilityDescriptor(
                capUri = "airdesk://health/status",
                providerDeviceId = providerDeviceId,
                label = "Health",
                summary = "Local identity, capability and permission diagnostics.",
                availability = Availability.AVAILABLE,
                authorization = Authorization.UNGRANTED,
                permissions = emptyList(),
                execution = "local-diagnostics",
                transport = "none",
                constraints = "{\"source\":\"local-diagnostics\",\"remoteSubscription\":false}",
                note = "Health is displayed locally; remote health subscription is deferred.",
            ),
        )
    }
}
