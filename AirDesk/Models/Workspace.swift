import Foundation

struct Workspace: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var runtime: String
    var createdAt: Date

    static let `default` = Workspace(
        id: "workspace.local",
        name: "Wanix",
        runtime: "Wanix",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

enum RuntimeChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case wanixDesktop
    case wanixKernel
    case puter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wanixDesktop: return "Wanix Desktop"
        case .wanixKernel: return "Wanix Kernel"
        case .puter: return "Puter (experimental)"
        }
    }

    var subtitle: String {
        switch self {
        case .wanixDesktop: return "Bundled macOS-style workspace. Works offline."
        case .wanixKernel: return "Live wanix.wasm shell loaded from the CDN."
        case .puter: return "Cloud desktop loaded from puter.com. Requires network."
        }
    }

    var badge: String {
        switch self {
        case .wanixDesktop: return "Offline"
        case .wanixKernel: return "CDN"
        case .puter: return "Web"
        }
    }

    var requiresNetwork: Bool {
        self != .wanixDesktop
    }
}
