import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import XCTest
@testable import AirDesk

final class SSHPTYSessionTests: XCTestCase {
    func testPTYShellInputResizeAndClose() async throws {
        let server = TestSSHServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let configuration = try SSHPTYConfiguration(
            host: "127.0.0.1",
            port: port,
            username: "tester",
            authentication: .password("secret"),
            expectedHostKey: String(openSSHPublicKey: server.hostKey.publicKey),
            size: .init(columns: 80, rows: 24),
            connectTimeout: .seconds(5)
        )
        let session = SSHPTYSession(configuration: configuration)
        let output = OutputBox()
        let consumer = Task {
            do {
                for try await data in session.output {
                    await output.append(data)
                }
            } catch {
                await output.finish(error: error)
            }
        }
        defer { consumer.cancel() }

        try await session.connect()
        let receivedReady = await waitUntil { await output.contains("ready") }
        XCTAssertTrue(receivedReady)
        let receivedPTY = await waitUntil { server.recorder.contains("pty xterm-256color 80x24") }
        XCTAssertTrue(receivedPTY)
        let receivedShell = await waitUntil { server.recorder.contains("shell") }
        XCTAssertTrue(receivedShell)

        try await session.write(Data("hello\r".utf8))
        let receivedEcho = await waitUntil { await output.contains("hello") }
        XCTAssertTrue(receivedEcho)
        let receivedInput = await waitUntil { server.recorder.contains("data hello") }
        XCTAssertTrue(receivedInput)

        try await session.resize(columns: 120, rows: 40)
        let receivedResize = await waitUntil { server.recorder.contains("resize 120x40") }
        XCTAssertTrue(receivedResize)

        await session.close()
    }

    func testStartupCommandUsesExecRequest() async throws {
        let server = TestSSHServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let configuration = try SSHPTYConfiguration(
            host: "127.0.0.1",
            port: port,
            username: "tester",
            authentication: .password("secret"),
            expectedHostKey: String(openSSHPublicKey: server.hostKey.publicKey),
            startupCommand: "tmux new -A -s airdesk",
            connectTimeout: .seconds(5)
        )
        let session = SSHPTYSession(configuration: configuration)
        let consumer = Task {
            for try await _ in session.output {}
        }
        defer { consumer.cancel() }

        try await session.connect()
        let receivedExec = await waitUntil { server.recorder.contains("exec tmux new -A -s airdesk") }
        XCTAssertTrue(receivedExec)
        await session.close()
    }

