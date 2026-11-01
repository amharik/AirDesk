import Crypto
import Foundation
import NIOSSH

enum RemoteTerminalProfileError: LocalizedError, Equatable {
    case disabled
    case missingHost
    case invalidPort
    case missingUsername
    case missingPassword
    case missingHostKey
    case invalidHostKey(String)
    case invalidPrivateKey

    var errorDescription: String? {
        switch self {
        case .disabled:
            return "The remote terminal is disabled."
        case .missingHost:
            return "Enter the SSH server host."
        case .invalidPort:
            return "The SSH port must be between 1 and 65535."
        case .missingUsername:
            return "Enter the SSH username."
        case .missingPassword:
            return "Enter the SSH password."
        case .missingHostKey:
            return "Paste the server's pinned OpenSSH host key."
        case .invalidHostKey(let message):
            return "The pinned host key is invalid: \(message)"
        case .invalidPrivateKey:
            return "The SSH private key is invalid."
        }
    }
}

struct RemoteTerminalProfile: Equatable, Sendable {
    var enabled: Bool
    var host: String
    var port: Int
    var username: String
    var hostKey: String
    var startupCommand: String
    var password: String

    var isConfigured: Bool {
        (try? makeConfiguration()) != nil
    }

    var destination: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return "SSH" }
        guard !trimmedUsername.isEmpty else { return trimmedHost }
        return "\(trimmedUsername)@\(trimmedHost)"
    }

    func makeConfiguration(
        size: SSHTerminalSize = .init(columns: 80, rows: 24),
        privateKeySeed: Data? = nil
    ) throws -> SSHPTYConfiguration {
        guard enabled else { throw RemoteTerminalProfileError.disabled }

        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw RemoteTerminalProfileError.missingHost }
        guard (1...65_535).contains(port) else { throw RemoteTerminalProfileError.invalidPort }

        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { throw RemoteTerminalProfileError.missingUsername }

        let authentication: SSHPTYAuthentication
        if let privateKeySeed {
            let key: Curve25519.Signing.PrivateKey
            do {
                key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeySeed)
            } catch {
                throw RemoteTerminalProfileError.invalidPrivateKey
            }
            authentication = .privateKey(NIOSSHPrivateKey(ed25519Key: key))
        } else {
            guard !password.isEmpty else { throw RemoteTerminalProfileError.missingPassword }
            authentication = .password(password)
        }

        let hostKey = hostKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostKey.isEmpty else { throw RemoteTerminalProfileError.missingHostKey }

        do {
            _ = try NIOSSHPublicKey(openSSHPublicKey: hostKey)
        } catch {
            throw RemoteTerminalProfileError.invalidHostKey(error.localizedDescription)
        }

        let command = startupCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return try SSHPTYConfiguration(
            host: host,
            port: port,
            username: username,
            authentication: authentication,
            expectedHostKey: hostKey,
            size: size,
            startupCommand: command.isEmpty ? nil : command,
            connectTimeout: .seconds(15)
        )
    }
}
