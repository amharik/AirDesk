import StoreKit
import XCTest
@testable import AirDesk

final class ProAccessTests: XCTestCase {
    func testProProductIdentifiersMatchAppStoreConfiguration() {
        XCTAssertEqual(ProProduct.monthly.rawValue, "com.airdesk.pro.monthly")
        XCTAssertEqual(ProProduct.yearly.rawValue, "com.airdesk.pro.yearly")
        XCTAssertEqual(ProProduct.familyYearly.rawValue, "com.airdesk.pro.family.yearly")
        XCTAssertEqual(ProProduct.lifetime.rawValue, "com.airdesk.pro.lifetime")
    }

    func testProProductsAreOrderedForPaywall() {
        let ordered = ProProduct.allCases.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(ordered, [.monthly, .yearly, .familyYearly, .lifetime])
    }

    func testOnlyLifetimeIsNotASubscription() {
        XCTAssertTrue(ProProduct.monthly.isSubscription)
        XCTAssertTrue(ProProduct.yearly.isSubscription)
        XCTAssertTrue(ProProduct.familyYearly.isSubscription)
        XCTAssertFalse(ProProduct.lifetime.isSubscription)
    }

    func testWanixKernelRequiresPro() {
        XCTAssertTrue(RuntimeChoice.wanixKernel.requiresPro)
        XCTAssertFalse(RuntimeChoice.wanixDesktop.requiresPro)
        XCTAssertFalse(RuntimeChoice.puter.requiresPro)
    }
}
