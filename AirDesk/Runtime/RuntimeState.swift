import Foundation

enum RuntimeState: String, Codable, CaseIterable, Sendable {
    case idle
    case preparing
    case loading
    case ready
    case suspended
    case recovering
    case failed
    case stopped

    var title: String {
        switch self {
        case .idle: return "Idle"
        case .preparing: return "Preparing"
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .suspended: return "Suspended"
        case .recovering: return "Recovering"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    var isReady: Bool { self == .ready }

    var allowsInput: Bool { self == .ready }
}

struct RuntimeCapabilities: Equatable, Sendable {
    var desktopWindows: Bool
    var terminal: Bool
    var filesystem: Bool
    var workbench: Bool
    var browser: Bool
    var persistentStorage: Bool
    var liveKernel: Bool
    var taskExecution: Bool

    static let wanixDesktop = RuntimeCapabilities(
        desktopWindows: true,
        terminal: true,
        filesystem: true,
        workbench: true,
        browser: true,
        persistentStorage: true,
        liveKernel: false,
        taskExecution: false
    )

    static let wanixKernel = RuntimeCapabilities(
        desktopWindows: false,
        terminal: true,
        filesystem: true,
        workbench: false,
        browser: false,
        persistentStorage: true,
        liveKernel: true,
        taskExecution: true
    )

    static let puter = RuntimeCapabilities(
        desktopWindows: true,
        terminal: false,
        filesystem: true,
        workbench: false,
        browser: true,
        persistentStorage: true,
        liveKernel: false,
        taskExecution: false
    )

    var labels: [String] {
        var result: [String] = []
        if desktopWindows { result.append("Windows") }
        if terminal { result.append("Terminal") }
        if filesystem { result.append("Files") }
        if workbench { result.append("Workbench") }
        if browser { result.append("Browser") }
        if persistentStorage { result.append("Persistent") }
        if liveKernel { result.append("Kernel") }
        if taskExecution { result.append("Tasks") }
        return result
    }
}
