import Foundation
import XCTest
@testable import AirDesk

final class DiscoveryAdvertisementTests: XCTestCase {
    private let currentHash = String(repeating: "ab", count: 32)
    private let nextHash = String(repeating: "cd", count: 32)

    func testControlAdvertisementUsesCanonicalTXTKeys() throws {
        let txt = try DiscoveryTXTRecord(
            deviceType: .host,
            currentCertificateHash: currentHash.uppercased(),
            nextCertificateHash: nextHash
        )
        let advertisement = DiscoveryAdvertisement(serviceKind: .control, txt: txt)

        XCTAssertEqual(advertisement.fullServiceName, "_airdesk._tcp.local.")
        XCTAssertEqual(txt.dictionary["txtvers"], "1")
        XCTAssertEqual(txt.dictionary["adfp_ver"], "1.0")
        XCTAssertEqual(txt.dictionary["device_type"], "host")
        XCTAssertEqual(txt.dictionary["certhash_current"], currentHash)
        XCTAssertEqual(txt.dictionary["certhash_next"], nextHash)
        XCTAssertEqual(try DiscoveryTXTRecord(txtData: txt.encoded()), txt)
    }

    func testWebTransportAdvertisementOmitsNextHashWhenAbsent() throws {
        let txt = try DiscoveryTXTRecord(
            deviceType: .display,
            currentCertificateHash: currentHash
        )
        let advertisement = DiscoveryAdvertisement(serviceKind: .webTransport, txt: txt)

        XCTAssertEqual(advertisement.fullServiceName, "_airdesk._udp.local.")
        XCTAssertEqual(txt.dictionary["device_type"], "display")
        XCTAssertNil(txt.dictionary["certhash_next"])
        XCTAssertEqual(try DiscoveryTXTRecord(txtData: txt.encoded()), txt)
    }

    func testRejectsStableIdentifiersCapabilitiesAndOtherSecrets() throws {
        let base = try DiscoveryTXTRecord(
            deviceType: .controller,
            currentCertificateHash: currentHash
        ).dictionary

        for key in ["dev_id", "role_mask"] {
            XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging([key: "x"]) { $1 })) {
                XCTAssertEqual($0 as? DiscoveryAdvertisementError, .forbiddenKey(key))
            }
        }

        for key in ["capabilities", "token", "endpoint", "user_name"] {
            XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging([key: "x"]) { $1 })) {
                XCTAssertEqual($0 as? DiscoveryAdvertisementError, .unsupportedKey(key))
            }
        }
    }

    func testRejectsInvalidCanonicalValues() throws {
        let base = try DiscoveryTXTRecord(
            deviceType: .host,
            currentCertificateHash: currentHash
        ).dictionary

        XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging(["txtvers": "2"]) { $1 }))
        XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging(["adfp_ver": "2.0"]) { $1 }))
        XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging(["device_type": "server"]) { $1 }))
        XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging(["certhash_current": "abcd"]) { $1 }))
        XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: base.merging(["certhash_current": String(repeating: "zz", count: 32)]) { $1 }))

        var missingVersion = base
        missingVersion.removeValue(forKey: "adfp_ver")
        XCTAssertThrowsError(try DiscoveryTXTRecord(dictionary: missingVersion)) {
            XCTAssertEqual($0 as? DiscoveryAdvertisementError, .missingKey("adfp_ver"))
        }

        XCTAssertThrowsError(try DiscoveryTXTRecord(
            deviceType: .host,
            currentCertificateHash: currentHash,
            nextCertificateHash: currentHash.uppercased()
        )) {
            XCTAssertEqual(
                $0 as? DiscoveryAdvertisementError,
                .invalidCertificateHash("next hash matches current")
            )
        }
    }

    func testRejectsMalformedTXTData() {
        XCTAssertThrowsError(try DiscoveryTXTRecord(txtData: Data([4, 0x74, 0x78]))) {
            XCTAssertEqual($0 as? DiscoveryAdvertisementError, .malformedTXT)
        }
        XCTAssertThrowsError(try DiscoveryTXTRecord(txtData: Data([3, 0x61, 0x62]))) {
            XCTAssertEqual($0 as? DiscoveryAdvertisementError, .malformedTXT)
        }
        XCTAssertThrowsError(try DiscoveryTXTRecord(txtData: txtData(["no-separator"]))) {
            XCTAssertEqual($0 as? DiscoveryAdvertisementError, .malformedTXT)
        }
        XCTAssertThrowsError(try DiscoveryTXTRecord(txtData: txtData(["txtvers=1", "txtvers=1"]))) {
            XCTAssertEqual($0 as? DiscoveryAdvertisementError, .duplicateKey("txtvers"))
        }
        XCTAssertThrowsError(try DiscoveryTXTRecord(txtData: Data([0]))) {
            XCTAssertEqual($0 as? DiscoveryAdvertisementError, .malformedTXT)
        }
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
