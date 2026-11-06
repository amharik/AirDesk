import FlatBuffers
import XCTest
@testable import AirDesk

@MainActor
final class CapabilityCatalogTests: XCTestCase {
    private let provider = "ad-device:" + String(repeating: "b", count: 64)

    func testCatalogAdvertisesExpectedScopedCapabilities() {
        let catalog = makeCatalog()

        XCTAssertEqual(
            Set(catalog.descriptors.map(\.capUri)),
            [
                "airdesk://display/output",
                "airdesk://input/pointer",
                "airdesk://input/keyboard",
                "airdesk://media/camera/capture",
                "airdesk://fs/documents/read",
                "airdesk://health/status"
            ]
        )
        XCTAssertTrue(catalog.descriptors.allSatisfy { $0.providerDeviceId == provider })
        XCTAssertTrue(catalog.descriptors.allSatisfy {
            $0.version == CapabilityDescriptor.currentVersion
        })
    }

    func testAvailabilityAndAuthorizationAreSeparateAxes() {
        let denied = makeCatalog(
            cameraStatus: .denied
        ).cameraDescriptor

        XCTAssertEqual(denied?.availability, .available)
        XCTAssertEqual(denied?.authorization, .denied)

        let notRequested = makeCatalog(
            cameraStatus: .notDetermined
        ).cameraDescriptor

        XCTAssertEqual(notRequested?.availability, .available)
        XCTAssertEqual(notRequested?.authorization, .ungranted)
    }

    func testCameraDenyRestrictAndUnavailableStates() {
        let denied = makeCatalog(cameraStatus: .denied).cameraDescriptor
        XCTAssertEqual(denied?.availability, .available)
        XCTAssertEqual(denied?.authorization, .denied)

        let restricted = makeCatalog(cameraStatus: .restricted).cameraDescriptor
        XCTAssertEqual(restricted?.availability, .restricted)
        XCTAssertEqual(restricted?.authorization, .denied)

        let missingHardware = makeCatalog(
            hardwareAvailable: false,
            cameraStatus: .notDetermined
        ).cameraDescriptor
        XCTAssertEqual(missingHardware?.availability, .unavailable)
        XCTAssertEqual(missingHardware?.authorization, .ungranted)
    }

    func testCameraPermissionRequestRefreshesCatalogWithoutClaimingOtherGrants() async {
        let camera = StubCameraProvider(
            hardwareAvailable: true,
            permissionStatus: .notDetermined,
            requestResult: .authorized
        )
        let catalog = CapabilityCatalog(
            providerDeviceId: provider,
            camera: camera,
            files: StubFileProvider(appScopedDocumentsAvailable: true)
        )

        XCTAssertEqual(catalog.cameraDescriptor?.authorization, .ungranted)

        let granted = await catalog.requestCameraAccess()

        XCTAssertTrue(granted)
        XCTAssertEqual(camera.requestCount, 1)
        XCTAssertEqual(catalog.cameraDescriptor?.authorization, .granted)
        XCTAssertEqual(catalog.cameraDescriptor?.availability, .available)
        XCTAssertTrue(catalog.descriptors
            .filter { $0.capUri != CapabilityCatalog.cameraCapUri }
            .allSatisfy { $0.authorization == .ungranted })
    }

