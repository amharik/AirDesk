import Foundation

enum RuntimeLocation: String, Codable, CaseIterable, Sendable {
    case phone
    case castReceiver
    case androidDevice
    case remote
}

enum DisplayTarget: String, Codable, CaseIterable, Sendable {
    case phone
    case externalScene
    case mirroredPhone
    case castReceiver
    case androidPresentation
    case stream
}

enum InputRoute: String, Codable, CaseIterable, Sendable {
    case localSurface
    case castChannel
    case inProcess
    case remoteChannel
}

struct DisplayProfile: Equatable, Sendable {
    let mode: SessionMode
    let runtime: RuntimeLocation
    let target: DisplayTarget
    let input: InputRoute

    static let preview = DisplayProfile(
        mode: .preview,
        runtime: .phone,
        target: .phone,
        input: .localSurface
    )
}

enum DisplayProfileError: LocalizedError, Equatable {
    case deviceUnavailable
    case castRequiresCastDevice
    case castDeviceRequiresCastMode

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "The selected display is no longer available."
        case .castRequiresCastDevice:
            return "The Cast profile requires a Cast device."
        case .castDeviceRequiresCastMode:
            return "A Cast device must use the Cast profile."
        }
    }
}

enum DisplayProfileResolver {
    static func resolve(mode: SessionMode, device: DisplayDevice) throws -> DisplayProfile {
        guard device.isAvailable else { throw DisplayProfileError.deviceUnavailable }
        guard mode == .cast || device.kind != .cast else {
            throw DisplayProfileError.castDeviceRequiresCastMode
        }
        guard mode != .cast || device.kind == .cast else {
            throw DisplayProfileError.castRequiresCastDevice
        }

        switch mode {
        case .preview:
            return DisplayProfile(mode: mode, runtime: .phone, target: .phone, input: .localSurface)
        case .extended:
            return DisplayProfile(mode: mode, runtime: .phone, target: .externalScene, input: .localSurface)
        case .mirrored:
            return DisplayProfile(mode: mode, runtime: .phone, target: .mirroredPhone, input: .localSurface)
        case .cast:
            return DisplayProfile(mode: mode, runtime: .castReceiver, target: .castReceiver, input: .castChannel)
        }
    }
}