    func testRejectsMismatchedHostKey() async throws {
        let server = TestSSHServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let wrongKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let configuration = try SSHPTYConfiguration(
            host: "127.0.0.1",
            port: port,
            username: "tester",
            authentication: .password("secret"),
            expectedHostKey: String(openSSHPublicKey: wrongKey.publicKey),
            connectTimeout: .seconds(5)
        )
        let session = SSHPTYSession(configuration: configuration)

        do {
            try await session.connect()
            XCTFail("Expected the host key check to fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        await session.close()
    }

    @MainActor
    func testControllerRelaysOutputAndResize() async throws {
        let server = TestSSHServer()
        let port = try await server.start()
        defer { Task { await server.stop() } }

        let configuration = try SSHPTYConfiguration(
            host: "127.0.0.1",
            port: port,
            username: "tester",
            authentication: .password("secret"),
            expectedHostKey: String(openSSHPublicKey: server.hostKey.publicKey),
            connectTimeout: .seconds(5)
        )
        let controller = RemoteTerminalController()
        let events = RemoteEventBox()
        controller.onEvent = { event in
            Task { await events.append(event) }
        }

        try await controller.start(configuration: configuration)
        XCTAssertTrue(controller.isRunning)
        let receivedReady = await waitUntil { await events.hasReady }
        XCTAssertTrue(receivedReady)

        controller.write(Data("hello\r".utf8))
        let receivedEcho = await waitUntil { await events.containsData("hello") }
        XCTAssertTrue(receivedEcho)

        controller.resize(columns: 120, rows: 40)
        let receivedResize = await waitUntil { server.recorder.contains("resize 120x40") }
        XCTAssertTrue(receivedResize)

        controller.stop()
        XCTAssertFalse(controller.isRunning)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}

private actor OutputBox {
    private var text = ""
    private var error: Error?

    func append(_ data: Data) {
        text += String(decoding: data, as: UTF8.self)
    }

    func finish(error: Error) {
        self.error = error
    }

    func contains(_ value: String) -> Bool {
        text.contains(value)
    }
}

private actor RemoteEventBox {
    private var events: [RemoteTerminalEvent] = []

    func append(_ event: RemoteTerminalEvent) {
        events.append(event)
    }

    var hasReady: Bool {
        events.contains {
            if case .ready = $0 { return true }
            return false
        }
    }

    func containsData(_ value: String) -> Bool {
        events.contains {
            guard case .data(let data) = $0 else { return false }
            return String(decoding: data, as: UTF8.self).contains(value)
        }
    }
}

private final class TestSSHServer {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
    let recorder = SSHTestRecorder()
    private var channel: Channel?

    func start() async throws -> Int {
        let hostKey = self.hostKey
        let recorder = self.recorder
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(
                ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR),
                value: 1
            )
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let ssh = NIOSSHHandler(
                        role: .server(
                            .init(
                                hostKeys: [hostKey],
                                userAuthDelegate: TestServerPasswordDelegate()
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { child, channelType in
                            guard case .session = channelType else {
                                return child.eventLoop.makeFailedFuture(TestSSHServerError.invalidChannel)
                            }
                            return child.eventLoop.makeCompletedFuture {
                                try child.pipeline.syncOperations.addHandler(
                                    TestServerPTYHandler(recorder: recorder)
                                )
                            }
                        }
                    )
                    try channel.pipeline.syncOperations.addHandler(ssh)
                }
            }

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        self.channel = channel
        guard let port = channel.localAddress?.port else {
            throw TestSSHServerError.missingPort
        }
        return port
    }

    func stop() async {
        try? await channel?.close().get()
        channel = nil
        try? await group.shutdownGracefully()
    }
}

private enum TestSSHServerError: Error {
    case invalidChannel
    case missingPort
}

private final class TestServerPasswordDelegate: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods = .password

    func requestReceived(
        request: NIOSSHUserAuthenticationRequest,
        responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>
    ) {
        guard
            request.username == "tester",
            case .password(let password) = request.request,
            password.password == "secret"
        else {
            responsePromise.succeed(.failure)
            return
        }
        responsePromise.succeed(.success)
    }
}

private final class TestServerPTYHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let recorder: SSHTestRecorder

    init(recorder: SSHTestRecorder) {
        self.recorder = recorder
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let event as SSHChannelRequestEvent.PseudoTerminalRequest:
            recorder.record(
                "pty \(event.term) \(event.terminalCharacterWidth)x\(event.terminalRowHeight)"
            )
            if event.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }

        case let event as SSHChannelRequestEvent.ShellRequest:
            recorder.record("shell")
            if event.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
            write("ready\r\n", context: context)

        case let event as SSHChannelRequestEvent.ExecRequest:
            recorder.record("exec \(event.command)")
            if event.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
            write("ready\r\n", context: context)

        case let event as SSHChannelRequestEvent.WindowChangeRequest:
            recorder.record(
                "resize \(event.terminalCharacterWidth)x\(event.terminalRowHeight)"
            )

        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        let text = String(decoding: buffer.readableBytesView, as: UTF8.self)
        recorder.record("data \(text.trimmingCharacters(in: .newlines))")
        write(text, context: context)
    }

    private func write(_ text: String, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: text.utf8.count)
        buffer.writeString(text)
        context.writeAndFlush(
            wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))),
            promise: nil
        )
    }
}

private final class SSHTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func record(_ item: String) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    func contains(_ item: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return items.contains { $0.contains(item) }
    }
}
