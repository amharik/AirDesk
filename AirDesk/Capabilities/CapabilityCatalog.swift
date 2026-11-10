import Combine
import Foundation

@MainActor
final class CapabilityCatalog: ObservableObject {
    static let cameraPermission = "ios.camera.video"
    static let cameraCapUri = "airdesk://media/camera/capture"
    static let documentsCapUri = "airdesk://fs/documents/read"

    let providerDeviceId: String
    @Published private(set) var descriptors: [CapabilityDescriptor] = []

    private let camera: any CameraCapabilityProviding
    private let files: any FileAccessCapabilityProviding

    init(
        providerDeviceId: String,
        camera: any CameraCapabilityProviding = AVCameraCapabilityProvider(),
        files: any FileAccessCapabilityProviding = SystemFileAccessCapabilityProvider()
    ) {
        self.providerDeviceId = providerDeviceId
        self.camera = camera
        self.files = files
        reload()
    }

    convenience init(
        identity: DeviceIdentity,
        camera: any CameraCapabilityProviding = AVCameraCapabilityProvider(),
        files: any FileAccessCapabilityProviding = SystemFileAccessCapabilityProvider()
    ) {
        self.init(
            providerDeviceId: identity.deviceId,
            camera: camera,
            files: files
        )
    }

    var cameraPermissionStatus: CameraPermissionStatus {
        camera.permissionStatus
    }

    var cameraCanRequestAccess: Bool {
        camera.hardwareAvailable && camera.permissionStatus == .notDetermined
    }

    var cameraDescriptor: CapabilityDescriptor? {
        descriptors.first { $0.capUri == Self.cameraCapUri }
    }

    func reload() {
        let hardwareAvailable = camera.hardwareAvailable
        let permissionStatus = camera.permissionStatus
        let documentsAvailable = files.appScopedDocumentsAvailable
        descriptors = [
            displayDescriptor,
            pointerDescriptor,
            keyboardDescriptor,
            cameraDescriptor(
                hardwareAvailable: hardwareAvailable,
                permissionStatus: permissionStatus
            ),
            documentsDescriptor(available: documentsAvailable),
            healthDescriptor
        ]
    }

    @discardableResult
    func requestCameraAccess() async -> Bool {
        let status = await camera.requestPermission()
        reload()
        return status == .authorized
    }

    private var displayDescriptor: CapabilityDescriptor {
        makeDescriptor(
            capUri: "airdesk://display/output",
            execution: "local-presentation",
            transport: "local-webview",
            constraints: #"{"presentation":"local","remoteTransport":false}"#,
            availability: .available,
            authorization: .ungranted,
            label: "Display output",
            summary: "Local DesktopShell presentation surface.",
            note: "Local WebView presentation works; remote display transport is deferred."
        )
    }

    private var pointerDescriptor: CapabilityDescriptor {
        makeDescriptor(
            capUri: "airdesk://input/pointer",
            execution: "local-input",
            transport: "local-surface-bridge",
            constraints: #"{"scope":"presentation-surface","remoteInput":false}"#,
            availability: .available,
            authorization: .ungranted,
            label: "Pointer input",
            summary: "Touch and pointer events on the local presentation.",
            note: "Local surface only; ADFP input routing is not connected."
        )
    }

    private var keyboardDescriptor: CapabilityDescriptor {
        makeDescriptor(
            capUri: "airdesk://input/keyboard",
            execution: "local-input",
            transport: "local-surface-bridge",
            constraints: #"{"scope":"presentation-surface","remoteInput":false}"#,
            availability: .available,
            authorization: .ungranted,
            label: "Keyboard input",
            summary: "Local text and hardware keyboard input.",
            note: "Local text input exists; remote keyboard transport is not connected."
        )
    }

    private func cameraDescriptor(
        hardwareAvailable: Bool,
        permissionStatus: CameraPermissionStatus
    ) -> CapabilityDescriptor {
        makeDescriptor(
            capUri: Self.cameraCapUri,
            permissions: [Self.cameraPermission],
            execution: "on-device-capture",
            transport: "none",
            constraints: "{\"hardwareAvailable\":\(hardwareAvailable),\"streaming\":true,\"remoteInvocation\":false}",
            availability: cameraAvailability(
                hardwareAvailable: hardwareAvailable,
                permissionStatus: permissionStatus
            ),
            authorization: cameraAuthorization(permissionStatus),
            label: "Camera capture",
            summary: "AVFoundation camera permission and hardware state.",
            note: cameraNote(
                hardwareAvailable: hardwareAvailable,
                permissionStatus: permissionStatus
            )
        )
    }

    private func documentsDescriptor(available: Bool) -> CapabilityDescriptor {
        makeDescriptor(
            capUri: Self.documentsCapUri,
            execution: "on-device-read",
            transport: "none",
            constraints: #"{"scope":"app-documents","userSelectedOnly":true,"deviceWideAccess":false,"remoteTransfer":false}"#,
            availability: available ? .restricted : .unavailable,
            authorization: .ungranted,
            label: "Documents read",
            summary: "App-scoped documents and user-selected files only.",
            note: "No device-wide filesystem is requested. Document access is user-mediated and file transfer is not implemented."
        )
    }

    private var healthDescriptor: CapabilityDescriptor {
        makeDescriptor(
            capUri: "airdesk://health/status",
            execution: "local-diagnostics",
            transport: "none",
            constraints: #"{"source":"local-diagnostics","healthKit":false,"remoteSubscription":false}"#,
            availability: .available,
            authorization: .ungranted,
            label: "Health",
            summary: "Local identity, capability and permission diagnostics.",
            note: "Agent health is displayed locally without HealthKit or new entitlements; remote health subscription is deferred."
        )
    }

    private func makeDescriptor(
        capUri: String,
        permissions: [String] = [],
        execution: String,
        transport: String,
        constraints: String,
        availability: CapabilityAvailability,
        authorization: CapabilityAuthorization,
        label: String,
        summary: String,
        note: String
    ) -> CapabilityDescriptor {
        CapabilityDescriptor(
            capUri: capUri,
            version: CapabilityDescriptor.currentVersion,
            providerDeviceId: providerDeviceId,
            permissions: permissions,
            execution: execution,
            transport: transport,
            constraints: constraints,
            availability: availability,
            authorization: authorization,
            label: label,
            summary: summary,
            note: note
        )
    }

    private func cameraAvailability(
        hardwareAvailable: Bool,
        permissionStatus: CameraPermissionStatus
    ) -> CapabilityAvailability {
        guard hardwareAvailable else { return .unavailable }
        if permissionStatus == .restricted { return .restricted }
        return .available
    }

    private func cameraAuthorization(
        _ status: CameraPermissionStatus
    ) -> CapabilityAuthorization {
        switch status {
        case .notDetermined: return .ungranted
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        }
    }

    private func cameraNote(
        hardwareAvailable: Bool,
        permissionStatus: CameraPermissionStatus
    ) -> String {
        guard hardwareAvailable else {
            return "No camera hardware is available on this device; permission state is reported independently."
        }
        switch permissionStatus {
        case .notDetermined:
            return "Camera permission has not been requested. Use the explicit permission action to ask AVFoundation."
        case .authorized:
            return "Camera permission is granted. Capture streaming is gated by a DeviceAgent lease; remote invocation is not connected."
        case .denied:
            return "Camera permission is denied. Availability and authorization are reported independently."
        case .restricted:
            return "Camera access is restricted by the system. No capture transport is implemented."
        }
    }
}
