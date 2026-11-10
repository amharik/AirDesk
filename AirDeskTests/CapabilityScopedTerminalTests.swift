import Crypto
import NIOSSH
import XCTest
@testable import AirDesk

@MainActor
final class CapabilityScopedTerminalTests: XCTestCase {
    func testConnectRequiresMatchingLeaseAndForwardsOperations() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let lease = makeLease()
        try leases.grant(lease)

        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )
        var events: [RemoteTerminalEvent] = []
        terminal.onEvent = { events.append($0) }

        try await terminal.start(
            configuration: try configuration(),
            context: makeContext(leaseId: lease.leaseId)
        )

        XCTAssertTrue(terminal.isRunning)
        XCTAssertEqual(transport.startCount, 1)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .allowed)
        XCTAssertEqual(terminal.auditEvents.last?.operation, .connect)

        terminal.write(Data("ls\r".utf8))
        terminal.resize(columns: 120, rows: 40)
        XCTAssertEqual(transport.writeCount, 1)
        XCTAssertEqual(transport.resizeCount, 1)

        terminal.stop()
        XCTAssertFalse(terminal.isRunning)
        XCTAssertEqual(transport.stopCount, 1)
    }

    func testDeniedLeaseDoesNotStartTransportAndIsAudited() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )

        do {
            try await terminal.start(
                configuration: try configuration(),
                context: makeContext(leaseId: "missing-lease")
            )
            XCTFail("Expected the terminal lease to be denied")
        } catch {
            XCTAssertEqual(error as? CapabilityTerminalError, .leaseDenied)
        }

        XCTAssertEqual(transport.startCount, 0)
        XCTAssertFalse(terminal.isRunning)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .denied)
        XCTAssertEqual(terminal.auditEvents.last?.leaseId, "missing-lease")
    }

    func testRevokedLeaseIsTypedAndAudited() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let lease = makeLease()
        try leases.grant(lease)
        leases.revoke(leaseId: lease.leaseId, reason: "test revocation")

        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )

        do {
            try await terminal.start(
                configuration: try configuration(),
                context: makeContext(leaseId: lease.leaseId)
            )
            XCTFail("Expected the revoked lease to fail")
        } catch {
            XCTAssertEqual(error as? CapabilityTerminalError, .leaseRevoked)
        }

        XCTAssertEqual(transport.startCount, 0)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .revoked)
        XCTAssertEqual(terminal.auditEvents.last?.auditId, lease.auditId)
    }

    func testExpiredLeaseIsTypedAndAudited() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let lease = makeLease(expiresAt: now.value)
        try leases.grant(lease)

        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )

        do {
            try await terminal.start(
                configuration: try configuration(),
                context: makeContext(leaseId: lease.leaseId)
            )
            XCTFail("Expected the expired lease to fail")
        } catch {
            XCTAssertEqual(error as? CapabilityTerminalError, .leaseExpired)
        }

        XCTAssertEqual(transport.startCount, 0)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .expired)
    }

    func testBusyLeaseIsTypedAndAudited() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let lease = makeLease()
        try leases.grant(lease)

        let firstTransport = FakeRemoteTerminal()
        let first = CapabilityScopedTerminal(
            controller: firstTransport,
            leases: leases,
            now: { now.value }
        )
        let secondTransport = FakeRemoteTerminal()
        let second = CapabilityScopedTerminal(
            controller: secondTransport,
            leases: leases,
            now: { now.value }
        )

        try await first.start(
            configuration: try configuration(),
            context: makeContext(leaseId: lease.leaseId)
        )

        do {
            try await second.start(
                configuration: try configuration(),
                context: makeContext(leaseId: lease.leaseId)
            )
            XCTFail("Expected the active lease to be busy")
        } catch {
            XCTAssertEqual(error as? CapabilityTerminalError, .leaseBusy(lease.leaseId))
        }

        XCTAssertEqual(firstTransport.startCount, 1)
        XCTAssertEqual(secondTransport.startCount, 0)
        XCTAssertTrue(first.isRunning)
        XCTAssertEqual(second.auditEvents.last?.decision, .busy)

        first.stop()
        try await second.start(
            configuration: try configuration(),
            context: makeContext(leaseId: lease.leaseId)
        )
        XCTAssertTrue(second.isRunning)
        second.stop()
    }

    func testTerminalProfileCannotBypassMissingLease() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )

        do {
            try await terminal.start(
                configuration: try configuration(),
                context: makeContext(leaseId: nil)
            )
            XCTFail("Expected a missing lease to fail")
        } catch {
            XCTAssertEqual(error as? CapabilityTerminalError, .leaseDenied)
        }

        XCTAssertEqual(transport.startCount, 0)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .denied)
    }

    func testWriteAndResizeRequireLeaseOperations() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let lease = makeLease(operations: [.connect])
        try leases.grant(lease)

        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )
        var events: [RemoteTerminalEvent] = []
        terminal.onEvent = { events.append($0) }

        try await terminal.start(
            configuration: try configuration(),
            context: makeContext(leaseId: lease.leaseId)
        )
        terminal.write(Data("pwd\r".utf8))

        XCTAssertEqual(transport.writeCount, 0)
        XCTAssertEqual(transport.stopCount, 1)
        XCTAssertFalse(terminal.isRunning)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .denied)
        XCTAssertEqual(terminal.auditEvents.last?.operation, .write)
        guard let last = events.last, case .exit = last else {
            return XCTFail("Expected an exit event")
        }
    }

    func testRevocationDuringSessionStopsTransport() async throws {
        let now = MutableNow()
        let leases = CapabilityLeaseRegistry(now: { now.value })
        let lease = makeLease()
        try leases.grant(lease)

        let transport = FakeRemoteTerminal()
        let terminal = CapabilityScopedTerminal(
            controller: transport,
            leases: leases,
            now: { now.value }
        )
        var events: [RemoteTerminalEvent] = []
        terminal.onEvent = { events.append($0) }

        try await terminal.start(
            configuration: try configuration(),
            context: makeContext(leaseId: lease.leaseId)
        )
        leases.revoke(leaseId: lease.leaseId, reason: "controller revoked")
        terminal.resize(columns: 100, rows: 30)

        XCTAssertEqual(transport.resizeCount, 0)
        XCTAssertEqual(transport.stopCount, 1)
        XCTAssertFalse(terminal.isRunning)
        XCTAssertEqual(terminal.auditEvents.last?.decision, .revoked)
        XCTAssertEqual(terminal.auditEvents.last?.operation, .resize)
        guard let last = events.last, case .exit = last else {
            return XCTFail("Expected an exit event")
        }
    }

    private func makeLease(
        expiresAt: Date? = nil,
        operations: Set<CapabilityTerminalOperation> = Set(CapabilityTerminalOperation.allCases)
    ) -> CapabilityLease {
        CapabilityLease(
            leaseId: "lease-1",
            capUri: CapabilityScopedTerminal.capabilityURI,
            workspaceId: "workspace.local",
            applicationId: "wanixDesktop",
            requesterDeviceId: "device.test",
            sessionId: "session-1",
            issuedAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: expiresAt,
            operations: operations,
            auditId: "audit-1"
        )
    }

    private func makeContext(leaseId: String?) -> CapabilityTerminalContext {
        CapabilityTerminalContext(
            workspaceId: "workspace.local",
            applicationId: "wanixDesktop",
            requesterDeviceId: "device.test",
            sessionId: "session-1",
            leaseId: leaseId
        )
    }

    private func configuration() throws -> SSHPTYConfiguration {
        let key = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        return try SSHPTYConfiguration(
            host: "127.0.0.1",
            port: 22,
            username: "tester",
            authentication: .password("secret"),
            expectedHostKey: String(openSSHPublicKey: key.publicKey),
            connectTimeout: .seconds(1)
        )
    }
}

private final class MutableNow {
    var value = Date(timeIntervalSince1970: 2_000)
}

@MainActor
private final class FakeRemoteTerminal: RemoteTerminalDriving {
    var onEvent: ((RemoteTerminalEvent) -> Void)?
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var writeCount = 0
    private(set) var resizeCount = 0
    private(set) var stopCount = 0

    func start(configuration: SSHPTYConfiguration) async throws {
        _ = configuration
        startCount += 1
        isRunning = true
        onEvent?(.ready)
    }

    func write(_ data: Data) {
        _ = data
        writeCount += 1
    }

    func resize(columns: Int, rows: Int) {
        _ = columns
        _ = rows
        resizeCount += 1
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}
