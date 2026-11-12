import XCTest
@testable import AirDesk

#if AIRDESK_CORE_SMOKE
final class CoreFFISmokeTests: XCTestCase {
    func testGeneratedCoreSmokeSurface() {
        XCTAssertEqual(CoreFFISmoke.label, "airdesk-core/1")
        XCTAssertEqual(CoreFFISmoke.abiVersion, 1)
        XCTAssertTrue(CoreFFISmoke.isCurrentABICompatible)
    }
}
#endif
