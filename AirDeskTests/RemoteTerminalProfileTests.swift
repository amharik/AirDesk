import Crypto
import NIOSSH
import XCTest
@testable import AirDesk

final class RemoteTerminalProfileTests: XCTestCase {
    private func hostKey() -> String {
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        return String(openSSHPublicKey: key.publicKey)
    }

    private func profile(hostKey: String) -> RemoteTerminalProfile {
        RemoteTerminalProfile(
            enabled: true,
            host: " shell.example.com ",
            port: 2222,
            username: " desktop ",
            hostKey: hostKey,
            startupCommand: " tmux new -A -s airdesk ",
            password: "secret"
        )
    }

    func testBuildsConfigurationFromTrimmedProfile() throws {
        let hostKey = hostKey()
        let configuration = try profile(hostKey: hostKey).makeConfiguration(
            size: SSHTerminalSize(columns: 132, rows: 43)
        )

        XCTAssertEqual(configuration.host, "shell.example.com")
        XCTAssertEqual(configuration.port, 2222)
        XCTAssertEqual(configuration.username, "desktop")
        XCTAssertEqual(configuration.startupCommand, "tmux new -A -s airdesk")
        XCTAssertEqual(configuration.size.columns, 132)
        XCTAssertEqual(configuration.size.rows, 43)
        guard case .password(let password) = configuration.authentication else {
            return XCTFail("Expected password authentication")
        }
        XCTAssertEqual(password, "secret")
    }

    func testBlankStartupCommandBecomesNil() throws {
        var candidate = profile(hostKey: hostKey())
        candidate.startupCommand = "   "
        let configuration = try candidate.makeConfiguration()
        XCTAssertNil(configuration.startupCommand)
    }

    func testRejectsDisabledAndIncompleteProfiles() {
        var candidate = profile(hostKey: hostKey())
        candidate.enabled = false
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            XCTAssertEqual(error as? RemoteTerminalProfileError, .disabled)
        }

        candidate = profile(hostKey: hostKey())
        candidate.host = " "
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            XCTAssertEqual(error as? RemoteTerminalProfileError, .missingHost)
        }

        candidate = profile(hostKey: hostKey())
        candidate.port = 0
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            XCTAssertEqual(error as? RemoteTerminalProfileError, .invalidPort)
        }

        candidate = profile(hostKey: hostKey())
        candidate.username = ""
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            XCTAssertEqual(error as? RemoteTerminalProfileError, .missingUsername)
        }

        candidate = profile(hostKey: hostKey())
        candidate.password = ""
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            XCTAssertEqual(error as? RemoteTerminalProfileError, .missingPassword)
        }

        candidate = profile(hostKey: hostKey())
        candidate.hostKey = ""
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            XCTAssertEqual(error as? RemoteTerminalProfileError, .missingHostKey)
        }
    }

    func testRejectsInvalidPinnedHostKey() {
        var candidate = profile(hostKey: hostKey())
        candidate.hostKey = "ssh-ed25519 not-a-key"
        XCTAssertThrowsError(try candidate.makeConfiguration()) { error in
            guard case .invalidHostKey = error as? RemoteTerminalProfileError else {
                return XCTFail("Expected invalidHostKey, got \(error)")
            }
        }
    }

    func testDestinationFormatsHostAndUser() {
        var candidate = profile(hostKey: hostKey())
        XCTAssertEqual(candidate.destination, "desktop@shell.example.com")
        candidate.username = ""
        XCTAssertEqual(candidate.destination, "shell.example.com")
        candidate.host = ""
        XCTAssertEqual(candidate.destination, "SSH")
    }
}
