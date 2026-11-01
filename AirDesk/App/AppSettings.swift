import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let sensitivity = "airdesk.pointer.sensitivity"
        static let acceleration = "airdesk.pointer.acceleration"
        static let naturalScrolling = "airdesk.pointer.naturalScroll"
        static let haptics = "airdesk.haptics"
        static let runtime = "airdesk.runtime"
        static let desktopAppearance = "airdesk.desktop.appearance"
        static let showHints = "airdesk.ui.hints"
        static let displayMode = "airdesk.display.mode"
        static let remoteTerminalEnabled = "airdesk.remoteTerminal.enabled"
        static let remoteTerminalHost = "airdesk.remoteTerminal.host"
        static let remoteTerminalPort = "airdesk.remoteTerminal.port"
        static let remoteTerminalUsername = "airdesk.remoteTerminal.username"
        static let remoteTerminalHostKey = "airdesk.remoteTerminal.hostKey"
        static let remoteTerminalStartupCommand = "airdesk.remoteTerminal.startupCommand"
    }

    private static let remoteTerminalKeychainService = "com.airdesk.ios.remote-terminal"
    private static let remoteTerminalKeychainAccount = "password"

    @Published var pointerSensitivity: Double {
        didSet { defaults.set(pointerSensitivity, forKey: Key.sensitivity) }
    }

    @Published var pointerAcceleration: Bool {
        didSet { defaults.set(pointerAcceleration, forKey: Key.acceleration) }
    }

    @Published var naturalScrolling: Bool {
        didSet { defaults.set(naturalScrolling, forKey: Key.naturalScrolling) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) }
    }

    @Published var runtimeChoice: RuntimeChoice {
        didSet { defaults.set(runtimeChoice.rawValue, forKey: Key.runtime) }
    }

    @Published var desktopAppearance: String {
        didSet { defaults.set(desktopAppearance, forKey: Key.desktopAppearance) }
    }

    @Published var showInteractionHints: Bool {
        didSet { defaults.set(showInteractionHints, forKey: Key.showHints) }
    }

    @Published var displayMode: DisplayPresentationMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    @Published var remoteTerminalEnabled: Bool {
        didSet { defaults.set(remoteTerminalEnabled, forKey: Key.remoteTerminalEnabled) }
    }

    @Published var remoteTerminalHost: String {
        didSet { defaults.set(remoteTerminalHost, forKey: Key.remoteTerminalHost) }
    }

    @Published var remoteTerminalPort: Int {
        didSet { defaults.set(remoteTerminalPort, forKey: Key.remoteTerminalPort) }
    }

    @Published var remoteTerminalUsername: String {
        didSet { defaults.set(remoteTerminalUsername, forKey: Key.remoteTerminalUsername) }
    }

    @Published var remoteTerminalHostKey: String {
        didSet { defaults.set(remoteTerminalHostKey, forKey: Key.remoteTerminalHostKey) }
    }

    @Published var remoteTerminalStartupCommand: String {
        didSet { defaults.set(remoteTerminalStartupCommand, forKey: Key.remoteTerminalStartupCommand) }
    }

    @Published var remoteTerminalPassword: String
    @Published private(set) var remoteTerminalCredentialError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pointerSensitivity = defaults.object(forKey: Key.sensitivity) as? Double ?? 0.8
        pointerAcceleration = defaults.object(forKey: Key.acceleration) as? Bool ?? true
        naturalScrolling = defaults.object(forKey: Key.naturalScrolling) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        showInteractionHints = defaults.object(forKey: Key.showHints) as? Bool ?? true
        desktopAppearance = defaults.string(forKey: Key.desktopAppearance) ?? "dark"
        remoteTerminalEnabled = defaults.object(forKey: Key.remoteTerminalEnabled) as? Bool ?? false
        remoteTerminalHost = defaults.string(forKey: Key.remoteTerminalHost) ?? ""
        remoteTerminalPort = defaults.object(forKey: Key.remoteTerminalPort) as? Int ?? 22
        remoteTerminalUsername = defaults.string(forKey: Key.remoteTerminalUsername) ?? ""
        remoteTerminalHostKey = defaults.string(forKey: Key.remoteTerminalHostKey) ?? ""
        remoteTerminalStartupCommand = defaults.string(forKey: Key.remoteTerminalStartupCommand)
            ?? "tmux new -A -s airdesk"
        remoteTerminalPassword = (try? SecureStorage.load(
            service: Self.remoteTerminalKeychainService,
            account: Self.remoteTerminalKeychainAccount
        ))
        .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        remoteTerminalCredentialError = nil
        if let raw = defaults.string(forKey: Key.displayMode), let mode = DisplayPresentationMode(rawValue: raw) {
            displayMode = mode
        } else {
            displayMode = .extended
        }
        if let raw = defaults.string(forKey: Key.runtime), let choice = RuntimeChoice(rawValue: raw) {
            runtimeChoice = choice
        } else {
            runtimeChoice = .wanixDesktop
        }
    }

    var availableRuntimes: [RuntimeChoice] {
        [.wanixDesktop, .wanixKernel]
    }

    var remoteTerminalProfile: RemoteTerminalProfile {
        RemoteTerminalProfile(
            enabled: remoteTerminalEnabled,
            host: remoteTerminalHost,
            port: remoteTerminalPort,
            username: remoteTerminalUsername,
            hostKey: remoteTerminalHostKey,
            startupCommand: remoteTerminalStartupCommand,
            password: remoteTerminalPassword
        )
    }

    func saveRemoteTerminalPassword() throws {
        do {
            if remoteTerminalPassword.isEmpty {
                SecureStorage.delete(
                    service: Self.remoteTerminalKeychainService,
                    account: Self.remoteTerminalKeychainAccount
                )
            } else {
                try SecureStorage.save(
                    Data(remoteTerminalPassword.utf8),
                    service: Self.remoteTerminalKeychainService,
                    account: Self.remoteTerminalKeychainAccount
                )
            }
            remoteTerminalCredentialError = nil
        } catch {
            remoteTerminalCredentialError = error.localizedDescription
            throw error
        }
    }

    func reset() {
        pointerSensitivity = 0.8
        pointerAcceleration = true
        naturalScrolling = true
        hapticsEnabled = true
        showInteractionHints = true
        desktopAppearance = "dark"
        displayMode = .extended
        runtimeChoice = .wanixDesktop
        remoteTerminalEnabled = false
        remoteTerminalHost = ""
        remoteTerminalPort = 22
        remoteTerminalUsername = ""
        remoteTerminalHostKey = ""
        remoteTerminalStartupCommand = "tmux new -A -s airdesk"
        remoteTerminalPassword = ""
        try? saveRemoteTerminalPassword()
    }
}
