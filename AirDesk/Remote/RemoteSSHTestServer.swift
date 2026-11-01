#if DEBUG
import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

final class RemoteSSHTestServer: @unchecked Sendable {
    let hostKey: NIOSSHPrivateKey
    let port: Int

    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel

    var hostKeyString: String {
        String(openSSHPublicKey: hostKey.publicKey)
    }

    static func start(dropFirstSession: Bool) async throws -> RemoteSSHTestServer {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let hostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let hostKeyBox = FixtureBox(hostKey)
        let dropState = FixtureDropState(dropFirstSession: dropFirstSession)

        do {
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
                                    hostKeys: [hostKeyBox.value],
                                    userAuthDelegate: FixturePasswordDelegate()
                                )
                            ),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: { child, channelType in
                                guard case .session = channelType else {
                                    return child.eventLoop.makeFailedFuture(FixtureError.invalidChannel)
                                }
                                return child.eventLoop.makeCompletedFuture {
                                    try child.pipeline.syncOperations.addHandler(
                                        FixturePTYHandler(dropState: dropState)
                                    )
                                }
                            }
                        )
                        try channel.pipeline.syncOperations.addHandler(ssh)
                    }
                }

            let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            guard let port = channel.localAddress?.port else {
                throw FixtureError.missingPort
            }
            return RemoteSSHTestServer(
                hostKey: hostKey,
                port: port,
                group: group,
                channel: channel
            )
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    private init(
        hostKey: NIOSSHPrivateKey,
        port: Int,
        group: MultiThreadedEventLoopGroup,
        channel: Channel
    ) {
        self.hostKey = hostKey
        self.port = port
        self.group = group
        self.channel = channel
    }

    func stop() async {
        try? await channel.close().get()
        try? await group.shutdownGracefully()
    }
}

private struct FixtureBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private enum FixtureError: Error {
    case invalidChannel
    case missingPort
}

private final class FixturePasswordDelegate: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
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

private final class FixtureDropState: @unchecked Sendable {
    private let lock = NSLock()
    private let shouldDrop: Bool
    private var dropped = false

    init(dropFirstSession: Bool) {
        shouldDrop = dropFirstSession
    }

    func claimDrop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard shouldDrop, !dropped else { return false }
        dropped = true
        return true
    }
}

private final class FixturePTYHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private let dropState: FixtureDropState

    init(dropState: FixtureDropState) {
        self.dropState = dropState
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let event as SSHChannelRequestEvent.PseudoTerminalRequest:
            if event.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }

        case let event as SSHChannelRequestEvent.ShellRequest:
            if event.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
            write("ready\r\n", context: context)

        case let event as SSHChannelRequestEvent.ExecRequest:
            if event.wantReply {
                context.channel.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
            write("ready\r\n", context: context)

        case is SSHChannelRequestEvent.WindowChangeRequest:
            break

        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        let text = String(decoding: buffer.readableBytesView, as: UTF8.self)
        write(text, context: context)
        if dropState.claimDrop() {
            context.close(promise: nil)
        }
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
#endif
