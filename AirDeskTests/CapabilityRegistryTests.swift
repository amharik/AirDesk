import XCTest
@testable import AirDesk

final class CapabilityRegistryTests: XCTestCase {
    private func descriptor(
        capUri: String = "airdesk://media/camera/capture",
        version: UInt32 = 1,
        providerDeviceId: String = "dev-a",
        permissions: [String] = ["ios.camera.video"],
        execution: String = "on-device-capture",
        transport: String = "websocket",
        constraints: String = #"{"hardwareAvailable":true,"streaming":false}"#,
        availability: CapabilityAvailability = .available,
        authorization: CapabilityAuthorization = .granted,
        label: String = "Camera capture",
        summary: String = "Camera permission and hardware state.",
        note: String = "Capture streaming is not implemented."
    ) -> CapabilityDescriptor {
        CapabilityDescriptor(
            capUri: capUri,
            version: version,
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

    func testRegistersReplacesAndSortsDescriptors() throws {
        let registry = CapabilityRegistry()
        XCTAssertTrue(try registry.register(descriptor()))
        XCTAssertEqual(registry.count, 1)
        XCTAssertFalse(try registry.register(descriptor(constraints: #"{"streaming":true}"#)))
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(
            registry.descriptor(
                providerDeviceId: "dev-a",
                capUri: "airdesk://media/camera/capture",
                version: 1
            )?.constraints,
            #"{"streaming":true}"#
        )

        XCTAssertTrue(try registry.register(
            descriptor(capUri: "airdesk://display/output", providerDeviceId: "dev-b")
        ))
        XCTAssertTrue(try registry.register(
            descriptor(capUri: "airdesk://display/output", providerDeviceId: "dev-a")
        ))

        let descriptors = registry.descriptors()
        XCTAssertEqual(descriptors.map(\.capUri), [
            "airdesk://display/output",
            "airdesk://display/output",
            "airdesk://media/camera/capture"
        ])
        XCTAssertEqual(descriptors.prefix(2).map(\.providerDeviceId), ["dev-a", "dev-b"])
    }

    func testRejectsMalformedDescriptors() {
        let registry = CapabilityRegistry()
        let invalid: [CapabilityDescriptor] = [
            descriptor(providerDeviceId: " "),
            descriptor(capUri: "https://media/camera/capture"),
            descriptor(capUri: "airdesk://media//capture"),
            descriptor(version: 0),
            descriptor(permissions: ["camera", "camera"]),
            descriptor(permissions: [""]),
            descriptor(execution: ""),
            descriptor(transport: ""),
            descriptor(constraints: "not-json"),
            descriptor(constraints: "[]"),
            descriptor(constraints: #"{"nested":{"enabled":true}}"#),
            descriptor(constraints: #"{"values":[1,2]}"#),
            descriptor(availability: .unknown),
            descriptor(authorization: .unknown),
            descriptor(label: ""),
            descriptor(summary: ""),
            descriptor(note: "")
        ]

        for descriptor in invalid {
            XCTAssertThrowsError(try registry.register(descriptor))
        }
        XCTAssertEqual(registry.count, 0)
    }

    func testKeepsAvailabilityAndAuthorizationIndependent() throws {
        let registry = CapabilityRegistry()
        try registry.register(descriptor())

        XCTAssertTrue(try registry.updateAvailability(
            providerDeviceId: "dev-a",
            capUri: "airdesk://media/camera/capture",
            version: 1,
            availability: .busy
        ))
        var current = registry.descriptors().first
        XCTAssertEqual(current?.availability, .busy)
        XCTAssertEqual(current?.authorization, .granted)

        XCTAssertTrue(try registry.updateAuthorization(
            providerDeviceId: "dev-a",
            capUri: "airdesk://media/camera/capture",
            version: 1,
            authorization: .revoked
        ))
        current = registry.descriptors().first
        XCTAssertEqual(current?.availability, .busy)
        XCTAssertEqual(current?.authorization, .revoked)

        XCTAssertFalse(try registry.updateAvailability(
            providerDeviceId: "dev-b",
            capUri: "airdesk://media/camera/capture",
            version: 1,
            availability: .busy
        ))
        XCTAssertThrowsError(try registry.updateAvailability(
            providerDeviceId: "dev-a",
            capUri: "airdesk://media/camera/capture",
            version: 1,
            availability: .unknown
        )) { error in
            XCTAssertEqual(error as? CapabilityRegistryError, .invalidAvailability)
        }
    }

    func testRemovesByVersionAndClearsRegistry() throws {
        let registry = CapabilityRegistry()
        try registry.register(descriptor(version: 1))
        try registry.register(descriptor(version: 2))

        XCTAssertEqual(registry.remove(
            providerDeviceId: "dev-a",
            capUri: "airdesk://media/camera/capture",
            version: 1
        ), 1)
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.remove(
            providerDeviceId: "dev-a",
            capUri: "airdesk://media/camera/capture"
        ), 1)
        XCTAssertEqual(registry.count, 0)

        try registry.register(descriptor())
        registry.removeAll()
        XCTAssertEqual(registry.count, 0)
    }
}
