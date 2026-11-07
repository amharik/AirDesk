import Foundation
import XCTest
@testable import AirDesk

final class BrowserEndpointHostTests: XCTestCase {
    private let token = "token_" + String(repeating: "b", count: 32)
    private let origin = "http://127.0.0.1:51234"

    func testListenerBindsLoopbackEphemeralPortAndRestarts() throws {
        let host = try makeHost()
        defer { host.stop() }

        let address = try host.start()
        XCTAssertEqual(address.host, "127.0.0.1")
        XCTAssertGreaterThan(address.port, 0)
        XCTAssertEqual(address.path, "/endpoint")
        XCTAssertEqual(address.endpointURL, "ws://127.0.0.1:\(address.port)/endpoint")
        XCTAssertEqual(host.runningPort, address.port)

        host.stop()
        XCTAssertNil(host.runningPort)

        let restarted = try host.start()
        XCTAssertGreaterThan(restarted.port, 0)
        XCTAssertEqual(host.runningPort, restarted.port)
    }

    func testRegistersDisplayAndAppliesViewportAndFocusUpdates() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let recorder = BrowserEndpointHostRecorder()
        recorder.attach(to: host)
        let address = try host.start()

        let client = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: "/endpoint?token=\(token)",
            origin: origin
        )
        defer { client.close() }

        client.sendText(try registrationMessage())
        let registered = try json(from: try await client.nextText())
        XCTAssertEqual(registered["type"] as? String, "display.registered")
        XCTAssertEqual(registered["role"] as? String, "display")
        XCTAssertEqual(registered["authority"] as? String, "none")
        XCTAssertEqual(registered["canWriteWorkspace"] as? Bool, false)
        XCTAssertEqual(registered["workspaceId"] as? String, "workspace-alpha")
        XCTAssertEqual(registered["displaySessionId"] as? String, "display-1")
        XCTAssertEqual(registered["generation"] as? Int, 0)

        try await waitUntil {
            host.registeredDisplays().count == 1
        }
        let registration = try XCTUnwrap(host.registeredDisplays().first)
        XCTAssertEqual(registration.workspaceId, "workspace-alpha")
        XCTAssertEqual(registration.displaySessionId, "display-1")
        XCTAssertEqual(registration.viewport, BrowserEndpointViewport(width: 1024, height: 768))
        XCTAssertNil(registration.focusTarget)
        XCTAssertEqual(registration.generation, 0)

        client.sendText(
            try updateMessage(type: "display.viewport", generation: 1, viewport: (1280, 720))
        )
        try await waitUntil {
            host.registeredDisplays().first?.viewport ==
                BrowserEndpointViewport(width: 1280, height: 720)
        }

        client.sendText(
            try updateMessage(
                type: "display.focus",
                generation: 2,
                viewport: (1280, 720),
                focusTarget: "editor"
            )
        )
        try await waitUntil {
            host.registeredDisplays().first?.focusTarget == "editor"
        }
        let updated = try XCTUnwrap(host.registeredDisplays().first)
        XCTAssertEqual(updated.generation, 2)
        XCTAssertEqual(updated.viewport, BrowserEndpointViewport(width: 1280, height: 720))

        try await waitUntil {
            recorder.registrations.count == 1 && recorder.updates.count == 2
        }
        XCTAssertEqual(recorder.registrations.count, 1)
        XCTAssertEqual(recorder.updates.map(\.kind), [.viewport, .focus])
        XCTAssertEqual(recorder.updates.last?.registration.focusTarget, "editor")
    }

    func testRejectsDuplicateActiveRegistration() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let address = try host.start()
        let target = "/endpoint?token=\(token)"

        let first = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { first.close() }
        first.sendText(try registrationMessage())
        _ = try await first.nextText()
        try await waitUntil { host.registeredDisplays().count == 1 }

        let second = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { second.close() }
        second.sendText(try registrationMessage())

        let error = try json(from: try await second.nextText())
        XCTAssertEqual(error["type"] as? String, "display.error")
        XCTAssertEqual(error["code"] as? String, "invalid-state")
        XCTAssertEqual(host.registeredDisplays().count, 1)
    }

    func testNewerGenerationReplacesActiveDisplayWithoutChangingWorkspace() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let recorder = BrowserEndpointHostRecorder()
        recorder.attach(to: host)
        let address = try host.start()
        let target = "/endpoint?token=\(token)"

        let first = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        first.sendText(try registrationMessage())
        _ = try await first.nextText()
        try await waitUntil { host.registeredDisplays().count == 1 }

        let second = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { second.close() }
        second.sendText(try registrationMessage(generation: 1))

        let registered = try json(from: try await second.nextText())
        XCTAssertEqual(registered["type"] as? String, "display.registered")
        XCTAssertEqual(registered["workspaceId"] as? String, "workspace-alpha")
        XCTAssertEqual(registered["displaySessionId"] as? String, "display-1")
        XCTAssertEqual(registered["generation"] as? Int, 1)

        try await first.waitUntilClosed()
        first.close()
        try await waitUntil {
            host.registeredDisplays().count == 1 &&
                host.registeredDisplays().first?.generation == 1
        }
        XCTAssertEqual(host.registeredDisplays().first?.workspaceId, "workspace-alpha")
        try await waitUntil { recorder.registrations.count == 2 }
        XCTAssertEqual(recorder.registrations.last?.displaySessionId, "display-1")
        XCTAssertEqual(recorder.registrations.last?.workspaceId, "workspace-alpha")
    }

    func testRejectsWorkspaceAndDisplaySessionMismatches() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let address = try host.start()
        let target = "/endpoint?token=\(token)"

        let workspaceClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { workspaceClient.close() }
        workspaceClient.sendText(try registrationMessage())
        _ = try await workspaceClient.nextText()
        workspaceClient.sendText(
            try updateMessage(
                type: "display.viewport",
                workspaceId: "workspace-other",
                generation: 1,
                viewport: (1280, 720)
            )
        )
        let workspaceError = try json(from: try await workspaceClient.nextText())
        XCTAssertEqual(workspaceError["code"] as? String, "workspace-mismatch")
        try await waitUntil { host.registeredDisplays().isEmpty }

        let displayClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { displayClient.close() }
        displayClient.sendText(try registrationMessage())
        _ = try await displayClient.nextText()
        displayClient.sendText(
            try updateMessage(
                type: "display.focus",
                displaySessionId: "display-other",
                generation: 1,
                viewport: (1024, 768),
                focusTarget: "editor"
            )
        )
        let displayError = try json(from: try await displayClient.nextText())
        XCTAssertEqual(displayError["code"] as? String, "display-session-mismatch")
    }

    func testRejectsStaleGenerationAndInvalidUpdates() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let address = try host.start()

        let client = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: "/endpoint?token=\(token)",
            origin: origin
        )
        defer { client.close() }
        client.sendText(try registrationMessage(generation: 5))
        _ = try await client.nextText()
        XCTAssertEqual(host.registeredDisplays().first?.generation, 5)

        client.sendText(
            try updateMessage(type: "display.viewport", generation: 5, viewport: (1280, 720))
        )
        let stale = try json(from: try await client.nextText())
        XCTAssertEqual(stale["code"] as? String, "protocol-error")

        let invalidViewportClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: "/endpoint?token=\(token)",
            origin: origin
        )
        defer { invalidViewportClient.close() }
        invalidViewportClient.sendText(
            try registrationMessage(displaySessionId: "display-2")
        )
        _ = try await invalidViewportClient.nextText()
        invalidViewportClient.sendText(
            try updateMessage(
                type: "display.viewport",
                displaySessionId: "display-2",
                generation: 1,
                viewport: (0, 720)
            )
        )
        let invalidViewport = try json(from: try await invalidViewportClient.nextText())
        XCTAssertEqual(invalidViewport["code"] as? String, "protocol-error")
    }

    func testRejectsAuthorityEscalationAndUnsupportedMessages() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let address = try host.start()
        let target = "/endpoint?token=\(token)"

        let authorityClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { authorityClient.close() }
        authorityClient.sendText(try registrationMessage(authority: "owner"))
        let authorityError = try json(from: try await authorityClient.nextText())
        XCTAssertEqual(authorityError["type"] as? String, "display.error")
        XCTAssertEqual(authorityError["code"] as? String, "protocol-error")
        XCTAssertTrue(host.registeredDisplays().isEmpty)

        let unsupportedClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { unsupportedClient.close() }
        unsupportedClient.sendText(try registrationMessage())
        _ = try await unsupportedClient.nextText()
        unsupportedClient.sendText(
            """
            {"type":"input.key","role":"display","authority":"none","workspaceId":"workspace-alpha",\
            "displaySessionId":"display-1","viewport":{"width":1024,"height":768},\
            "focusTarget":null,"generation":1,"canWriteWorkspace":false}
            """
        )
        let unsupportedError = try json(from: try await unsupportedClient.nextText())
        XCTAssertEqual(unsupportedError["type"] as? String, "display.error")
        XCTAssertEqual(unsupportedError["code"] as? String, "protocol-error")

        let malformedClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { malformedClient.close() }
        malformedClient.sendText(try registrationMessage(displaySessionId: "display-3"))
        _ = try await malformedClient.nextText()
        malformedClient.sendText("not json")
        let malformedError = try json(from: try await malformedClient.nextText())
        XCTAssertEqual(malformedError["type"] as? String, "display.error")
        XCTAssertEqual(malformedError["code"] as? String, "protocol-error")
    }

    func testHandshakeRejections() async throws {
        let host = try makeHost()
        defer { host.stop() }
        let address = try host.start()

        try await assertStatus(
            404,
            port: address.port,
            request: request(port: address.port, target: "/other?token=\(token)")
        )
        try await assertStatus(
            401,
            port: address.port,
            request: request(port: address.port, target: "/endpoint")
        )
        try await assertStatus(
            400,
            port: address.port,
            request: request(
                port: address.port,
                target: "/endpoint?token=\(token)&token=\(token)"
            )
        )
        try await assertStatus(
            401,
            port: address.port,
            request: request(port: address.port, target: "/endpoint?token=short")
        )
        try await assertStatus(
            403,
            port: address.port,
            request: request(
                port: address.port,
                target: "/endpoint?token=\(token)",
                origin: "http://192.168.1.4:51234"
            )
        )
        try await assertStatus(
            403,
            port: address.port,
            request: request(
                port: address.port,
                target: "/endpoint?token=\(token)",
                origin: "http://127.0.0.1:51235"
            )
        )
        try await assertStatus(
            403,
            port: address.port,
            request: request(
                port: address.port,
                target: "/endpoint?token=\(token)",
                includeOrigin: false
            )
        )
        try await assertStatus(
            400,
            port: address.port,
            request: request(
                port: address.port,
                target: "/endpoint?token=\(token)",
                includeUpgrade: false
            )
        )

        let expiredHost = try makeHost(tokenExpiresIn: -1)
        defer { expiredHost.stop() }
        let expiredAddress = try expiredHost.start()
        try await assertStatus(
            401,
            port: expiredAddress.port,
            request: request(
                port: expiredAddress.port,
                target: "/endpoint?token=\(token)"
            )
        )
    }

    func testRejectsUnmaskedFramesAndOversizeMessages() async throws {
        let host = try makeHost(maximumMessageBytes: 1_024)
        defer { host.stop() }
        let address = try host.start()
        let target = "/endpoint?token=\(token)"

        let unmaskedClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { unmaskedClient.close() }
        unmaskedClient.sendText(try registrationMessage())
        _ = try await unmaskedClient.nextText()
        unmaskedClient.sendUnmaskedText("{}")
        let close = try await unmaskedClient.nextFrame()
        XCTAssertEqual(close.opcode, .close)
        XCTAssertEqual(closeCode(close), 1002)

        let oversizedClient = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { oversizedClient.close() }
        oversizedClient.sendText(try registrationMessage(displaySessionId: "display-2"))
        _ = try await oversizedClient.nextText()
        oversizedClient.sendText(String(repeating: "x", count: 2_048))
        let oversizeClose = try await oversizedClient.nextFrame()
        XCTAssertEqual(oversizeClose.opcode, .close)
        XCTAssertEqual(closeCode(oversizeClose), 1009)
    }

    func testPingPongLivenessAndCleanCloseThenReconnect() async throws {
        let host = try makeHost(heartbeatInterval: 0.05, heartbeatTimeout: 0.5)
        defer { host.stop() }
        let address = try host.start()
        let target = "/endpoint?token=\(token)"

        let first = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        first.sendText(try registrationMessage())
        _ = try await first.nextText()

        var ping: BrowserEndpointFrame?
        for _ in 0..<10 {
            let frame = try await first.nextFrame()
            if frame.opcode == .ping {
                ping = frame
                break
            }
        }
        let heartbeat = try XCTUnwrap(ping)
        XCTAssertFalse(heartbeat.payload.isEmpty)
        first.sendPong(heartbeat.payload)
        first.sendText(
            try updateMessage(type: "display.viewport", generation: 1, viewport: (1440, 900))
        )
        try await waitUntil {
            host.registeredDisplays().first?.viewport ==
                BrowserEndpointViewport(width: 1440, height: 900)
        }

        first.sendClose(code: 1000, reason: "client-stop")
        var close: BrowserEndpointFrame?
        for _ in 0..<10 {
            let frame = try await first.nextFrame()
            if frame.opcode == .close {
                close = frame
                break
            }
        }
        XCTAssertEqual(close?.opcode, .close)
        try await first.waitUntilClosed()
        first.close()
        try await waitUntil { host.registeredDisplays().isEmpty }

        let second = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: target,
            origin: origin
        )
        defer { second.close() }
        second.sendText(
            try registrationMessage(displaySessionId: "display-1", generation: 2)
        )
        let registered = try json(from: try await second.nextText())
        XCTAssertEqual(registered["type"] as? String, "display.registered")
        XCTAssertEqual(registered["displaySessionId"] as? String, "display-1")
        try await waitUntil { host.registeredDisplays().count == 1 }
    }

    func testHeartbeatTimeoutClosesUnresponsiveDisplay() async throws {
        let host = try makeHost(heartbeatInterval: 0.05, heartbeatTimeout: 0.1)
        defer { host.stop() }
        let address = try host.start()

        let client = try await BrowserEndpointTestClient.connect(
            port: address.port,
            target: "/endpoint?token=\(token)",
            origin: origin
        )
        defer { client.close() }
        client.sendText(try registrationMessage())
        _ = try await client.nextText()

        var close: BrowserEndpointFrame?
        for _ in 0..<20 {
            let frame = try await client.nextFrame()
            if frame.opcode == .close {
                close = frame
                break
            }
        }
        let timeoutClose = try XCTUnwrap(close)
        XCTAssertEqual(closeCode(timeoutClose), 1001)
        try await waitUntil { host.registeredDisplays().isEmpty }
    }

    private func makeHost(
        tokenExpiresIn: TimeInterval = 60,
        heartbeatInterval: TimeInterval = 0,
        heartbeatTimeout: TimeInterval = 0.5,
        maximumMessageBytes: Int = 64 * 1024
    ) throws -> BrowserEndpointHost {
        try BrowserEndpointHost(
            configuration: BrowserEndpointHostConfiguration(
                token: token,
                tokenExpiresAt: Date().addingTimeInterval(tokenExpiresIn),
                allowedOrigin: origin,
                heartbeatInterval: heartbeatInterval,
                heartbeatTimeout: heartbeatTimeout,
                handshakeTimeout: 2,
                maximumMessageBytes: maximumMessageBytes
            )
        )
    }

    private func assertStatus(
        _ expected: Int,
        port: UInt16,
        request: String
    ) async throws {
        let client = try await BrowserEndpointTestClient.open(port: port, request: request)
        defer { client.close() }
        let response = try await client.readHTTPResponse()
        XCTAssertEqual(response.statusCode, expected, response.statusLine)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Condition was not met before timeout.", file: file, line: line)
        throw BrowserEndpointTestClientError.timedOut
    }

    private func request(
        port: UInt16,
        target: String,
        origin: String = "",
        includeUpgrade: Bool = true,
        includeOrigin: Bool = true
    ) -> String {
        var lines = [
            "GET \(target) HTTP/1.1",
            "Host: 127.0.0.1:\(port)"
        ]
        if includeUpgrade {
            lines.append("Upgrade: websocket")
            lines.append("Connection: Upgrade")
        }
        lines.append("Sec-WebSocket-Version: 13")
        lines.append("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==")
        if includeOrigin {
            lines.append("Origin: \(origin.isEmpty ? self.origin : origin)")
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private func registrationMessage(
        workspaceId: String = "workspace-alpha",
        displaySessionId: String = "display-1",
        viewport: (Int, Int) = (1024, 768),
        focusTarget: String? = nil,
        generation: Int = 0,
        authority: String = "none"
    ) throws -> String {
        try encode([
            "type": "display.register",
            "role": "display",
            "authority": authority,
            "workspaceId": workspaceId,
            "displaySessionId": displaySessionId,
            "viewport": ["width": viewport.0, "height": viewport.1],
            "focusTarget": focusTarget ?? NSNull(),
            "generation": generation,
            "canWriteWorkspace": false
        ])
    }

    private func updateMessage(
        type: String,
        workspaceId: String = "workspace-alpha",
        displaySessionId: String = "display-1",
        generation: Int,
        viewport: (Int, Int),
        focusTarget: String? = nil
    ) throws -> String {
        try encode([
            "type": type,
            "role": "display",
            "authority": "none",
            "workspaceId": workspaceId,
            "displaySessionId": displaySessionId,
            "viewport": ["width": viewport.0, "height": viewport.1],
            "focusTarget": focusTarget ?? NSNull(),
            "generation": generation,
            "canWriteWorkspace": false
        ])
    }

    private func encode(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func json(from text: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func closeCode(_ frame: BrowserEndpointFrame) -> UInt16? {
        guard frame.opcode == .close, frame.payload.count >= 2 else { return nil }
        let bytes = Array(frame.payload)
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }
}

private final class BrowserEndpointHostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRegistrations: [BrowserEndpointRegistration] = []
    private var storedUpdates: [BrowserEndpointDisplayUpdate] = []
    private var storedClosed: [UUID] = []

    var registrations: [BrowserEndpointRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return storedRegistrations
    }

    var updates: [BrowserEndpointDisplayUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return storedUpdates
    }

    var closed: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return storedClosed
    }

    func attach(to host: BrowserEndpointHost) {
        host.onDisplayRegistered = { [weak self] registration in
            guard let self else { return }
            self.lock.lock()
            self.storedRegistrations.append(registration)
            self.lock.unlock()
        }
        host.onDisplayUpdated = { [weak self] update in
            guard let self else { return }
            self.lock.lock()
            self.storedUpdates.append(update)
            self.lock.unlock()
        }
        host.onConnectionClosed = { [weak self] id in
            guard let self else { return }
            self.lock.lock()
            self.storedClosed.append(id)
            self.lock.unlock()
        }
    }
}
