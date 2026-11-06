import Foundation

struct WorkspaceStatusPresentation: Equatable, Sendable {
    enum Severity: String, Equatable, Sendable {
        case info
        case warning
        case error
    }

    var title: String
    var detail: String
    var severity: Severity
}

enum WorkspaceStatusCopy {
    static func restore(_ report: WorkspaceRestoreReport) -> WorkspaceStatusPresentation? {
        if let warning = report.recoveryWarning {
            return WorkspaceStatusPresentation(
                title: "Workspace recovered",
                detail: "AirDesk restored the last good workspace after a storage problem: \(warning.localizedDescription)",
                severity: .warning
            )
        }

        let lost = report.instances.filter {
            if case .lost = $0 { return true }
            return false
        }
        if !lost.isEmpty {
            return WorkspaceStatusPresentation(
                title: "Some applications need attention",
                detail: "\(lost.count) application\(lost.count == 1 ? "" : "s") could not be restored. Open Session details to retry or stop them.",
                severity: .warning
            )
        }

        switch report.outcome {
        case .created:
            return WorkspaceStatusPresentation(
                title: "Workspace ready",
                detail: "Created \(report.workspaceName) on this device.",
                severity: .info
            )
        case .restored:
            let reconnected = report.instances.filter {
                if case .reconnected = $0 { return true }
                return false
            }.count
            if reconnected > 0 {
                return WorkspaceStatusPresentation(
                    title: "Workspace restored",
                    detail: "Reconnected \(reconnected) running application\(reconnected == 1 ? "" : "s").",
                    severity: .info
                )
            }
            return nil
        case .recovered:
            return WorkspaceStatusPresentation(
                title: "Workspace recovered",
                detail: "The workspace was restored from its recovery journal.",
                severity: .warning
            )
        }
    }

    static func host(_ state: WorkspaceHostState) -> WorkspaceStatusPresentation? {
        switch state {
        case .active:
            return nil
        case .degraded(let reason):
            return WorkspaceStatusPresentation(
                title: "Workspace host degraded",
                detail: "Running applications and input can continue. Structural changes are unavailable: \(reason)",
                severity: .warning
            )
        case .handoffPending(let targetDeviceId):
            return WorkspaceStatusPresentation(
                title: "Workspace handoff in progress",
                detail: "Structural changes are paused while workspace authority moves to \(targetDeviceId).",
                severity: .info
            )
        case .handedOff:
            return WorkspaceStatusPresentation(
                title: "Workspace authority moved",
                detail: "This device is no longer the workspace host. Open the workspace from the active host to make structural changes.",
                severity: .info
            )
        }
    }
}

extension WorkspaceRestoreReport {
    var presentation: WorkspaceStatusPresentation? {
        WorkspaceStatusCopy.restore(self)
    }
}

extension WorkspaceHostState {
    var presentation: WorkspaceStatusPresentation? {
        WorkspaceStatusCopy.host(self)
    }
}
