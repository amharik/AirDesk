import XCTest
@testable import AirDesk

final class WorkspaceStatusCopyTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testCreatedAndRestoredCopy() {
        let created = WorkspaceStatusCopy.restore(report(outcome: .created))
        XCTAssertEqual(created?.title, "Workspace ready")
        XCTAssertEqual(created?.severity, .info)

        let restored = WorkspaceStatusCopy.restore(report(outcome: .restored))
        XCTAssertNil(restored)

        let reconnected = WorkspaceStatusCopy.restore(report(
            outcome: .restored,
            instances: [.reconnected(instanceId: "i")]
        ))
        XCTAssertEqual(reconnected?.detail, "Reconnected 1 running application.")
    }

    func testRecoveryAndLostApplicationsAreWarnings() {
        let recovered = WorkspaceStatusCopy.restore(report(
            outcome: .recovered,
            warning: .corruptManifest
        ))
        XCTAssertEqual(recovered?.title, "Workspace recovered")
        XCTAssertEqual(recovered?.severity, .warning)

        let lost = WorkspaceStatusCopy.restore(report(
            outcome: .restored,
            instances: [.lost(instanceId: "i", reason: "offline")]
        ))
        XCTAssertEqual(lost?.title, "Some applications need attention")
        XCTAssertEqual(lost?.severity, .warning)
    }

    func testHostDegradedAndHandoffCopy() {
        let degraded = WorkspaceStatusCopy.host(.degraded(reason: "offline"))
        XCTAssertEqual(degraded?.title, "Workspace host degraded")
        XCTAssertTrue(degraded?.detail.contains("Structural changes are unavailable") == true)

        let handedOff = WorkspaceStatusCopy.host(.handedOff)
        XCTAssertEqual(handedOff?.title, "Workspace authority moved")

        let pending = WorkspaceStatusCopy.host(.handoffPending(targetDeviceId: "device.next"))
        XCTAssertEqual(pending?.title, "Workspace handoff in progress")
        XCTAssertTrue(pending?.detail.contains("device.next") == true)
        XCTAssertNil(WorkspaceStatusCopy.host(.active))
    }

    private func report(
        outcome: WorkspaceRestoreOutcome,
        warning: WorkspaceStoreError? = nil,
        instances: [WorkspaceInstanceRestoreState] = []
    ) -> WorkspaceRestoreReport {
        WorkspaceRestoreReport(
            outcome: outcome,
            workspaceId: "workspace.test",
            workspaceName: "Test",
            createdAt: createdAt,
            recoveryWarning: warning,
            instances: instances
        )
    }
}
