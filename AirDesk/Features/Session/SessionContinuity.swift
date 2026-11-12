import Foundation

enum SessionContinuityTone: Equatable {
    case neutral
    case positive
    case warning
    case critical
}

enum SessionContinuityHaptic: Equatable {
    case none
    case sessionReady
    case pathUpgraded
    case pathDegraded
    case pathChanged
    case recovery
    case failure
}

enum SessionContinuityTransport: String, Equatable {
    case direct
    case relay
    case other

    init(path: IrohFabricPath) {
        if path.isDirectIP {
            self = .direct
        } else if path.isRelay {
            self = .relay
        } else {
            self = .other
        }
    }

    var label: String {
        switch self {
        case .direct: return "Direct path"
        case .relay: return "Relay path"
        case .other: return "Path"
        }
    }
}

struct SessionContinuityPresentation: Equatable {
    var isVisible = false
    var title = ""
    var detail = ""
    var tone: SessionContinuityTone = .neutral
    var icon = "circle.dotted"
    var haptic: SessionContinuityHaptic = .none
    var latencyMilliseconds: Int?
    var pathLabel: String?

    static let hidden = SessionContinuityPresentation()
}

struct SessionContinuityModel {
    private var previousPhase: SessionPhase?
    private var previousRuntimeState: RuntimeState?
    private var previousTransport: SessionContinuityTransport?
    private var previousPathID: String?
    private var migrationDetail: String?

    mutating func reset() {
        previousPhase = nil
        previousRuntimeState = nil
        previousTransport = nil
        previousPathID = nil
        migrationDetail = nil
    }

    mutating func update(
        phase: SessionPhase,
        stage: ConnectionStage,
        runtimeState: RuntimeState,
        capabilities: RuntimeCapabilities,
        recoveryAttempts: Int,
        recoveryMaximumAttempts: Int,
        lastError: String?,
        selectedDeviceName: String?,
        paths: [IrohFabricPath],
        measuredLatencyMilliseconds: Double
    ) -> SessionContinuityPresentation {
        let selectedPath = paths.first { $0.isSelected } ?? paths.first
        let currentTransport = selectedPath.map(SessionContinuityTransport.init(path:))
        let currentPathID = selectedPath?.id
        let pathChanged = currentPathID != nil
            && previousPathID != nil
            && (currentPathID != previousPathID || currentTransport != previousTransport)

        if pathChanged, let currentTransport, let previousTransport {
            switch (previousTransport, currentTransport) {
            case (.relay, .direct):
                migrationDetail = "Upgraded from relay to direct"
            case (.direct, .relay):
                migrationDetail = "Failover to relay"
            default:
                migrationDetail = "Path changed to \(currentTransport.label.lowercased())"
            }
        } else if pathChanged, let currentTransport {
            migrationDetail = "Path changed to \(currentTransport.label.lowercased())"
        }

        let latency = latencyMilliseconds(path: selectedPath, measuredMilliseconds: measuredLatencyMilliseconds)
        let becameReady = phase == .ready && previousPhase != .ready
        let startedRecovery = runtimeState == .recovering && previousRuntimeState != .recovering
        let failed = phase == .failed && previousPhase != .failed
        let haptic: SessionContinuityHaptic
        if failed {
            haptic = .failure
        } else if startedRecovery {
            haptic = .recovery
        } else if becameReady {
            haptic = .sessionReady
        } else if pathChanged, phase == .ready, runtimeState != .recovering, currentTransport == .direct, previousTransport != .direct {
            haptic = .pathUpgraded
        } else if pathChanged, phase == .ready, runtimeState != .recovering, currentTransport == .relay, previousTransport != .relay {
            haptic = .pathDegraded
        } else if pathChanged, phase == .ready, runtimeState != .recovering {
            haptic = .pathChanged
        } else {
            haptic = .none
        }

        previousPhase = phase
        previousRuntimeState = runtimeState
        previousTransport = currentTransport
        previousPathID = currentPathID

        var presentation: SessionContinuityPresentation
        if phase == .idle {
            presentation = .hidden
        } else if runtimeState == .recovering, phase == .ready {
            presentation = SessionContinuityPresentation(
                isVisible: true,
                title: "Restoring workspace",
                detail: recoveryDetail(
                    attempts: recoveryAttempts,
                    maximum: recoveryMaximumAttempts,
                    path: currentTransport
                ),
                tone: .warning,
                icon: "arrow.triangle.2.circlepath",
                haptic: haptic,
                latencyMilliseconds: latency,
                pathLabel: currentTransport?.label
            )
        } else {
            switch phase {
            case .idle:
                presentation = .hidden
            case .connecting:
                presentation = SessionContinuityPresentation(
                    isVisible: true,
                    title: stage.title,
                    detail: stage.detail,
                    tone: .neutral,
                    icon: "antenna.radiowaves.left.and.right",
                    haptic: haptic,
                    latencyMilliseconds: latency,
                    pathLabel: currentTransport?.label
                )
            case .ready:
                presentation = readyPresentation(
                    transport: currentTransport,
                    capabilities: capabilities,
                    latency: latency,
                    haptic: haptic
                )
            case .failed:
                presentation = SessionContinuityPresentation(
                    isVisible: true,
                    title: recoveryAttempts > 0 ? "Recovery failed" : "Connection interrupted",
                    detail: failureDetail(
                        error: lastError,
                        deviceName: selectedDeviceName,
                        recoveryAttempts: recoveryAttempts,
                        path: currentTransport
                    ),
                    tone: .critical,
                    icon: "exclamationmark.triangle.fill",
                    haptic: haptic,
                    latencyMilliseconds: nil,
                    pathLabel: currentTransport?.label
                )
            }
        }

        return presentation
    }

