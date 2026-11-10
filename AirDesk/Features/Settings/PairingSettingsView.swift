import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct PairingSettingsView: View {
    enum Role: String, CaseIterable, Identifiable {
        case host = "This device"
        case controller = "Another device"

        var id: String { rawValue }
    }

    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var hostSession: AdPairLiveSession
    @StateObject private var controllerSession: AdPairLiveSession
    @State private var role: Role = .host
    @State private var mode: AdPairCode.Mode = .pin
    @State private var enteredCode = ""
    @State private var isScanningQR = false
    @State private var enteredPin = ""
    @State private var verificationCode = ""
    @State private var notice: String?
    @State private var errorMessage: String?
    @State private var knownPeers: [PairedPeerRecord] = []
    @State private var pendingRevocation: PairedPeerRecord?
    @State private var pendingRemoval: PairedPeerRecord?

    init(
        identity: DeviceIdentity,
        registry: DeviceRegistry?,
        fabric: IrohFabricPeer,
        relayPolicy: IrohRelayPolicy
    ) {
        _hostSession = StateObject(wrappedValue: AdPairLiveSession(
            role: .host,
            identity: identity,
            peer: fabric,
            registry: registry,
            relayPolicy: relayPolicy,
            peerDisplayLabel: "Paired controller"
        ))
        _controllerSession = StateObject(wrappedValue: AdPairLiveSession(
            role: .controller,
            identity: identity,
            peer: fabric,
            registry: registry,
            relayPolicy: relayPolicy,
            peerDisplayLabel: "Paired host"
        ))
    }

    var body: some View {
        Form {
            Section {
                Picker("Role", selection: $role) {
                    ForEach(Role.allCases) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: role) { _, _ in
                    reset()
                }
            } header: {
                Text("Pairing role")
            } footer: {
                Text("Create a code on one device, then enter it on the other. Compare the six-digit verification code on both screens before activating workspace sync.")
            }

            switch role {
            case .host:
                hostSection
            case .controller:
                controllerSection
            }

            knownDevicesSection

            if let notice {
                Section {
                    Text(notice)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ADTheme.accent)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AirDeskBackground(intensity: 0.45))
        .navigationTitle("Pair a Device")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $isScanningQR) {
            NavigationStack {
                QRCodeScannerView { code in
                    enteredCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    isScanningQR = false
                }
                .ignoresSafeArea()
                .navigationTitle("Scan Pairing Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isScanningQR = false }
                    }
                }
            }
        }
        .confirmationDialog(
            pendingRevocation.map { "Revoke \($0.displayLabel)?" } ?? "Revoke device?",
            isPresented: Binding(
                get: { pendingRevocation != nil },
                set: { if !$0 { pendingRevocation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Revoke trust", role: .destructive) {
                if let record = pendingRevocation { revoke(record) }
                pendingRevocation = nil
            }
            Button("Cancel", role: .cancel) { pendingRevocation = nil }
        } message: {
            Text("This device will no longer be trusted and its sync envelopes will be rejected.")
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove \($0.displayLabel)?" } ?? "Remove device?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove record", role: .destructive) {
                if let record = pendingRemoval { remove(record) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This removes the local pairing record. It does not change trust on the other device.")
        }
        .onAppear {
            refreshPeers()
        }
        .onDisappear {
            hostSession.cancel()
            controllerSession.cancel()
        }
    }

    @ViewBuilder
    private var knownDevicesSection: some View {
        Section {
            if knownPeers.isEmpty {
                Text("No paired devices yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(ADTheme.textTertiary)
            }
            ForEach(knownPeers, id: \.deviceId) { record in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(record.displayLabel)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(trustTitle(record.trustState))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(trustTint(record.trustState))
                    }
                    Text(record.deviceId)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(ADTheme.textTertiary)
                        .lineLimit(1)
                    HStack {
                        Text("Paired \(record.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11))
                            .foregroundStyle(ADTheme.textTertiary)
                        Spacer()
                        if record.trustState == .trusted {
                            Button("Revoke", role: .destructive) {
                                pendingRevocation = record
                            }
                        } else {
                            Button("Remove", role: .destructive) {
                                pendingRemoval = record
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Known devices")
        } footer: {
            Text("Pending devices have completed the cryptographic exchange but not SAS verification.")
        }
    }

    @ViewBuilder
    private var hostSection: some View {
        Section {
            Picker("Code type", selection: $mode) {
                Text("PIN").tag(AdPairCode.Mode.pin)
                Text("QR secret").tag(AdPairCode.Mode.qrSecret)
            }
            .pickerStyle(.segmented)

            Button {
                Task { await startHost() }
            } label: {
                Label("Create pairing code", systemImage: "qrcode")
            }
            .disabled(hostSession.state != .idle)
        } header: {
            Text("Create code")
        } footer: {
            Text("The QR code contains a short-lived secret and connection ticket, never this device's private key.")
        }

        if let code = hostSession.code {
            Section {
                if let pin = hostSession.pin {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PIN")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ADTheme.textTertiary)
                        Text(pin)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .tracking(6)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }

                if let image = qrImage(code) {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(12)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Spacer()
                    }
                }

                Text(code)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineLimit(4)
                    .textSelection(.enabled)

                Button {
                    UIPasteboard.general.string = code
                    notice = "Pairing code copied."
                } label: {
                    Label("Copy pairing code", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Share this code")
            } footer: {
                Text("Keep this code private until the other device joins. It expires automatically.")
            }
        }

        sessionStatusSection(hostSession)
    }

    @ViewBuilder
    private var controllerSection: some View {
        Section {
            TextField("ADPAIR1:…", text: $enteredCode, axis: .vertical)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Button {
                    isScanningQR = true
                } label: {
                    Label("Scan QR code", systemImage: "qrcode.viewfinder")
                }

                Spacer()

                Button {
                    if let value = UIPasteboard.general.string {
                        enteredCode = value
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
            }

            TextField("Six-digit PIN, if requested", text: $enteredPin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 18, design: .monospaced))

            Button {
                Task { await join() }
            } label: {
                Label("Join pairing", systemImage: "arrow.right.circle")
            }
            .disabled(
                enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || controllerSession.state != .idle
            )
        } header: {
            Text("Enter pairing code")
        } footer: {
            Text("Scan the QR code shown on the host, or paste the pairing code.")
        }

        sessionStatusSection(controllerSession)
    }

    @ViewBuilder
    private func sessionStatusSection(_ session: AdPairLiveSession) -> some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(statusTitle(session.state))
                    .foregroundStyle(statusTint(session.state))
            }

            if session.state == .awaitingUserVerification,
               let sas = session.shortAuthenticationString {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Verification code")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ADTheme.textTertiary)
                    Text(sas)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .textSelection(.enabled)
                    Text("Both devices must show the same code.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ADTheme.textSecondary)
                }
                .padding(.vertical, 4)

                TextField("Enter verification code", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 18, design: .monospaced))

                Button {
                    confirm(session)
                } label: {
                    Label("Confirm and activate sync", systemImage: "checkmark.shield")
                }
            }

            if session.state != .idle {
                Button(role: .destructive) {
                    session.cancel()
                    verificationCode = ""
                } label: {
                    Label("Cancel pairing", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Pairing status")
        }
    }

    private func startHost() async {
        notice = nil
        errorMessage = nil
        verificationCode = ""
        controllerSession.cancel()
        do {
            try await hostSession.startHost(mode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func join() async {
        notice = nil
        errorMessage = nil
        verificationCode = ""
        hostSession.cancel()
        do {
            try await controllerSession.join(
                code: enteredCode,
                pin: enteredPin.isEmpty ? nil : enteredPin
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirm(_ session: AdPairLiveSession) {
        notice = nil
        errorMessage = nil
        do {
            let keys = try session.confirmShortAuthenticationString(verificationCode)
            do {
                if session.isHost {
                    guard let endpointID = session.remoteEndpointID else {
                        throw AdPairLiveError.peerUnavailable(
                            "The paired peer endpoint is unavailable."
                        )
                    }
                    try environment.activateWorkspaceSyncForHost(
                        pairingKeys: keys,
                        remoteEndpointID: endpointID
                    )
                } else {
                    guard let hostDeviceId = session.peerDeviceId else {
                        throw AdPairLiveError.peerUnavailable(
                            "The paired host identity is unavailable."
                        )
                    }
                    try environment.activateWorkspaceSync(
                        pairingKeys: keys,
                        hostDeviceId: hostDeviceId
                    )
                }
                notice = "Pairing verified and workspace sync activated."
            } catch {
                notice = "Pairing verified. Workspace sync is unavailable: \(error.localizedDescription)"
            }
            verificationCode = ""
            refreshPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ record: PairedPeerRecord) {
        do {
            try environment.revokePairedDevice(deviceId: record.deviceId)
            notice = "Trust revoked for \(record.displayLabel)."
            errorMessage = nil
            refreshPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ record: PairedPeerRecord) {
        do {
            guard let registry = environment.deviceRegistry else {
                throw DeviceRegistryError.peerNotFound(record.deviceId)
            }
            try registry.remove(deviceId: record.deviceId)
            notice = "Removed \(record.displayLabel) from this device."
            errorMessage = nil
            refreshPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshPeers() {
        knownPeers = environment.deviceRegistry?.peers ?? []
    }

    private func trustTitle(_ state: DeviceTrustState) -> String {
        switch state {
        case .pending: return "Awaiting SAS"
        case .trusted: return "Trusted"
        case .revoked: return "Revoked"
        }
    }

    private func trustTint(_ state: DeviceTrustState) -> Color {
        switch state {
        case .pending: return ADTheme.amber
        case .trusted: return ADTheme.accent
        case .revoked: return .red
        }
    }

    private func reset() {
        hostSession.cancel()
        controllerSession.cancel()
        enteredCode = ""
        enteredPin = ""
        verificationCode = ""
        notice = nil
        errorMessage = nil
    }

    private func statusTitle(_ state: AdPairLiveSession.State) -> String {
        switch state {
        case .idle: return "Not started"
        case .waitingForController: return "Waiting for code entry"
        case .awaitingShare: return "Starting secure exchange"
        case .awaitingVerifierResponse: return "Verifying peer"
        case .awaitingInitiatorFinish: return "Finishing verification"
        case .awaitingUserVerification: return "Compare codes"
        case .completed: return "Paired"
        case .failed: return "Failed"
        }
    }

    private func statusTint(_ state: AdPairLiveSession.State) -> Color {
        switch state {
        case .completed: return ADTheme.accent
        case .failed: return .red
        case .awaitingUserVerification: return ADTheme.amber
        default: return ADTheme.textSecondary
        }
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
