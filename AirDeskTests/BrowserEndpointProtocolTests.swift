import XCTest
@testable import AirDesk

final class BrowserEndpointProtocolTests: XCTestCase {
    private let token = "token_" + String(repeating: "a", count: 32)
    private let origin = "http://127.0.0.1:51234"

    func testTokenAndIdentifierValidation() {
        XCTAssertTrue(BrowserEndpointValidation.isValidToken(token))
        XCTAssertFalse(BrowserEndpointValidation.isValidToken("short"))
        XCTAssertFalse(BrowserEndpointValidation.isValidToken("token with spaces_123456"))

        XCTAssertTrue(BrowserEndpointValidation.isValidIdentifier("workspace-alpha_1:display.2"))
        XCTAssertFalse(BrowserEndpointValidation.isValidIdentifier(""))
        XCTAssertFalse(BrowserEndpointValidation.isValidIdentifier("workspace/beta"))
        XCTAssertFalse(BrowserEndpointValidation.isValidIdentifier(String(repeating: "a", count: 257)))
    }

    func testLoopbackOriginParsing() throws {
        let parsed = try BrowserEndpointOrigin.parseLoopback(origin)
        XCTAssertEqual(parsed.value, origin)
        XCTAssertEqual(parsed.port, 51_234)

        for value in [
            "http://localhost:51234",
            "http://192.168.1.4:51234",
            "https://example.com:443",
            "http://user@127.0.0.1:51234",
            "http://127.0.0.1",
            "http://127.0.0.1:51234/other"
        ] {
            XCTAssertThrowsError(try BrowserEndpointOrigin.parseLoopback(value), value)
        }
    }

    func testDisplayRegistrationMessageContract() throws {
        let message = try parseMessage(
            type: "display.register",
            workspaceId: "workspace-alpha",
            displaySessionId: "display-1",
            viewport: ["width": 1024, "height": 768],
            focusTarget: NSNull(),
            generation: 0
        )

        XCTAssertEqual(message.kind, .register)
        XCTAssertEqual(message.state.workspaceId, "workspace-alpha")
        XCTAssertEqual(message.state.displaySessionId, "display-1")
        XCTAssertEqual(message.state.viewport, BrowserEndpointViewport(width: 1024, height: 768))
        XCTAssertNil(message.state.focusTarget)
        XCTAssertEqual(message.state.generation, 0)
    }

    func testDisplayUpdateMessages() throws {
        let viewport = try parseMessage(
            type: "display.viewport",
            viewport: ["width": 1280, "height": 720],
            focusTarget: NSNull(),
            generation: 1
        )
        XCTAssertEqual(viewport.kind, .viewport)

        let focus = try parseMessage(
            type: "display.focus",
            viewport: ["width": 1280, "height": 720],
            focusTarget: "editor",
            generation: 2
        )
        XCTAssertEqual(focus.kind, .focus)
        XCTAssertEqual(focus.state.focusTarget, "editor")
    }

    func testDisplayMessageRejectsAuthorityAndInvalidFields() {
        XCTAssertThrowsError(try parseMessage(canWriteWorkspace: true))
        XCTAssertThrowsError(try parseMessage(role: "controller"))
        XCTAssertThrowsError(try parseMessage(authority: "owner"))
        XCTAssertThrowsError(try parseMessage(workspaceId: "workspace/beta"))
        XCTAssertThrowsError(try parseMessage(displaySessionId: ""))
        XCTAssertThrowsError(try parseMessage(viewport: ["width": -1, "height": 720]))
        XCTAssertThrowsError(try parseMessage(viewport: ["width": "wide", "height": 720]))
        XCTAssertThrowsError(try parseMessage(focusTarget: String(repeating: "x", count: 513)))
        XCTAssertThrowsError(try parseMessage(generation: -1))

        XCTAssertThrowsError(try BrowserEndpointMessageCodec.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try parseMessage(type: "display.unknown"))
        XCTAssertThrowsError(try parseMessage(type: "input.key"))
    }

