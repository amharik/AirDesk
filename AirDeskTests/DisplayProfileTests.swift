import XCTest
@testable import AirDesk

final class DisplayProfileTests: XCTestCase {
    func testPreviewProfileUsesPhoneRuntimeAndLocalInput() throws {
        let profile = try DisplayProfileResolver.resolve(mode: .preview, device: device(kind: .preview))

        XCTAssertEqual(profile.mode, .preview)
        XCTAssertEqual(profile.runtime, .phone)
        XCTAssertEqual(profile.target, .phone)
        XCTAssertEqual(profile.input, .localSurface)
    }

    func testExtendedProfileUsesExternalScene() throws {
        let profile = try DisplayProfileResolver.resolve(mode: .extended, device: device(kind: .airPlay))

        XCTAssertEqual(profile.runtime, .phone)
        XCTAssertEqual(profile.target, .externalScene)
        XCTAssertEqual(profile.input, .localSurface)
    }

    func testMirroredProfileUsesPhoneRuntime() throws {
        let profile = try DisplayProfileResolver.resolve(mode: .mirrored, device: device(kind: .wired))

        XCTAssertEqual(profile.runtime, .phone)
        XCTAssertEqual(profile.target, .mirroredPhone)
        XCTAssertEqual(profile.input, .localSurface)
    }

    func testCastProfileUsesReceiverRuntimeAndChannel() throws {
        let profile = try DisplayProfileResolver.resolve(mode: .cast, device: device(kind: .cast))

        XCTAssertEqual(profile.runtime, .castReceiver)
        XCTAssertEqual(profile.target, .castReceiver)
        XCTAssertEqual(profile.input, .castChannel)
    }

    func testCastModeRejectsNonCastDevice() {
        XCTAssertThrowsError(
            try DisplayProfileResolver.resolve(mode: .cast, device: device(kind: .airPlay))
        ) { error in
            XCTAssertEqual(error as? DisplayProfileError, .castRequiresCastDevice)
        }
    }

    func testCastDeviceRejectsNonCastMode() {
        XCTAssertThrowsError(
            try DisplayProfileResolver.resolve(mode: .preview, device: device(kind: .cast))
        ) { error in
            XCTAssertEqual(error as? DisplayProfileError, .castDeviceRequiresCastMode)
        }
    }

    func testUnavailableDeviceIsRejected() {
        XCTAssertThrowsError(
            try DisplayProfileResolver.resolve(mode: .preview, device: device(kind: .preview, isAvailable: false))
        ) { error in
            XCTAssertEqual(error as? DisplayProfileError, .deviceUnavailable)
        }
    }

    private func device(kind: DisplayKind, isAvailable: Bool = true) -> DisplayDevice {
        DisplayDevice(
            id: "test.\(kind.rawValue)",
            name: kind.label,
            detail: kind.label,
            kind: kind,
            mode: kind == .cast ? .cast : .preview,
            isAvailable: isAvailable
        )
    }
}
