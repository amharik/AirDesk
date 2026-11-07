import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var diagnostics: PerformanceMetrics
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                capabilitiesSection
                sessionSection
                fabricSection
                browserEndpointSection
                performanceSection
                runtimeSection
                transitionsSection
                privacySection
            }
            .scrollContentBackground(.hidden)
            .background(AirDeskBackground(intensity: 0.4))
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        copyReport()
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(copied ? ADTheme.accent : Color.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var identitySection: some View {
        Section {
            if let identity = environment.identity {
                infoRow("Device ID", identity.deviceId)
                infoRow("Algorithm", identity.algorithm.displayName)
                infoRow("Public key", identity.spkiHex)
                infoRow("Paired devices", "\(environment.deviceRegistry?.pairedCount ?? 0)")
                infoRow("Trusted", "\(environment.deviceRegistry?.trustedCount ?? 0)")
                infoRow("Revoked", "\(environment.deviceRegistry?.revokedCount ?? 0)")
            } else {
                infoRow("Device identity", "Unavailable")
                if let error = environment.identityError {
                    infoRow("Identity error", error)
                }
            }
            if let error = environment.deviceRegistryError {
                infoRow("Registry error", error)
            }
        } header: {
            sectionHeader("Device identity")
        } footer: {
            Text("The device ID is the SHA-256 fingerprint of the canonical DER SPKI. The browser has AD-PAIR-1 and an RFC 9383 SPAKE2+ P-256 primitive, but interactive SPAKE2+ pairing and transport binding are not implemented.")
        }
        .listRowBackground(rowBackground)
    }

    private var capabilitiesSection: some View {
        CapabilityCatalogSection(catalog: environment.capabilityCatalog)
            .listRowBackground(rowBackground)
            .onAppear { environment.capabilityCatalog.reload() }
    }

    private var sessionSection: some View {
        Section {
            infoRow("Phase", session.phase.rawValue)
            infoRow("Mode", session.effectiveMode.title)
            infoRow("Device", session.selectedDevice?.name ?? "None")
            infoRow("Runtime", "\(session.runtimeName) · \(session.runtimeState.title)")
            infoRow("Session", session.sessionId.isEmpty ? "Inactive" : session.sessionId)
            infoRow("Recovery", session.recoveryAttempts == 0 ? "None" : "\(session.recoveryAttempts) / \(session.recoveryMaximumAttempts)")
            infoRow("Display output", displayOutput)
            infoRow("External display", environment.display.isExternalDisplayConnected ? "Connected" : "Not connected")
            infoRow("Input route", inputRoute)
        } header: {
            sectionHeader("Session")
        }
        .listRowBackground(rowBackground)
    }

    private var inputRoute: String {
        if environment.settings.fabricInputForwardingEnabled, environment.fabric.isConnected {
            return "Iroh fabric"
        }
        return session.effectiveMode == .cast ? "Cast channel" : "Local surface bridge"
    }

    private var fabricSection: some View {
        Section {
            infoRow("Endpoint", environment.fabric.state.title)
            infoRow("Peer", environment.fabric.remoteEndpointID ?? "None")
            if let path = environment.fabric.selectedPath {
                infoRow("Path", path.isRelay ? "Relay" : (path.isDirectIP ? "Direct IP" : "Direct"))
                infoRow("RTT", "\(path.rttMs) ms")
                infoRow("Address", path.remoteAddress)
            } else {
                infoRow("Path", "None")
            }
            infoRow("Relay policy", environment.fabric.relayPolicyLabel)
            infoRow("Remote input", remoteInputState)
            if let error = environment.fabric.lastError {
                infoRow("Last error", error)
            }
        } header: {
            sectionHeader("Iroh fabric")
        } footer: {
            Text("Path and RTT values come from the live endpoint. A relayed path is never reported as direct.")
        }
        .listRowBackground(rowBackground)
    }

    private var browserEndpointSection: some View {
        BrowserEndpointDiagnosticsSection(service: environment.browserEndpoint)
    }

    private var remoteInputState: String {
        guard session.fabricControllerID != nil else { return "No peer" }
        return session.fabricControllerHasLease ? "Lease granted" : "Lease not granted"
    }

    private var displayOutput: String {
        if environment.display.isMirroring { return "AirPlay mirroring" }
        if environment.display.hasExternalDisplay { return "Extended desktop" }
        return "On-device"
    }

    private var performanceSection: some View {
        Section {
            HStack(spacing: 8) {
                metricTile("Events", value: "\(diagnostics.eventsSent)", tint: ADTheme.accent)
                metricTile("Per second", value: "\(diagnostics.eventsPerSecond)", tint: ADTheme.violet)
            }
            HStack(spacing: 8) {
                metricTile("P50 ack", value: String(format: "%.1f ms", diagnostics.p50Latency), tint: ADTheme.accent)
                metricTile("P95 ack", value: String(format: "%.1f ms", diagnostics.p95Latency), tint: ADTheme.amber)
            }
            infoRow("Last acknowledgement", String(format: "%.1f ms", diagnostics.lastLatency))
            infoRow("Protocol", "Input v1 · bridge v1")
        } header: {
            sectionHeader("Performance")
        } footer: {
            Text("Acknowledgement latency is the round trip from input dispatch to the desktop bridge acknowledgement. It includes local processing and transport.")
        }
        .listRowBackground(rowBackground)
    }

    private var runtimeSection: some View {
        Section {
            ForEach(session.capabilities.labels, id: \.self) { capability in
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ADTheme.accent)
                    Text(capability)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Spacer()
                }
            }
            infoRow("Cast transport", environment.cast.isDemo ? "Simulated / demo" : "Live receiver")
            infoRow("Receiver configured", CastConfiguration.hasRegisteredReceiver ? "Yes" : "No")
            infoRow("Cast state", environment.cast.state.rawValue)
        } header: {
            sectionHeader("Runtime capabilities")
        }
        .listRowBackground(rowBackground)
    }

    private var transitionsSection: some View {
        Section {
            if diagnostics.transitions.isEmpty {
                Text("No transitions recorded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.textTertiary)
            } else {
                ForEach(diagnostics.transitions.suffix(18).reversed()) { transition in
                    HStack(spacing: 10) {
                        Text(transition.timestamp, style: .time)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ADTheme.textTertiary)
                            .frame(width: 64, alignment: .leading)
                        Text(transition.name)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Spacer()
                    }
                }
            }
        } header: {
            sectionHeader("State transitions")
        }
        .listRowBackground(rowBackground)
    }

    private var privacySection: some View {
        Section {
            Text("Diagnostics record event counts, latency, state names, and session metadata. Keystrokes, typed text, passwords, and clipboard contents are never recorded.")
                .font(.system(size: 12))
                .foregroundStyle(ADTheme.textSecondary)
                .lineSpacing(2)
        } header: {
            sectionHeader("Privacy")
        }
        .listRowBackground(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.04))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(ADTheme.textTertiary)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(ADTheme.textTertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func metricTile(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(ADTheme.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        }
    }

    private func copyReport() {
        let report = """
        AirDesk diagnostics
        phase=\(session.phase.rawValue)
        mode=\(session.effectiveMode.rawValue)
        device=\(session.selectedDevice?.name ?? "none")
        runtime=\(session.runtimeName)
        runtimeState=\(session.runtimeState.rawValue)
        sessionId=\(session.sessionId)
        recoveryAttempts=\(session.recoveryAttempts)
        eventsSent=\(diagnostics.eventsSent)
        eventsPerSecond=\(diagnostics.eventsPerSecond)
        p50AckMs=\(String(format: "%.1f", diagnostics.p50Latency))
        p95AckMs=\(String(format: "%.1f", diagnostics.p95Latency))
        castDemo=\(environment.cast.isDemo)
        receiverConfigured=\(CastConfiguration.hasRegisteredReceiver)
        fabricState=\(environment.fabric.state.rawValue)
        fabricPeer=\(environment.fabric.remoteEndpointID ?? "none")
        fabricPath=\(environment.fabric.selectedPath?.isRelay == true ? "relay" : "direct-or-none")
        fabricRTTms=\(environment.fabric.selectedPath?.rttMs ?? 0)
        fabricRelayPolicy=\(environment.fabric.relayPolicyLabel)
        fabricRemoteInput=\(remoteInputState)
        identityDeviceId=\(environment.identity?.deviceId ?? "none")
        identityAlgorithm=\(environment.identity?.algorithm.rawValue ?? "none")
        identitySPKI=\(environment.identity?.spkiHex ?? "none")
        pairedPeers=\(environment.deviceRegistry?.pairedCount ?? 0)
        trustedPeers=\(environment.deviceRegistry?.trustedCount ?? 0)
        revokedPeers=\(environment.deviceRegistry?.revokedCount ?? 0)
        """
        UIPasteboard.general.string = report
        copied = true
        if environment.settings.hapticsEnabled { Haptics.shared.tap() }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}

private struct BrowserEndpointDiagnosticsSection: View {
    @ObservedObject var service: BrowserEndpointService

    var body: some View {
        Section {
            LabeledContent("Host", value: service.state.title)
            LabeledContent("Page", value: service.presentationURL == nil ? "Not bundled" : "Bundled")
            if let displayURL = service.presentationURL ?? service.endpointURL {
                LabeledContent("Display link", value: displayURL.absoluteString)
                    .lineLimit(2)
            }
            if let lastError = service.lastError {
                LabeledContent("Last error", value: lastError)
            }
        } header: {
            Text("BROWSER ENDPOINT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(ADTheme.textTertiary)
        } footer: {
            Text("The host binds to loopback only. It accepts the configured local asset origin and a short-lived session token.")
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

private struct CapabilityCatalogSection: View {
    @ObservedObject var catalog: CapabilityCatalog

    var body: some View {
        Section {
            if catalog.descriptors.isEmpty {
                Text("No capabilities advertised.")
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.textTertiary)
            } else {
                ForEach(catalog.descriptors) { capability in
                    capabilityRow(capability)
                }
            }
            if catalog.cameraCanRequestAccess {
                Button {
                    Task { await catalog.requestCameraAccess() }
                } label: {
                    Label("Request camera access", systemImage: "camera")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ADTheme.accent)
                }
            }
        } header: {
            Text("DEVICE CAPABILITIES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(ADTheme.textTertiary)
        } footer: {
            Text("Capability advertisement is not permission. Availability and authorization are reported separately; no capability grants, leases or remote invocation are issued in this baseline.")
        }
    }

    private func capabilityRow(_ capability: CapabilityDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(capability.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                Spacer(minLength: 8)
                Text(capability.availability.displayName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(availabilityColor(capability.availability))
                Text(capability.authorization.displayName)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(authorizationColor(capability.authorization))
            }
            Text(capability.capUri)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(ADTheme.textTertiary)
            if !capability.permissions.isEmpty {
                Text("Permissions: \(capability.permissions.joined(separator: ", "))")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
            }
            Text(capability.note)
                .font(.system(size: 11.5))
                .foregroundStyle(ADTheme.textSecondary)
                .lineSpacing(1)
        }
        .padding(.vertical, 2)
    }

    private func availabilityColor(_ availability: CapabilityAvailability) -> Color {
        switch availability {
        case .available: return ADTheme.accent
        case .busy: return ADTheme.amber
        case .restricted: return ADTheme.amber
        case .unavailable, .unknown: return ADTheme.textTertiary
        }
    }

    private func authorizationColor(_ authorization: CapabilityAuthorization) -> Color {
        switch authorization {
        case .granted: return ADTheme.accent
        case .denied, .revoked: return ADTheme.amber
        case .ungranted, .unknown: return ADTheme.textTertiary
        }
    }
}
