import Foundation

struct CastDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let model: String
    let isDemo: Bool

    static let demoStudio = CastDevice(
        id: "demo-cast-studio",
        name: "Studio Receiver",
        model: "AirDesk Demo Receiver",
        isDemo: true
    )

    static let demoLivingRoom = CastDevice(
        id: "demo-cast-living-room",
        name: "Living Room",
        model: "Chromecast",
        isDemo: true
    )
}

enum CastConnectionState: String, Sendable {
    case idle
    case discovering
    case connecting
    case connected
    case failed
}

enum CastNamespace {
    static let input = "urn:x-cast:com.airdesk.input"
    static let control = "urn:x-cast:com.airdesk.control"
}

enum CastAdapterError: LocalizedError, Equatable {
    case deviceUnavailable
    case sdkUnavailable
    case notConnected
    case receiverNotConfigured
    case connectionTimedOut

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "The Cast device is no longer available."
        case .sdkUnavailable: return "The Google Cast SDK is not available in this build."
        case .notConnected: return "No Cast receiver is connected."
        case .receiverNotConfigured: return "Add a registered AirDesk receiver application ID to enable Google Cast."
        case .connectionTimedOut: return "The Cast receiver did not finish connecting."
        }
    }
}

struct CastConfiguration {
    static var receiverApplicationID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AirDeskCastReceiverApplicationID") as? String) ?? ""
    }

    static var hasRegisteredReceiver: Bool {
        !receiverApplicationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static var runtimeBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "AirDeskRuntimeBaseURL") as? String) ?? ""
    }
}