    private func readyPresentation(
        transport: SessionContinuityTransport?,
        capabilities: RuntimeCapabilities,
        latency: Int?,
        haptic: SessionContinuityHaptic
    ) -> SessionContinuityPresentation {
        let title: String
        let tone: SessionContinuityTone
        switch transport {
        case .direct:
            title = "Direct path"
            tone = .positive
        case .relay:
            title = "Relay path"
            tone = .warning
        case .other, .none:
            title = "Session live"
            tone = .positive
        }

        var details: [String] = []
        if let migrationDetail {
            details.append(migrationDetail)
        }
        if !capabilities.labels.isEmpty {
            details.append(capabilitySummary(capabilities.labels))
        }
        return SessionContinuityPresentation(
            isVisible: true,
            title: title,
            detail: details.joined(separator: " · "),
            tone: tone,
            icon: transport == .relay ? "arrow.triangle.swap" : "checkmark.circle.fill",
            haptic: haptic,
            latencyMilliseconds: latency,
            pathLabel: transport?.label
        )
    }

    private func latencyMilliseconds(path: IrohFabricPath?, measuredMilliseconds: Double) -> Int? {
        if let path, path.rttMs > 0 {
            return Int(path.rttMs)
        }
        guard measuredMilliseconds > 0 else { return nil }
        return Int(measuredMilliseconds.rounded())
    }

    private func capabilitySummary(_ labels: [String]) -> String {
        let visible = labels.prefix(3)
        let hidden = labels.count - visible.count
        let summary = visible.joined(separator: " · ")
        return hidden > 0 ? "\(summary) +\(hidden)" : summary
    }

    private func recoveryDetail(
        attempts: Int,
        maximum: Int,
        path: SessionContinuityTransport?
    ) -> String {
        var detail = "Attempt \(max(attempts, 1)) of \(max(maximum, 1))"
        if let path {
            detail += " · \(path.label.lowercased())"
        }
        return detail
    }

    private func failureDetail(
        error: String?,
        deviceName: String?,
        recoveryAttempts: Int,
        path: SessionContinuityTransport?
    ) -> String {
        var parts: [String] = []
        if let error, !error.isEmpty {
            parts.append(error)
        } else if let deviceName, !deviceName.isEmpty {
            parts.append("\(deviceName) did not report readiness.")
        } else {
            parts.append("The desktop did not report readiness.")
        }
        if recoveryAttempts > 0 {
            parts.append("After \(recoveryAttempts) recovery attempt\(recoveryAttempts == 1 ? "" : "s")")
        }
        if let path {
            parts.append("Last path: \(path.label.lowercased())")
        }
        return parts.joined(separator: " · ")
    }
}
