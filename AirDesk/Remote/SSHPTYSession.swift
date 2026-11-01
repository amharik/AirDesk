import Foundation
import NIOCore
import NIOPosix
import NIOSSH

struct SSHTerminalSize: Sendable, Equatable {
    var columns: Int
    var rows: Int
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
}

enum SSHPTYAuthentication: Sendable {
    case password(String)
    case privateKey(NIOSSHPrivateKey)
}

struct SSHPTYConfiguration: Sendable {
    var host: String
    var port: Int
    var username: String
    var authentication: SSHPTYAuthentication
    var expectedHostKey: NIOSSHPublicKey
    var terminalType: String
    var size: SSHTerminalSize
    var startupCommand: String?
    var connectTimeout: TimeAmount

    init(
        host: String,
        port: Int = 22,
        username: String,
        authentication: SSHPTYAuthentication,
        expectedHostKey: String,
        terminalType: String = "xterm-256color",
        size: SSHTerminalSize = .init(columns: 80, rows: 24),
        startupCommand: String? = nil,
        connectTimeout: TimeAmount = .seconds(15)
    ) throws {
        self.host = host
        self.port = port
        self.username = username
        self.authentication = authentication
        self.expectedHostKey = try NIOSSHPublicKey(openSSHPublicKey: expectedHostKey)
        self.terminalType = terminalType
        self.size = size
        self.startupCommand = startupCommand
        self.connectTimeout = connectTimeout
    }
}

enum SSHPTYError: LocalizedError {
    case invalidChannelType
    case hostKeyMismatch
    case authenticationUnavailable
    case terminalRequestRejected
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .invalidChannelType:
            return "The SSH server opened an unsupported channel type."
        case .hostKeyMismatch:
            return "The SSH host key does not match the pinned key."
        case .authenticationUnavailable:
            return "The SSH server did not accept the configured authentication method."
        case .terminalRequestRejected:
            return "The SSH server rejected the terminal request."
        case .connectionClosed:
            return "The SSH session is closed."
        }
    }
}

actor SSHPTYSession {
    nonisolated let output: AsyncThrowingStream<Data, Error>

    private let configuration: SSHPTYConfiguration
    private let group: MultiThreadedEventLoopGroup
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var parentChannel: Channel?
    private var sessionChannel: Channel?
    private var connected = false
    private var closed = false

    init(configuration: SSHPTYConfiguration) {
        self.configuration = configuration
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        self.output = stream
        self.continuation = continuation
    }

    func connect() async throws {
        guard !connected else { return }
        guard !closed else { throw SSHPTYError.connectionClosed }

        do {
            let authentication = UnsafeSendableBox(makeAuthenticationDelegate())
            let hostKey = PinnedHostKeyDelegate(expected: configuration.expectedHostKey)
            let bootstrap = ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let ssh = NIOSSHHandler(
                            role: .client(
                                .init(
                                    userAuthDelegate: authentication.value,
                                    serverAuthDelegate: hostKey
                                )
                            ),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                        try channel.pipeline.syncOperations.addHandler(ssh)
                        try channel.pipeline.syncOperations.addHandler(SSHConnectionErrorHandler())
                    }
                }
                .channelOption(
                    ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY),
                    value: 1
                )
                .connectTimeout(configuration.connectTimeout)

            let parent = try await bootstrap.connect(
                host: configuration.host,
                port: configuration.port
            ).get()
            parentChannel = parent

            sessionChannel = try await createSessionChannel(parent: parent)
            connected = true
        } catch {
            continuation.finish(throwing: error)
            await close()
            throw error
        }
    }

    func write(_ data: Data) async throws {
        guard let channel = sessionChannel, channel.isActive else {
            throw SSHPTYError.connectionClosed
        }
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(buffer).get()
    }

    func resize(columns: Int, rows: Int) async throws {
        guard let channel = sessionChannel, channel.isActive else {
            throw SSHPTYError.connectionClosed
        }
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: columns,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        try await channel.triggerUserOutboundEvent(request).get()
    }

    func close() async {
        guard !closed else { return }
        closed = true
        connected = false
        continuation.finish()

        if let channel = sessionChannel {
            try? await channel.close().get()
        }
        if let channel = parentChannel {
            try? await channel.close().get()
        }
        sessionChannel = nil
        parentChannel = nil
        try? await group.shutdownGracefully()
    }

    private func makeAuthenticationDelegate() -> NIOSSHClientUserAuthenticationDelegate {
        switch configuration.authentication {
        case .password(let password):
            return PasswordAuthenticationDelegate(
                username: configuration.username,
                password: password
            )
        case .privateKey(let key):
            return PrivateKeyAuthenticationDelegate(
                username: configuration.username,
                privateKey: key
            )
        }
    }

    private func createSessionChannel(parent: Channel) async throws -> Channel {
        let promise = parent.eventLoop.makePromise(of: Channel.self)
        let continuation = self.continuation
        let size = configuration.size
        let terminalType = configuration.terminalType
        let startupCommand = configuration.startupCommand

        parent.eventLoop.execute {
            do {
                let ssh = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                ssh.createChannel(promise, channelType: .session) { channel, channelType in
                    guard channelType == .session else {
                        return channel.eventLoop.makeFailedFuture(SSHPTYError.invalidChannelType)
                    }
                    return channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMap {
                        channel.eventLoop.makeCompletedFuture {
                            let handler = SSHPTYChannelHandler(
                                size: size,
                                terminalType: terminalType,
                                startupCommand: startupCommand,
                                onData: { continuation.yield($0) },
                                onExit: { _ in continuation.finish() },
                                onError: { continuation.finish(throwing: $0) }
                            )
                            try channel.pipeline.syncOperations.addHandler(handler)
                        }
                    }
                }
            } catch {
                promise.fail(error)
            }
        }

        return try await promise.futureResult.get()
    }
}

