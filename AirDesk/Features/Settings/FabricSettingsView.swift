import SwiftUI
import UIKit

struct FabricSettingsView: View {
    @ObservedObject var fabric: IrohFabricPeer
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator

    @State private var ticketInput = ""
    @State private var relayDraft = ""
    @State private var busy = false
    @State private var message: String?
    @State private var copied = false

    var body: some View {
        Form {
            identitySection
            connectionSection
            relaySection
            ticketSection
            pathSection
            inputSection
            securitySection
        }
        .scrollContentBackground(.hidden)
        .background(AirDeskBackground(intensity: 0.45))
        .navigationTitle("Iroh Fabric")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            relayDraft = settings.fabricRelayURLs
        }
        .onChange(of: fabric.ticket) { _, _ in
            copied = false
        }
    }

    private var identitySection: some View {
        Section {
            if let identity = environment.identity {
                infoRow("Device ID", identity.deviceId)
                infoRow("Algorithm", identity.algorithm.displayName)
                infoRow("Public key", identity.spkiHex)
                infoRow("Paired devices", "\(environment.deviceRegistry?.pairedCount ?? 0)")
                infoRow("Revoked", "\(environment.deviceRegistry?.revokedCount ?? 0)")
                Button {
                    UIPasteboard.general.string = identity.deviceId
                    message = "Device ID copied."
                } label: {
                    Label("Copy device ID", systemImage: "doc.on.doc")
                }
                .foregroundStyle(ADTheme.accent)
                Button {
                    UIPasteboard.general.string = identity.spkiHex
                    message = "Public key copied."
                } label: {
                    Label("Copy public key", systemImage: "key")
                }
                .foregroundStyle(ADTheme.accent)
            } else {
                infoRow("Device identity", "Unavailable")
                if let error = environment.identityError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(ADTheme.danger)
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.accent)
            }
        } header: {
            header("Device identity")
        } footer: {
            Text("The long-term Ed25519 key is stored in the Keychain after first unlock, this device only, without iCloud sync. P-256 is the fallback identity algorithm; Secure Enclave Ed25519 is not claimed. Pairing offers require an out-of-band channel binding. The browser has AD-PAIR-1 and an RFC 9383 SPAKE2+ primitive; interactive pairing, QR scanning and transport binding are not implemented.")
        }
        .listRowBackground(rowBackground)
    }

    private var connectionSection: some View {
        Section {
            HStack {
                Text("Endpoint")
                    .foregroundStyle(.white.opacity(0.86))
                Spacer()
                Text(fabric.state.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(stateTint)
            }
            infoRow("Endpoint ID", fabric.endpointID.isEmpty ? "Not started" : fabric.endpointID)
            infoRow("Relay policy", fabric.relayPolicyLabel)
            if let relayURL = fabric.relayURL {
                infoRow("Home relay", relayURL)
            }
            if let error = fabric.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.danger)
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.accent)
            }
            Button {
                Task {
                    busy = true
                    await environment.applyFabricSettings()
                    busy = false
                }
            } label: {
                Label(
                    settings.fabricEnabled ? "Restart endpoint" : "Start endpoint",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .foregroundStyle(ADTheme.accent)
            .disabled(busy)
        } header: {
            header("Endpoint")
        } footer: {
            Text("Iroh binds a native endpoint only when enabled. Direct addresses are preferred; relay use is never implicit.")
        }
        .listRowBackground(rowBackground)
    }

    private var relaySection: some View {
        Section {
            TextField("https://relay.example.com", text: $relayDraft, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2...5)
            Button {
                settings.fabricRelayURLs = relayDraft
                Task {
                    busy = true
                    await environment.applyFabricSettings()
                    busy = false
                    message = relayDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Relay disabled. Restarted in direct-only mode."
                        : "Relay policy applied."
                }
            } label: {
                Label("Apply relay policy", systemImage: "checkmark")
            }
            .foregroundStyle(ADTheme.accent)
            .disabled(busy)
        } header: {
            header("Self-hosted relay")
        } footer: {
            Text("Leave empty for direct-only operation. Provide one or more HTTPS relay URLs, separated by commas or new lines. Public relays are never selected automatically.")
        }
        .listRowBackground(rowBackground)
    }

    private var ticketSection: some View {
        Section {
            if fabric.ticket.isEmpty {
                Text("Start the endpoint to generate a pairing ticket.")
                    .font(.system(size: 12))
                    .foregroundStyle(ADTheme.textTertiary)
            } else {
                Text(fabric.ticket)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .textSelection(.enabled)
                Button {
                    UIPasteboard.general.string = fabric.ticket
                    copied = true
                } label: {
                    Label(copied ? "Ticket copied" : "Copy ticket", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .foregroundStyle(ADTheme.accent)
            }

            TextField("Paste a peer ticket", text: $ticketInput, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2...5)

            HStack(spacing: 16) {
                Button {
                    connect()
                } label: {
                    Label("Connect", systemImage: "link")
                }
                .foregroundStyle(ADTheme.accent)
                .disabled(busy || ticketInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    fabric.disconnect()
                    message = "Disconnected the active fabric peer."
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .disabled(!fabric.isConnected)
            }
        } header: {
            header("Pairing")
        } footer: {
            Text("Tickets contain the remote endpoint ID and direct addresses. Share them only with the device you intend to pair.")
        }
        .listRowBackground(rowBackground)
    }

    private var pathSection: some View {
        Section {
            infoRow("Peers", "\(fabric.connectionCount)")
            infoRow("Remote", fabric.remoteEndpointID ?? "None")
            if let path = fabric.selectedPath {
                infoRow("Selected path", path.isRelay ? "Relay" : (path.isDirectIP ? "Direct IP" : "Direct"))
                infoRow("Address", path.remoteAddress)
                infoRow("RTT", "\(path.rttMs) ms")
            } else {
                infoRow("Selected path", "None")
            }
            ForEach(Array(fabric.paths.enumerated()), id: \.offset) { _, path in
                HStack(spacing: 8) {
                    Image(systemName: path.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(path.isSelected ? ADTheme.accent : ADTheme.textTertiary)
                    Text(path.remoteAddress)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Text(path.isRelay ? "relay" : "direct")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(path.isRelay ? ADTheme.amber : ADTheme.accent)
                }
            }
        } header: {
            header("Paths")
        } footer: {
            Text("Path state comes from the live Iroh connection. AirDesk reports relay and direct paths separately and never labels a relayed session as direct.")
        }
        .listRowBackground(rowBackground)
    }

    private var inputSection: some View {
        Section {
            Toggle(isOn: $settings.fabricInputForwardingEnabled) {
                Label("Forward local input to peer", systemImage: "cursorarrow.motionlines")
                    .foregroundStyle(.white.opacity(0.88))
            }
            .tint(ADTheme.accent)
            .disabled(!fabric.isConnected)

            infoRow("Local route", settings.fabricInputForwardingEnabled && fabric.isConnected ? "Iroh fabric" : "Local runtime")

            if let controllerID = session.fabricControllerID {
                infoRow("Remote controller", controllerID)
                infoRow("Remote lease", session.fabricControllerHasLease ? "Granted" : "Not granted")
                if session.canGrantFabricControl {
                    Button {
                        session.grantFabricControl()
                    } label: {
                        Label("Grant remote control", systemImage: "hand.raised")
                    }
                    .foregroundStyle(ADTheme.accent)
                }
                if session.canReclaimLocalControl {
                    Button {
                        session.reclaimLocalControl()
                    } label: {
                        Label("Return control to this device", systemImage: "iphone")
                    }
                    .foregroundStyle(ADTheme.amber)
                }
            } else {
                infoRow("Remote controller", "None")
            }
        } header: {
            header("Input")
        } footer: {
            Text("Forwarding routes the Air Cursor to the paired peer. Incoming remote input requires an explicit lease grant before it can drive this device.")
        }
        .listRowBackground(rowBackground)
    }

    private var securitySection: some View {
        Section {
            Text("Iroh connections are encrypted and authenticated by the endpoint identity stored in the device Keychain. Pairing tickets contain reachability hints but no shared secret.")
                .font(.system(size: 12))
                .foregroundStyle(ADTheme.textSecondary)
                .lineSpacing(2)
        } header: {
            header("Security")
        }
        .listRowBackground(rowBackground)
    }

    private var stateTint: Color {
        switch fabric.state {
        case .connected, .ready: return ADTheme.accent
        case .starting, .connecting: return ADTheme.amber
        case .failed: return ADTheme.danger
        case .stopped: return ADTheme.textTertiary
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.04))
    }

    private func connect() {
        let ticket = ticketInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticket.isEmpty else { return }
        busy = true
        message = nil
        Task {
            do {
                try await fabric.connect(to: ticket)
                message = "Connected to the Iroh peer."
                ticketInput = ""
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }

    private func header(_ text: String) -> some View {
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
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ADTheme.textTertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
