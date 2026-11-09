import FlatBuffers
import Foundation
import XCTest
@testable import AirDesk

final class ADFPEnvelopeCodecTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("protocol/fixtures/adfp/envelope-v1.json")

    private var fixture: [String: Any]!
    private var now: Date!

    override func setUpWithError() throws {
        let data = try Data(contentsOf: Self.fixtureURL)
        fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let nowMillis = try XCTUnwrap(UInt64(try XCTUnwrap(fixture["nowEpochMillis"] as? String)))
        now = Date(timeIntervalSince1970: Double(nowMillis) / 1000)
    }

    func testInputFixtureDecodesAndReencodes() throws {
        let item = try fixtureCase(named: "input-key-down")
        let bytes = try data(hex: XCTUnwrap(item["hex"] as? String))
        let decoded = try ADFPEnvelopeCodec.decode(bytes, now: now)

        XCTAssertEqual(decoded.header.messageId, "message-1")
        XCTAssertEqual(decoded.header.senderDeviceId, "device-controller-1")
        XCTAssertEqual(decoded.header.senderRole, .controller)
        XCTAssertEqual(decoded.header.expiresAtEpochMillis, 4_102_444_800_000)

        guard case .input(let event) = decoded.payload else {
            return XCTFail("expected input payload")
        }
        XCTAssertEqual(event.type, .keyDown)
        XCTAssertEqual(event.sessionId, "session-1")
        XCTAssertEqual(event.generation, 7)
        XCTAssertEqual(event.seq, 42)
        XCTAssertEqual(event.timestamp, 1_700_000_000_123)
        XCTAssertEqual(event.key, "a")
        XCTAssertEqual(event.code, "KeyA")
        XCTAssertEqual(event.modifiers, ["Shift"])
        XCTAssertEqual(event.target, "window-1")

        let reencoded = try ADFPEnvelopeCodec.encodeInput(event, header: decoded.header, now: now)
        XCTAssertEqual(reencoded, bytes)
    }

    func testControlFixtureDecodesAndReencodes() throws {
        let item = try fixtureCase(named: "control-notice")
        let bytes = try data(hex: XCTUnwrap(item["hex"] as? String))
        let decoded = try ADFPEnvelopeCodec.decode(bytes, now: now)

        guard case .control(let control) = decoded.payload else {
            return XCTFail("expected control payload")
        }
        XCTAssertEqual(control.type, .notice)
        XCTAssertEqual(control.sessionId, "session-1")
        XCTAssertEqual(control.generation, 7)
        XCTAssertEqual(control.seq, 43)
        XCTAssertEqual(control.timestamp, 1_700_000_000_124)
        XCTAssertEqual(control.message, "connected")
        XCTAssertEqual(control.action, "focus")

        let reencoded = try ADFPEnvelopeCodec.encodeControl(control, header: decoded.header, now: now)
        XCTAssertEqual(reencoded, bytes)
    }

    func testInvalidFixturesAreRejected() throws {
        let invalid = try XCTUnwrap(fixture["invalid"] as? [[String: Any]])
        for item in invalid {
            let bytes = try data(hex: XCTUnwrap(item["hex"] as? String))
            XCTAssertThrowsError(try ADFPEnvelopeCodec.decode(bytes, now: now), "\(item["name"] ?? "")")
        }

        let item = try fixtureCase(named: "input-key-down")
        let bytes = try data(hex: XCTUnwrap(item["hex"] as? String))
        XCTAssertThrowsError(
            try ADFPEnvelopeCodec.decode(bytes, now: Date(timeIntervalSince1970: 4_102_444_800))
        ) { error in
            XCTAssertEqual(error as? ADFPEnvelopeError, .headerExpired)
        }

        XCTAssertThrowsError(try ADFPEnvelopeCodec.decode(Data(repeating: 0, count: 4))) { error in
            XCTAssertEqual(error as? ADFPEnvelopeError, .truncated)
        }
        XCTAssertThrowsError(try ADFPEnvelopeCodec.decode(Data())) { error in
            XCTAssertEqual(error as? ADFPEnvelopeError, .empty)
        }
    }

    func testHeaderValidationRejectsRequiredFields() throws {
        let header = ADFPHeader(
            messageId: "",
            senderDeviceId: "device-controller-1",
            senderRole: .controller,
            correlationId: nil,
            idempotencyKey: nil,
            expiresAtEpochMillis: 0,
            cancellationId: nil
        )
        let event = InputEvent.make(.pointerCancel, sessionId: "session-1", seq: 1)
        XCTAssertThrowsError(try ADFPEnvelopeCodec.encodeInput(event, header: header, now: now))
    }

    private func fixtureCase(named name: String) throws -> [String: Any] {
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        return try XCTUnwrap(cases.first { $0["name"] as? String == name })
    }

    private func data(hex: String) throws -> Data {
        var result = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw ADFPEnvelopeError.truncated
            }
            result.append(byte)
            index = next
        }
        return result
    }
}
