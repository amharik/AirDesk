import XCTest
@testable import AirDesk

@MainActor
final class CoreCutoverTests: XCTestCase {
    func testNativeIsTheDefaultAndNeverFallsBack() {
        for feature in CoreFeature.allCases {
            let selection = CoreCutoverPolicy.resolve(
                feature: feature,
                requested: .native,
                movementAvailable: true
            )
            XCTAssertEqual(selection.active, .native)
            XCTAssertEqual(selection.reason, .none)
            XCTAssertFalse(selection.isFallback)
        }
    }

    func testRequestedCorePathsRespectReviewAndBindingGates() {
        XCTAssertEqual(
            CoreCutoverPolicy.resolve(feature: .movement, requested: .core, movementAvailable: true).active,
            .core
        )
        XCTAssertEqual(
            CoreCutoverPolicy.resolve(feature: .movement, requested: .core, movementAvailable: false).reason,
            .bindingUnavailable
        )
        XCTAssertEqual(
            CoreCutoverPolicy.resolve(feature: .envelope, requested: .core).reason,
            .bindingUnavailable
        )
        XCTAssertEqual(
            CoreCutoverPolicy.resolve(feature: .pairing, requested: .core).reason,
            .independentReviewRequired
        )
        XCTAssertEqual(
            CoreCutoverPolicy.resolve(feature: .sync, requested: .core).active,
            .core
        )
        XCTAssertEqual(
            CoreCutoverPolicy.resolve(feature: .sync, requested: .core, syncAvailable: false).reason,
            .bindingUnavailable
        )
        XCTAssertTrue(
            CoreCutoverPolicy.resolve(feature: .pairing, requested: .core).isFallback
        )
    }

    func testCoreMovementMatchesNativeFilterOutputs() {
        let native = AdaptivePointerFilter(backend: .native)
        let core = AdaptivePointerFilter(backend: .core)
        let samples: [(Double, Double, Double)] = [
            (0.10, 0.20, 0.0),
            (0.15, 0.25, 1.0 / 120.0),
            (0.35, 0.55, 2.0 / 120.0),
            (0.34, 0.54, 3.0 / 120.0),
            (0.80, 0.30, 4.0 / 120.0),
            (0.79, 0.31, 5.0 / 120.0)
        ]

        for sample in samples {
            let nativePoint = native.filter(x: sample.0, y: sample.1, timestamp: sample.2)
            let corePoint = core.filter(x: sample.0, y: sample.1, timestamp: sample.2)
            XCTAssertEqual(corePoint.x, nativePoint.x, accuracy: 1e-9)
            XCTAssertEqual(corePoint.y, nativePoint.y, accuracy: 1e-9)
        }
        XCTAssertFalse(core.didFallback)
    }

    func testCorePathsPersistAndReset() {
        let suiteName = "CoreCutoverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.corePath(for: .movement), .native)
        settings.setCorePath(.core, for: .movement)
        settings.setCorePath(.core, for: .pairing)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.corePath(for: .movement), .core)
        XCTAssertEqual(reloaded.coreSelection(for: .movement).active, .core)
        XCTAssertEqual(reloaded.coreSelection(for: .pairing).active, .native)
        XCTAssertEqual(reloaded.coreSelection(for: .pairing).reason, .independentReviewRequired)

        reloaded.reset()
        XCTAssertEqual(reloaded.corePath(for: .movement), .native)
        XCTAssertEqual(reloaded.corePath(for: .pairing), .native)
    }
}
