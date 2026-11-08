import XCTest
@testable import AirDesk

final class PairingWireMessageTests: XCTestCase {
    func testWireMessagesRoundTrip() throws {
        let response = try AdPairWireMessage.response(Data([1, 2, 3]))
        XCTAssertEqual(try AdPairWireMessage.decode(response.encoded()), response)

        let share = try AdPairWireMessage.share(Data(repeating: 4, count: 65))
        XCTAssertEqual(try AdPairWireMessage.decode(share.encoded()), share)

        let verifier = try AdPairWireMessage.verifierResponse(
            share: Data(repeating: 5, count: 65),
            confirmation: Data(repeating: 6, count: 32),
            signature: Data(repeating: 7, count: 64)
        )
        XCTAssertEqual(try AdPairWireMessage.decode(verifier.encoded()), verifier)

        let finish = try AdPairWireMessage.initiatorFinish(
            confirmation: Data(repeating: 8, count: 32),
            signature: Data(repeating: 9, count: 64)
        )
        XCTAssertEqual(try AdPairWireMessage.decode(finish.encoded()), finish)
    }

    func testWireMessagesRejectMalformedUnsupportedAndMissingPayloads() throws {
        XCTAssertThrowsError(try AdPairWireMessage.decode(Data("{}".utf8))) {
            XCTAssertEqual($0 as? AdPairWireError, .malformed)
        }

        let valid = try AdPairWireMessage.share(Data(repeating: 1, count: 65))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid.encoded()) as? [String: Any]
        )
        object["version"] = 2
        XCTAssertThrowsError(try AdPairWireMessage.decode(try JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? AdPairWireError, .unsupportedVersion)
        }

        object["version"] = 1
        object["protocol"] = "other"
        XCTAssertThrowsError(try AdPairWireMessage.decode(try JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? AdPairWireError, .unsupportedProtocol)
        }

        object["protocol"] = AdPairWireMessage.protocolName
        object["share"] = nil
        XCTAssertThrowsError(try AdPairWireMessage.decode(try JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? AdPairWireError, .invalidPayload("share"))
        }
    }
}
