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
    }

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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pointerSensitivity = defaults.object(forKey: Key.sensitivity) as? Double ?? 0.8
        pointerAcceleration = defaults.object(forKey: Key.acceleration) as? Bool ?? true
        naturalScrolling = defaults.object(forKey: Key.naturalScrolling) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        showInteractionHints = defaults.object(forKey: Key.showHints) as? Bool ?? true
        desktopAppearance = defaults.string(forKey: Key.desktopAppearance) ?? "dark"
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

    func reset() {
        pointerSensitivity = 0.8
        pointerAcceleration = true
        naturalScrolling = true
        hapticsEnabled = true
        showInteractionHints = true
        desktopAppearance = "dark"
        displayMode = .extended
        runtimeChoice = .wanixDesktop
    }
}
