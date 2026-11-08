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
    @State private var enteredPin = ""
    @State private var verificationCode = ""
    @State private var notice: String?
    @State private var errorMessage: String?

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
        .onDisappear {
            hostSession.cancel()
            controllerSession.cancel()
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

            Button {
                if let value = UIPasteboard.general.string {
                    enteredCode = value
                }
            } label: {
                Label("Paste from clipboard", systemImage: "doc.on.clipboard")
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
            Text("Scanning with the camera is not enabled yet; paste the code shown on the host.")
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
                try environment.activateWorkspaceSync(pairingKeys: keys)
                notice = "Pairing verified and workspace sync activated."
            } catch {
                notice = "Pairing verified. Workspace sync is unavailable: \(error.localizedDescription)"
            }
            verificationCode = ""
        } catch {
            errorMessage = error.localizedDescription
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
