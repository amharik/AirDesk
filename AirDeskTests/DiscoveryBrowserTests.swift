import Foundation
import XCTest
@testable import AirDesk

final class DiscoveryBrowserTests: XCTestCase {
    private let currentHash = String(repeating: "ab", count: 32)

    func testBrowserFiltersMalformedAndForbiddenAdvertisements() throws {
        let transport = FakeDiscoveryTransport()
        let browser = DiscoveryBrowser(transport: transport)
        var updates: [[DiscoveredAdvertisement]] = []

        browser.start(kinds: [.control]) { updates.append($0) }
        XCTAssertEqual(transport.startedKinds, [.control])
        XCTAssertEqual(transport.stopCount, 1)
        XCTAssertEqual(browser.state(for: .control), .idle)

        transport.send(.ready(.control))
        XCTAssertEqual(browser.state(for: .control), .browsing)

        let valid = try DiscoveryTXTRecord(
            deviceType: .host,
            currentCertificateHash: currentHash
        ).encoded()
        let forbidden = txtData(["txtvers=1", "adfp_ver=1.0", "device_type=host", "certhash_current=\(currentHash)", "dev_id=device"])
        transport.send(.snapshot(DiscoveryBrowserSnapshot(serviceKind: .control, entries: [
            DiscoveryBrowserEntry(serviceName: "Desk", txtData: valid),
            DiscoveryBrowserEntry(serviceName: "Forbidden", txtData: forbidden),
            DiscoveryBrowserEntry(serviceName: "Malformed", txtData: Data([4, 0x74]))
        ])))

        XCTAssertEqual(browser.advertisements.count, 1)
        XCTAssertEqual(browser.advertisements.first?.serviceName, "Desk")
        XCTAssertEqual(browser.advertisements.first?.advertisement.fullServiceName, "_airdesk._tcp.local.")
        XCTAssertEqual(updates.last?.count, 1)

        transport.send(.snapshot(DiscoveryBrowserSnapshot(serviceKind: .control, entries: [])))
        XCTAssertTrue(browser.advertisements.isEmpty)
        XCTAssertEqual(updates.last?.isEmpty, true)
    }

    func testBrowserClearsResultsOnFailureAndStop() throws {
        let transport = FakeDiscoveryTransport()
        let browser = DiscoveryBrowser(transport: transport)
        browser.start(kinds: [.webTransport]) { _ in }
        let valid = try DiscoveryTXTRecord(
            deviceType: .display,
            currentCertificateHash: currentHash
        ).encoded()
        transport.send(.snapshot(DiscoveryBrowserSnapshot(serviceKind: .webTransport, entries: [
            DiscoveryBrowserEntry(serviceName: "Display", txtData: valid)
        ])))
        XCTAssertEqual(browser.advertisements.count, 1)

        transport.send(.failed(.webTransport, "browser failed"))
        XCTAssertEqual(browser.state(for: .webTransport), .failed("browser failed"))
        XCTAssertTrue(browser.advertisements.isEmpty)

        browser.stop()
        XCTAssertEqual(transport.stopCount, 2)
        XCTAssertEqual(browser.state(for: .webTransport), .idle)
        XCTAssertTrue(browser.advertisements.isEmpty)
    }

    func testBrowserAdvertisesOnlyCanonicalKeysWhenPublishing() throws {
        let txt = try DiscoveryTXTRecord(
            deviceType: .controller,
            currentCertificateHash: currentHash
        )
        let advertisement = DiscoveryAdvertisement(serviceKind: .webTransport, txt: txt)
        let text = String(decoding: txt.encoded(), as: UTF8.self)

        XCTAssertTrue(text.contains("txtvers=1"))
        XCTAssertTrue(text.contains("adfp_ver=1.0"))
        XCTAssertTrue(text.contains("certhash_current=\(currentHash)"))
        XCTAssertFalse(text.contains("dev_id"))
        XCTAssertFalse(text.contains("role_mask"))
        XCTAssertEqual(advertisement.domain, "local.")
    }

    private func txtData(_ items: [String]) -> Data {
        var data = Data()
        for item in items {
            let bytes = Data(item.utf8)
            data.append(UInt8(bytes.count))
            data.append(bytes)
        }
        return data
    }
}

private final class FakeDiscoveryTransport: DiscoveryBrowserTransport {
    private(set) var startedKinds: Set<DiscoveryServiceKind> = []
    private(set) var stopCount = 0
    private var handler: ((DiscoveryBrowserTransportEvent) -> Void)?

    func start(
        kinds: Set<DiscoveryServiceKind>,
        handler: @escaping (DiscoveryBrowserTransportEvent) -> Void
    ) {
        startedKinds = kinds
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func send(_ event: DiscoveryBrowserTransportEvent) {
        handler?(event)
    }
}
