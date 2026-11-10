import SwiftUI

struct RemoteTerminalSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: SessionCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var leaseMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.remoteTerminalEnabled) {
                    Label("Use SSH remote terminal", systemImage: "network")
                        .foregroundStyle(.white.opacity(0.88))
                }
                .tint(ADTheme.accent)

                Text("When enabled, the Terminal app runs a remote shell over SSH instead of the local Wanix shell. The default command attaches to a persistent tmux session named airdesk.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineSpacing(1.5)
            } header: {
                header("Connection")
            }

            Section {
                TextField("Host", text: $settings.remoteTerminalHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", value: $settings.remoteTerminalPort, format: .number)
                    .keyboardType(.numberPad)
                TextField("Username", text: $settings.remoteTerminalUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $settings.remoteTerminalPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                header("Server")
            } footer: {
                Text("The password is stored in the device Keychain when you apply these settings.")
            }

            Section {
                TextField("ssh-ed25519 AAAA…", text: $settings.remoteTerminalHostKey, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(3...6)
                Text("Paste the server's full OpenSSH public host key. AirDesk refuses connections that do not match this pinned key.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineSpacing(1.5)
            } header: {
                header("Pinned host key")
            }

            Section {
                TextField("tmux new -A -s airdesk", text: $settings.remoteTerminalStartupCommand)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 12, design: .monospaced))
                Text("Leave empty to open the account's default shell. The command runs inside an allocated PTY.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineSpacing(1.5)
            } header: {
                header("Startup command")
            }

            Section {
                Button {
                    authorize()
                } label: {
                    Label("Authorize terminal for this session", systemImage: "lock.shield")
                }
                .foregroundStyle(ADTheme.accent)

                Text("A scoped capability lease is required before the terminal can connect. Authorization is limited to this device, workspace, runtime and session, and expires after eight hours.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ADTheme.textTertiary)
                    .lineSpacing(1.5)

                if let leaseMessage {
                    Text(leaseMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(ADTheme.accent)
                }
            } header: {
                header("Authorization")
            }

            Section {
                Button {
                    apply()
                } label: {
                    Label("Save settings", systemImage: "checkmark")
                }
                .foregroundStyle(ADTheme.accent)

                HStack {
                    Text("Status")
                        .foregroundStyle(.white.opacity(0.86))
                    Spacer()
                    Text(session.remoteTerminalStatus)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(ADTheme.textTertiary)
                        .multilineTextAlignment(.trailing)
                }

                if let savedMessage {
                    Text(savedMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(ADTheme.accent)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(ADTheme.danger)
                }
            } header: {
                header("Apply")
            } footer: {
                Text("An open Terminal window restarts automatically, switching between the local shell and SSH.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AirDeskBackground(intensity: 0.45))
        .navigationTitle("Remote Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func authorize() {
        do {
            try settings.saveRemoteTerminalPassword()
            _ = try session.authorizeRemoteTerminal()
            errorMessage = nil
            leaseMessage = "Authorized this session for the remote terminal."
        } catch {
            leaseMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func apply() {
        do {
            try settings.saveRemoteTerminalPassword()
            if settings.remoteTerminalEnabled {
                _ = try settings.remoteTerminalProfile.makeConfiguration()
            }
            session.remoteTerminalSettingsDidChange()
            errorMessage = nil
            savedMessage = settings.remoteTerminalEnabled
                ? "Saved. An open Terminal window restarts with the new profile."
                : "Saved. An open Terminal window restarts with the local Wanix shell."
            leaseMessage = nil
        } catch {
            savedMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(ADTheme.textTertiary)
    }
}