    func testServerMessagesEncodeExpectedContract() throws {
        let registration = BrowserEndpointRegistration(
            connectionId: UUID(),
            workspaceId: "workspace-alpha",
            displaySessionId: "display-1",
            viewport: BrowserEndpointViewport(width: 1024, height: 768),
            focusTarget: nil,
            generation: 3
        )
        let registered = try json(BrowserEndpointMessageCodec.registered(registration))
        XCTAssertEqual(registered["type"] as? String, "display.registered")
        XCTAssertEqual(registered["workspaceId"] as? String, "workspace-alpha")
        XCTAssertEqual(registered["displaySessionId"] as? String, "display-1")
        XCTAssertEqual(registered["authority"] as? String, "none")
        XCTAssertEqual(registered["canWriteWorkspace"] as? Bool, false)

        let error = try json(
            BrowserEndpointMessageCodec.error(
                code: .workspaceMismatch,
                message: "workspace does not match"
            )
        )
        XCTAssertEqual(error["type"] as? String, "display.error")
        XCTAssertEqual(error["code"] as? String, "workspace-mismatch")
        XCTAssertEqual(error["message"] as? String, "workspace does not match")
    }

    func testFrameEncodingRoundTrip() throws {
        let serverFrame = BrowserEndpointFrame.text(Data("hello".utf8))
        var serverData = serverFrame.encoded(masked: false)
        let parsedServer = try XCTUnwrap(
            try BrowserEndpointFrameParser.parse(
                from: &serverData,
                expectedMasked: false,
                maximumPayload: 1024
            )
        )
        XCTAssertEqual(parsedServer, serverFrame)
        XCTAssertTrue(serverData.isEmpty)

        let clientFrame = BrowserEndpointFrame.text(Data("hello".utf8))
        var clientData = clientFrame.encoded(masked: true)
        let parsedClient = try XCTUnwrap(
            try BrowserEndpointFrameParser.parse(
                from: &clientData,
                expectedMasked: true,
                maximumPayload: 1024
            )
        )
        XCTAssertEqual(parsedClient, clientFrame)
    }

    func testFrameParserRejectsUnmaskedClientFramesAndOversizePayloads() {
        var unmasked = BrowserEndpointFrame.text(Data("hello".utf8)).encoded(masked: false)
        XCTAssertThrowsError(
            try BrowserEndpointFrameParser.parse(
                from: &unmasked,
                expectedMasked: true,
                maximumPayload: 1024
            )
        )

        var oversized = BrowserEndpointFrame.text(Data(repeating: 0, count: 128)).encoded(masked: true)
        XCTAssertThrowsError(
            try BrowserEndpointFrameParser.parse(
                from: &oversized,
                expectedMasked: true,
                maximumPayload: 64
            )
        )
    }

    func testFragmentAndControlFrames() throws {
        let first = BrowserEndpointFrame(opcode: .text, payload: Data("hel".utf8), fin: false)
        let second = BrowserEndpointFrame(opcode: .continuation, payload: Data("lo".utf8), fin: true)
        var data = first.encoded(masked: true)
        data.append(second.encoded(masked: true))

        let parsedFirst = try XCTUnwrap(
            try BrowserEndpointFrameParser.parse(from: &data, expectedMasked: true, maximumPayload: 1024)
        )
        let parsedSecond = try XCTUnwrap(
            try BrowserEndpointFrameParser.parse(from: &data, expectedMasked: true, maximumPayload: 1024)
        )
        XCTAssertEqual(parsedFirst.opcode, .text)
        XCTAssertFalse(parsedFirst.fin)
        XCTAssertEqual(parsedSecond.opcode, .continuation)
        XCTAssertTrue(parsedSecond.fin)

        let ping = BrowserEndpointFrame.ping(Data([1, 2, 3]))
        var pingData = ping.encoded(masked: true)
        let parsedPing = try XCTUnwrap(
            try BrowserEndpointFrameParser.parse(from: &pingData, expectedMasked: true, maximumPayload: 1024)
        )
        XCTAssertEqual(parsedPing.opcode, .ping)
        XCTAssertEqual(parsedPing.payload, Data([1, 2, 3]))
    }