    func testDocumentsAreRestrictedOrUnavailableAndNeverBroadFilesystem() {
        let available = makeCatalog().descriptors.first {
            $0.capUri == CapabilityCatalog.documentsCapUri
        }

        XCTAssertEqual(available?.availability, .restricted)
        XCTAssertEqual(available?.authorization, .ungranted)
        XCTAssertEqual(available?.permissions, [])
        XCTAssertTrue(available?.constraints.contains(#""deviceWideAccess":false"#) == true)
        XCTAssertTrue(available?.constraints.contains(#""userSelectedOnly":true"#) == true)

        let catalog = CapabilityCatalog(
            providerDeviceId: provider,
            camera: StubCameraProvider(hardwareAvailable: true),
            files: StubFileProvider(appScopedDocumentsAvailable: false)
        )
        let unavailable = catalog.descriptors.first {
            $0.capUri == CapabilityCatalog.documentsCapUri
        }
        XCTAssertEqual(unavailable?.availability, .unavailable)
    }

    func testHealthUsesLocalDiagnosticsWithoutEntitlements() {
        let health = makeCatalog().descriptors.first {
            $0.capUri == "airdesk://health/status"
        }

        XCTAssertEqual(health?.availability, .available)
        XCTAssertEqual(health?.authorization, .ungranted)
        XCTAssertEqual(health?.permissions, [])
        XCTAssertTrue(health?.constraints.contains(#""healthKit":false"#) == true)
    }

    func testDescriptorMapsIntoGeneratedADFPType() throws {
        let descriptor = try XCTUnwrap(
            makeCatalog(cameraStatus: .authorized).cameraDescriptor
        )
        var buffer = ByteBuffer(data: descriptor.adfpEncoded())
        let decoded: AirDesk_Protocol__CapabilityDescriptor = getRoot(byteBuffer: &buffer)

        XCTAssertEqual(decoded.capUri, descriptor.capUri)
        XCTAssertEqual(decoded.version, descriptor.version)
        XCTAssertEqual(decoded.providerDeviceId, descriptor.providerDeviceId)
        XCTAssertEqual(decoded.availability, .available)
        XCTAssertEqual(decoded.authorization, .granted)
        XCTAssertEqual(Array(decoded.permissions).compactMap { $0 }, descriptor.permissions)
        XCTAssertEqual(decoded.execution, descriptor.execution)
        XCTAssertEqual(decoded.transport, descriptor.transport)
        XCTAssertEqual(decoded.constraints, descriptor.constraints)
    }

    func testSelfIdentityBindingUsesLocalDeviceIDForEveryDescriptor() throws {
        let identity = try DeviceIdentity(algorithm: .ed25519)
        let catalog = CapabilityCatalog(
            identity: identity,
            camera: StubCameraProvider(hardwareAvailable: true),
            files: StubFileProvider(appScopedDocumentsAvailable: true)
        )

        XCTAssertEqual(catalog.providerDeviceId, identity.deviceId)
        XCTAssertTrue(catalog.descriptors.allSatisfy {
            $0.providerDeviceId == identity.deviceId
        })

        let camera = try XCTUnwrap(catalog.cameraDescriptor)
        var buffer = ByteBuffer(data: camera.adfpEncoded())
        let decoded: AirDesk_Protocol__CapabilityDescriptor = getRoot(byteBuffer: &buffer)
        XCTAssertEqual(decoded.providerDeviceId, identity.deviceId)
    }

    func testLocalCapabilitiesAreAvailableButNotGrantedByAdvertisement() {
        let descriptors = makeCatalog().descriptors

        for uri in [
            "airdesk://display/output",
            "airdesk://input/pointer",
            "airdesk://input/keyboard"
        ] {
            let descriptor = descriptors.first { $0.capUri == uri }
            XCTAssertEqual(descriptor?.availability, .available)
            XCTAssertEqual(descriptor?.authorization, .ungranted)
        }
        XCTAssertFalse(descriptors.contains { $0.authorization == .granted })
    }

    private func makeCatalog(
        hardwareAvailable: Bool = true,
        cameraStatus: CameraPermissionStatus = .notDetermined,
        filesAvailable: Bool = true
    ) -> CapabilityCatalog {
        CapabilityCatalog(
            providerDeviceId: provider,
            camera: StubCameraProvider(
                hardwareAvailable: hardwareAvailable,
                permissionStatus: cameraStatus,
                requestResult: cameraStatus
            ),
            files: StubFileProvider(appScopedDocumentsAvailable: filesAvailable)
        )
    }
}

private final class StubCameraProvider: CameraCapabilityProviding {
    var hardwareAvailable: Bool
    var permissionStatus: CameraPermissionStatus
    var requestResult: CameraPermissionStatus
    private(set) var requestCount = 0

    init(
        hardwareAvailable: Bool,
        permissionStatus: CameraPermissionStatus = .notDetermined,
        requestResult: CameraPermissionStatus = .notDetermined
    ) {
        self.hardwareAvailable = hardwareAvailable
        self.permissionStatus = permissionStatus
        self.requestResult = requestResult
    }

    func requestPermission() async -> CameraPermissionStatus {
        requestCount += 1
        permissionStatus = requestResult
        return requestResult
    }
}

private struct StubFileProvider: FileAccessCapabilityProviding {
    var appScopedDocumentsAvailable: Bool
}
