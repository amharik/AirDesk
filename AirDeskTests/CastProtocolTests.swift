import XCTest
@testable import AirDesk

final class CastProtocolTests: XCTestCase {
    func testSessionStartRoundTripsWithProtocolVersions() throws {
        let message = CastControlMessage.sessionStart(
            sessionId: "ads-test",
            generation: 3,
            workspace: "Wanix",
            appearance: "dark",
            operationId: "op-1"
        )

        let json = try message.jsonString()
        let decoded = try CastControlMessage.decode(from: json)

        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.protocolInfo, CastProtocolVersions(input: 1, control: 2))
        XCTAssertTrue(json.contains("\"protocol\""))
    }

    func testUnsupportedVersionIsRejected() throws {
        let json = """
        {"version":1,"type":"sessionStart","sessionId":"ads-test","generation":1,"workspace":"Wanix","appearance":"dark"}
        """

        XCTAssertThrowsError(try CastControlMessage.decode(from: json)) { error in
            XCTAssertEqual(error as? CastProtocolError, .unsupportedVersion)
        }
    }

    func testUnsupportedProtocolVersionsAreRejected() {
        let message = CastControlMessage(
            type: .sessionStart,
            sessionId: "ads-test",
            generation: 1,
            workspace: "Wanix",
            appearance: "dark",
            protocolInfo: CastProtocolVersions(input: 2, control: 2)
        )

        XCTAssertThrowsError(try message.validated()) { error in
            XCTAssertEqual(error as? CastProtocolError, .unsupportedVersion)
        }
    }

    func testUnknownTypeIsRejected() {
        let json = """
        {"version":2,"type":"execute","sessionId":"ads-test","generation":1}
        """

        XCTAssertThrowsError(try CastControlMessage.decode(from: json)) { error in
            XCTAssertEqual(error as? CastProtocolError, .malformedPayload)
        }
    }

    func testInvalidSessionAndGenerationAreRejected() {
        let emptySession = """
        {"version":2,"type":"ping","sessionId":"","generation":1}
        """
        XCTAssertThrowsError(try CastControlMessage.decode(from: emptySession)) { error in
            XCTAssertEqual(error as? CastProtocolError, .invalidSession)
        }

        let negativeGeneration = """
        {"version":2,"type":"ping","sessionId":"ads-test","generation":-1}
        """
        XCTAssertThrowsError(try CastControlMessage.decode(from: negativeGeneration)) { error in
            XCTAssertEqual(error as? CastProtocolError, .invalidGeneration)
        }
    }

    func testUnknownOptionalFieldsAreIgnored() throws {
        let json = """
        {"version":2,"type":"ping","sessionId":"ads-test","generation":1,"futureField":{"value":42}}
        """

        let decoded = try CastControlMessage.decode(from: json)
        XCTAssertEqual(decoded.type, .ping)
        XCTAssertEqual(decoded.sessionId, "ads-test")
    }

    func testResumeRequiresLastAcknowledgedSequence() throws {
        let missing = """
        {"version":2,"type":"sessionResume","sessionId":"ads-test","generation":1}
        """
        XCTAssertThrowsError(try CastControlMessage.decode(from: missing)) { error in
            XCTAssertEqual(error as? CastProtocolError, .invalidField)
        }

        let message = CastControlMessage.sessionResume(
            sessionId: "ads-test",
            generation: 1,
            lastAckedInputSeq: 42,
            operationId: "op-resume"
        )
        XCTAssertNoThrow(try message.validated())
        XCTAssertEqual(message.lastAckedInputSeq, 42)
    }

    func testReadyRequiresCapabilitiesAndDimensions() {
        let missingCapabilities = """
        {"version":2,"type":"ready","sessionId":"ads-test","generation":1,"receiverVersion":"1","width":1920,"height":1080,"persistence":"opfs","lastAcceptedInputSeq":0}
        """
        XCTAssertThrowsError(try CastControlMessage.decode(from: missingCapabilities)) { error in
            XCTAssertEqual(error as? CastProtocolError, .invalidField)
        }

        let invalidDimension = """
        {"version":2,"type":"ready","sessionId":"ads-test","generation":1,"receiverVersion":"1","width":0,"height":1080,"persistence":"opfs","capabilities":{"pointer":true,"keyboard":true,"textInput":true,"desktopWindows":true},"lastAcceptedInputSeq":0}
        """
        XCTAssertThrowsError(try CastControlMessage.decode(from: invalidDimension)) { error in
            XCTAssertEqual(error as? CastProtocolError, .invalidField)
        }
    }

    func testOversizedPayloadIsRejectedBeforeDecoding() {
        let padding = String(repeating: "x", count: CastProtocol.maxMessageBytes)
        let json = """
        {"version":2,"type":"ping","sessionId":"ads-test","generation":1,"extra":"\(padding)"}
        """

        XCTAssertThrowsError(try CastControlMessage.decode(from: json)) { error in
            XCTAssertEqual(error as? CastProtocolError, .messageTooLarge)
        }
    }

    func testAckCarriesHighestAcceptedSequence() throws {
        let message = CastControlMessage.ack(
            sessionId: "ads-test",
            generation: 2,
            lastAcceptedInputSeq: 17
        )

        let decoded = try CastControlMessage.decode(from: message.jsonString())
        XCTAssertEqual(decoded.type, .ack)
        XCTAssertEqual(decoded.lastAcceptedInputSeq, 17)
    }
}