private struct UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class PasswordAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private var password: String?

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard let password, availableMethods.contains(.password) else {
            nextChallengePromise.succeed(nil)
            return
        }
        self.password = nil
        nextChallengePromise.succeed(
            .init(
                username: username,
                serviceName: "ssh-connection",
                offer: .password(.init(password: password))
            )
        )
    }
}

private final class PrivateKeyAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private var privateKey: NIOSSHPrivateKey?

    init(username: String, privateKey: NIOSSHPrivateKey) {
        self.username = username
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard let privateKey, availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        self.privateKey = nil
        nextChallengePromise.succeed(
            .init(
                username: username,
                serviceName: "ssh-connection",
                offer: .privateKey(.init(privateKey: privateKey))
            )
        )
    }
}

private final class SSHConnectionErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

private final class PinnedHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let expected: NIOSSHPublicKey

    init(expected: NIOSSHPublicKey) {
        self.expected = expected
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        if hostKey == expected {
            validationCompletePromise.succeed(())
        } else {
            validationCompletePromise.fail(SSHPTYError.hostKeyMismatch)
        }
    }
}

private final class SSHPTYChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let size: SSHTerminalSize
    private let terminalType: String
    private let startupCommand: String?
    private let onData: (Data) -> Void
    private let onExit: (Int?) -> Void
    private let onError: (Error) -> Void

    init(
        size: SSHTerminalSize,
        terminalType: String,
        startupCommand: String?,
        onData: @escaping (Data) -> Void,
        onExit: @escaping (Int?) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.size = size
        self.terminalType = terminalType
        self.startupCommand = startupCommand
        self.onData = onData
        self.onExit = onExit
        self.onError = onError
    }

    func channelActive(context: ChannelHandlerContext) {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: terminalType,
            terminalCharacterWidth: size.columns,
            terminalRowHeight: size.rows,
            terminalPixelWidth: size.pixelWidth,
            terminalPixelHeight: size.pixelHeight,
            terminalModes: .init([:])
        )

        context.triggerUserOutboundEvent(ptyRequest).flatMap { [startupCommand] in
            let request: Any
            if let startupCommand {
                request = SSHChannelRequestEvent.ExecRequest(command: startupCommand, wantReply: true)
            } else {
                request = SSHChannelRequestEvent.ShellRequest(wantReply: true)
            }
            return context.triggerUserOutboundEvent(request)
        }.whenFailure { [onError] error in
            onError(error)
            context.close(promise: nil)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        if channelData.type == .channel || channelData.type == .stdErr {
            onData(Data(buffer.readableBytesView))
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(
            wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))),
            promise: promise
        )
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let exit = event as? SSHChannelRequestEvent.ExitStatus {
            onExit(exit.exitStatus)
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onError(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onExit(nil)
        context.fireChannelInactive()
    }
}
