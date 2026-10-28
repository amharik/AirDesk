import XCTest
@testable import AirDesk

final class DisplayModeResolverTests: XCTestCase {
    func testMirroringWinsForDisplayDevices() {
        XCTAssertEqual(
            DisplayModeResolver.resolvedMode(for: .airPlay, hasExternalDisplay: false, isMirroring: true),
            .mirrored
        )
        XCTAssertEqual(
            DisplayModeResolver.resolvedMode(for: .wired, hasExternalDisplay: true, isMirroring: true),
            .mirrored
        )
    }

    func testExtendedDisplayWinsWithoutMirroring() {
        XCTAssertEqual(
            DisplayModeResolver.resolvedMode(for: .airPlay, hasExternalDisplay: true, isMirroring: false),
            .extended
        )
        XCTAssertEqual(
            DisplayModeResolver.resolvedMode(for: .wired, hasExternalDisplay: true, isMirroring: false),
            .extended
        )
    }

    func testCastAndPreviewIgnoreDisplayState() {
        XCTAssertEqual(
            DisplayModeResolver.resolvedMode(for: .cast, hasExternalDisplay: true, isMirroring: true),
            .cast
        )
        XCTAssertEqual(
            DisplayModeResolver.resolvedMode(for: .preview, hasExternalDisplay: true, isMirroring: true),
            .preview
        )
    }

    func testEffectiveModeTracksDisplayState() {
        XCTAssertEqual(
            DisplayModeResolver.effectiveMode(current: .preview, hasExternalDisplay: false, isMirroring: true),
            .mirrored
        )
        XCTAssertEqual(
            DisplayModeResolver.effectiveMode(current: .preview, hasExternalDisplay: true, isMirroring: false),
            .extended
        )
        XCTAssertEqual(
            DisplayModeResolver.effectiveMode(current: .cast, hasExternalDisplay: true, isMirroring: true),
            .cast
        )
    }

    func testFallbackModeUsesPreviewAfterDisconnect() {
        XCTAssertEqual(
            DisplayModeResolver.fallbackMode(for: .airPlay, hasExternalDisplay: false, isMirroring: false),
            .preview
        )
        XCTAssertEqual(
            DisplayModeResolver.fallbackMode(for: .wired, hasExternalDisplay: false, isMirroring: false),
            .preview
        )
        XCTAssertEqual(
            DisplayModeResolver.fallbackMode(for: .cast, hasExternalDisplay: false, isMirroring: false),
            .cast
        )
    }

    @MainActor
    func testDisplayModePersists() {
        let suite = "AirDeskTests.DisplayMode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.displayMode, .extended)
        settings.displayMode = .mirrored

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.displayMode, .mirrored)
    }
}