    func testHTTPRequestParsing() throws {
        let raw = validRequest(target: "/endpoint?token=\(token)")
        let request = try BrowserEndpointHTTPRequestParser.parse(Data(raw.utf8))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.target, "/endpoint?token=\(token)")
        XCTAssertEqual(request.version, "HTTP/1.1")
        XCTAssertEqual(request.singleValue(for: "origin"), origin)
        XCTAssertEqual(request.values(for: "connection"), ["Upgrade"])

        XCTAssertThrowsError(try BrowserEndpointHTTPRequestParser.parse(Data("bad\r\n\r\n".utf8)))
        XCTAssertThrowsError(
            try BrowserEndpointHTTPRequestParser.parse(
                Data("GET / HTTP/1.1\r\n Folded: yes\r\n\r\n".utf8)
            )
        )
        XCTAssertThrowsError(
            try BrowserEndpointHTTPRequestParser.parse(
                Data(repeating: 0x41, count: BrowserEndpointHTTPRequestParser.maximumHeaderBytes + 1)
            )
        )
    }

    func testHandshakeValidationAcceptsLoopbackWebSocket() throws {
        let request = try BrowserEndpointHTTPRequestParser.parse(
            Data(validRequest(target: "/endpoint?token=\(token)").utf8)
        )
        let handshake = try BrowserEndpointHandshake.validate(request, policy: policy())
        XCTAssertEqual(handshake.token, token)
        XCTAssertEqual(handshake.origin.value, origin)

        let response = String(decoding: handshake.acceptResponseData(), as: UTF8.self)
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 101 Switching Protocols"))
        XCTAssertTrue(response.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo="))
    }

    func testHandshakeRejectsMalformedRequests() {
        XCTAssertEqual(handshakeFailure(method: "POST"), .invalidMethod)
        XCTAssertEqual(handshakeFailure(version: "HTTP/1.0"), .invalidHTTPVersion)
        XCTAssertEqual(handshakeFailure(removeHeader: "host"), .missingHost)
        XCTAssertEqual(handshakeFailure(target: "/other?token=\(token)"), .invalidPath)
        XCTAssertEqual(handshakeFailure(removeHeader: "upgrade"), .missingUpgrade)
        XCTAssertEqual(handshakeFailure(header: "connection", value: "keep-alive"), .invalidConnection)
        XCTAssertEqual(handshakeFailure(header: "sec-websocket-version", value: "8"), .unsupportedVersion)
        XCTAssertEqual(handshakeFailure(removeHeader: "sec-websocket-key"), .missingKey)
        XCTAssertEqual(handshakeFailure(header: "sec-websocket-key", value: "not-base64"), .invalidKey)
        XCTAssertEqual(handshakeFailure(target: "/endpoint"), .missingToken)
        XCTAssertEqual(
            handshakeFailure(target: "/endpoint?token=\(token)&token=\(token)"),
            .duplicateToken
        )
        XCTAssertEqual(handshakeFailure(target: "/endpoint?token=short"), .invalidToken)
        XCTAssertEqual(handshakeFailure(target: "/endpoint?token=\(token)wrong"), .invalidToken)
        XCTAssertEqual(handshakeFailure(removeHeader: "origin"), .missingOrigin)
        XCTAssertEqual(
            handshakeFailure(header: "origin", value: "http://192.168.1.4:51234"),
            .invalidOrigin
        )
        XCTAssertEqual(
            handshakeFailure(header: "origin", value: "http://localhost:51234"),
            .invalidOrigin
        )
        XCTAssertEqual(
            handshakeFailure(header: "origin", value: "http://127.0.0.1:51235"),
            .originMismatch
        )
    }

    func testHandshakeRejectsExpiredToken() {
        XCTAssertEqual(
            handshakeFailure(policy: policy(expiresIn: -1)),
            .tokenExpired
        )
    }

    func testHandshakeRejectionHTTPStatuses() {
        XCTAssertEqual(BrowserEndpointHandshakeError.invalidToken.statusCode, 401)
        XCTAssertEqual(BrowserEndpointHandshakeError.invalidToken.responseData.count > 0, true)
        XCTAssertEqual(BrowserEndpointHandshakeError.invalidOrigin.statusCode, 403)
        XCTAssertEqual(BrowserEndpointHandshakeError.invalidPath.statusCode, 404)
        XCTAssertEqual(BrowserEndpointHandshakeError.invalidMethod.statusCode, 405)
        XCTAssertEqual(BrowserEndpointHandshakeError.unsupportedVersion.statusCode, 426)
        XCTAssertEqual(
            BrowserEndpointHandshakeError.unsupportedVersion.responseHeaders["Sec-WebSocket-Version"],
            "13"
        )
        XCTAssertEqual(BrowserEndpointHandshakeError.requestTooLarge.statusCode, 431)
    }

    private func policy(expiresIn: TimeInterval = 60) -> BrowserEndpointHandshakePolicy {
        BrowserEndpointHandshakePolicy(
            path: "/endpoint",
            token: token,
            tokenExpiresAt: Date().addingTimeInterval(expiresIn),
            allowedOrigin: try! BrowserEndpointOrigin.parseLoopback(origin)
        )
    }

    private func validRequest(target: String) -> String {
        [
            "GET \(target) HTTP/1.1",
            "Host: 127.0.0.1:51234",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
            "Origin: \(origin)",
            "",
            ""
        ].joined(separator: "\r\n")
    }

    private func handshakeFailure(
        method: String = "GET",
        target: String? = nil,
        version: String = "HTTP/1.1",
        header: String? = nil,
        value: String? = nil,
        removeHeader: String? = nil,
        policy: BrowserEndpointHandshakePolicy? = nil
    ) -> BrowserEndpointHandshakeError? {
        var headers: [String: [String]] = [
            "host": ["127.0.0.1:51234"],
            "upgrade": ["websocket"],
            "connection": ["Upgrade"],
            "sec-websocket-version": ["13"],
            "sec-websocket-key": ["dGhlIHNhbXBsZSBub25jZQ=="],
            "origin": [origin]
        ]
        if let removeHeader {
            headers.removeValue(forKey: removeHeader)
        }
        if let header, let value {
            headers[header] = [value]
        }
        let request = BrowserEndpointHTTPRequest(
            method: method,
            target: target ?? "/endpoint?token=\(token)",
            version: version,
            headers: headers
        )
        do {
            _ = try BrowserEndpointHandshake.validate(
                request,
                policy: policy ?? self.policy()
            )
            return nil
        } catch let error as BrowserEndpointHandshakeError {
            return error
        } catch {
            XCTFail("Unexpected error: \(error)")
            return nil
        }
    }

    private func parseMessage(
        type: String = "display.register",
        role: String = "display",
        authority: String = "none",
        workspaceId: String = "workspace-alpha",
        displaySessionId: String = "display-1",
        viewport: [String: Any] = ["width": 1024, "height": 768],
        focusTarget: Any = NSNull(),
        generation: Int = 0,
        canWriteWorkspace: Bool = false
    ) throws -> BrowserEndpointMessage {
        let object: [String: Any] = [
            "type": type,
            "role": role,
            "authority": authority,
            "workspaceId": workspaceId,
            "displaySessionId": displaySessionId,
            "viewport": viewport,
            "focusTarget": focusTarget,
            "generation": generation,
            "canWriteWorkspace": canWriteWorkspace
        ]
        return try BrowserEndpointMessageCodec.parse(JSONSerialization.data(withJSONObject: object))
    }

    private func json(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
