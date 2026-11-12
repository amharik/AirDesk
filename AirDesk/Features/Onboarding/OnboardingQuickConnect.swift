import Foundation

struct OnboardingQuickConnect: Equatable, Sendable {
    enum Route: String, Equatable, Sendable {
        case external
        case airPlay
        case cast
        case preview
    }

    struct Recommendation: Equatable, Sendable {
        let route: Route
        let device: DisplayDevice

        var title: String {
            switch route {
            case .external:
                return "Continue on \(device.name)"
            case .airPlay:
                return "Continue with AirPlay"
            case .cast:
                return "Cast to \(device.name)"
            case .preview:
                return "Preview on this \(DeviceContext.name)"
            }
        }

        var detail: String {
            switch route {
            case .external:
                return "Uses the connected display and skips manual setup."
            case .airPlay:
                return "Uses the active AirPlay mirroring route."
            case .cast:
                return "Uses the first available AirDesk Cast receiver."
            case .preview:
                return "Starts the on-device desktop without another setup step."
            }
        }

        var accessibilityLabel: String {
            "\(title). \(detail)"
        }

        var accessibilityHint: String {
            "Starts AirDesk immediately. Use Choose a display for advanced setup."
        }
    }

    static func recommend(
        externalDisplay: DisplayDevice?,
        airPlayMirroring: DisplayDevice?,
        castDevices: [DisplayDevice],
        preview: DisplayDevice
    ) -> Recommendation {
        if let externalDisplay {
            return Recommendation(route: .external, device: externalDisplay)
        }
        if let airPlayMirroring {
            return Recommendation(route: .airPlay, device: airPlayMirroring)
        }
        if let cast = castDevices.first(where: \.isAvailable) {
            return Recommendation(route: .cast, device: cast)
        }
        return Recommendation(route: .preview, device: preview)
    }
}
