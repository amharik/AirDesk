import Foundation

enum DisplayKind: String, Codable, CaseIterable, Sendable {
    case airPlay
    case wired
    case cast
    case preview
    case external

    var iconName: String {
        switch self {
        case .airPlay: return "appletv.fill"
        case .wired: return "display"
        case .cast: return "airplayvideo"
        case .preview: return DeviceContext.symbolName
        case .external: return "rectangle.on.rectangle"
        }
    }

    var label: String {
        switch self {
        case .airPlay: return "AirPlay"
        case .wired: return "Wired display"
        case .cast: return "Google Cast"
        case .preview: return "Preview"
        case .external: return "External display"
        }
    }
}

enum SessionMode: String, Codable, CaseIterable, Sendable {
    case extended
    case mirrored
    case cast
    case preview

    var title: String {
        switch self {
        case .extended: return "Extended desktop"
        case .mirrored: return "Mirrored"
        case .cast: return "Cast receiver"
        case .preview: return "On-device preview"
        }
    }

    var shortTitle: String {
        switch self {
        case .extended: return "Extended"
        case .mirrored: return "Mirrored"
        case .cast: return "Cast"
        case .preview: return "Preview"
        }
    }

    var detail: String {
        switch self {
        case .extended: return "Desktop on the display, controller stays on \(DeviceContext.name)."
        case .mirrored: return "The desktop fills \(DeviceContext.name) with a floating remote and is mirrored to the TV."
        case .cast: return "AirDesk receiver renders the desktop independently."
        case .preview: return "A live desktop preview runs on this device."
        }
    }

    var iconName: String {
        switch self {
        case .extended: return "rectangle.on.rectangle.angled"
        case .mirrored: return "rectangle.on.rectangle"
        case .cast: return "airplayvideo"
        case .preview: return DeviceContext.symbolName
        }
    }
}

enum DisplayPresentationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case extended
    case mirrored

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extended: return "Extended desktop"
        case .mirrored: return "Mirror \(DeviceContext.name) screen"
        }
    }

    var shortTitle: String {
        switch self {
        case .extended: return "Extended"
        case .mirrored: return "Mirrored"
        }
    }

    var detail: String {
        switch self {
        case .extended: return "The display renders the Wanix desktop while the controller stays on \(DeviceContext.name)."
        case .mirrored: return "AirPlay shares the entire \(DeviceContext.name) screen. AirDesk shows the desktop full-screen with a collapsible floating remote."
        }
    }

    var iconName: String {
        switch self {
        case .extended: return "rectangle.on.rectangle.angled"
        case .mirrored: return "rectangle.on.rectangle"
        }
    }
}

struct DisplayDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let kind: DisplayKind
    var mode: SessionMode
    var isDemo: Bool = false
    var isAvailable: Bool = true

    var iconName: String { kind.iconName }
    var statusText: String { mode.shortTitle }

    static let previewID = "preview.local"
    static let demoAppleTV = "demo.airplay.living-room"
    static let demoCast = "demo.cast.studio"
    static let demoWired = "demo.wired.display"
}
