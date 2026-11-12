import XCTest
@testable import AirDesk

final class OnboardingQuickConnectTests: XCTestCase {
    private let preview = DisplayDevice(
        id: DisplayDevice.previewID,
        name: "This device",
        detail: "On-device preview",
        kind: .preview,
        mode: .preview,
        isDemo: true
    )
    private let external = DisplayDevice(
        id: "display.external",
        name: "Studio Display",
        detail: "Connected",
        kind: .external,
        mode: .extended
    )
    private let airPlay = DisplayDevice(
        id: "display.airplay.mirroring",
        name: "AirPlay mirroring",
        detail: "Mirrored",
        kind: .airPlay,
        mode: .mirrored
    )
    private let cast = DisplayDevice(
        id: "cast.studio",
        name: "Studio TV",
        detail: "Google Cast",
        kind: .cast,
        mode: .cast
    )

    func testExternalDisplayWinsWithoutManualSetup() {
        let recommendation = OnboardingQuickConnect.recommend(
            externalDisplay: external,
            airPlayMirroring: airPlay,
            castDevices: [cast],
            preview: preview
        )

        XCTAssertEqual(recommendation.route, .external)
        XCTAssertEqual(recommendation.device, external)
        XCTAssertEqual(recommendation.title, "Continue on Studio Display")
    }

    func testAirPlayWinsOverCastAndPreview() {
        let recommendation = OnboardingQuickConnect.recommend(
            externalDisplay: nil,
            airPlayMirroring: airPlay,
            castDevices: [cast],
            preview: preview
        )

        XCTAssertEqual(recommendation.route, .airPlay)
        XCTAssertEqual(recommendation.device, airPlay)
        XCTAssertTrue(recommendation.accessibilityLabel.contains("AirPlay"))
    }

    func testAvailableCastWinsOverPreview() {
        let unavailable = DisplayDevice(
            id: "cast.offline",
            name: "Offline TV",
            detail: "Unavailable",
            kind: .cast,
            mode: .cast,
            isAvailable: false
        )
        let recommendation = OnboardingQuickConnect.recommend(
            externalDisplay: nil,
            airPlayMirroring: nil,
            castDevices: [unavailable, cast],
            preview: preview
        )

        XCTAssertEqual(recommendation.route, .cast)
        XCTAssertEqual(recommendation.device, cast)
        XCTAssertEqual(recommendation.title, "Cast to Studio TV")
    }

    func testPreviewIsAlwaysAvailableFallback() {
        let recommendation = OnboardingQuickConnect.recommend(
            externalDisplay: nil,
            airPlayMirroring: nil,
            castDevices: [],
            preview: preview
        )

        XCTAssertEqual(recommendation.route, .preview)
        XCTAssertEqual(recommendation.device, preview)
        XCTAssertTrue(recommendation.accessibilityHint.contains("Choose a display"))
    }

    func testAdvancedSetupHintRemainsAvailable() {
        let recommendation = OnboardingQuickConnect.recommend(
            externalDisplay: external,
            airPlayMirroring: nil,
            castDevices: [],
            preview: preview
        )

        XCTAssertTrue(recommendation.accessibilityHint.contains("advanced setup"))
        XCTAssertTrue(recommendation.detail.contains("skips manual setup"))
    }
}
