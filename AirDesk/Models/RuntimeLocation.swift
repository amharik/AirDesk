import Foundation

enum RuntimeLocation: String, Codable, CaseIterable, Sendable {
    case phone
    case castReceiver
    case androidDevice
    case remote
}
