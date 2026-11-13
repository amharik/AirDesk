import AirDeskCore
import Foundation

enum CoreFeature: String, CaseIterable, Codable, Sendable {
    case movement
    case envelope
    case pairing
    case sync

    var title: String {
        switch self {
        case .movement: return "Pointer movement"
        case .envelope: return "ADFP envelope"
        case .pairing: return "Pairing"
        case .sync: return "Workspace sync"
        }
    }
}

enum CoreFeaturePath: String, CaseIterable, Codable, Sendable {
    case native
    case core

    var title: String {
        switch self {
        case .native: return "Native"
        case .core: return "Shared core"
        }
    }
}

enum CoreFallbackReason: String, Codable, Sendable {
    case none
    case bindingUnavailable = "binding-unavailable"
    case independentReviewRequired = "independent-review-required"
    case fixtureMigrationPending = "fixture-migration-pending"

    var title: String {
        switch self {
        case .none: return "Ready"
        case .bindingUnavailable: return "Binding not exported"
        case .independentReviewRequired: return "Independent review required"
        case .fixtureMigrationPending: return "Fixture migration pending"
        }
    }
}

struct CoreFeatureSelection: Equatable, Sendable {
    let feature: CoreFeature
    let requested: CoreFeaturePath
    let active: CoreFeaturePath
    let reason: CoreFallbackReason

    var isFallback: Bool {
        requested != active
    }

    var telemetry: String {
        "\(feature.rawValue)=\(active.rawValue) requested=\(requested.rawValue) reason=\(reason.rawValue)"
    }
}

enum CoreMovementSupport {
    static let isAvailable: Bool = {
        (try? CoreOneEuroFilter(minCutoff: 1.0, beta: 160.0, dCutoff: 1.0)) != nil
    }()
}

enum CoreCutoverPolicy {
    static func resolve(
        feature: CoreFeature,
        requested: CoreFeaturePath,
        movementAvailable: Bool = CoreMovementSupport.isAvailable
    ) -> CoreFeatureSelection {
        guard requested == .core else {
            return CoreFeatureSelection(
                feature: feature,
                requested: requested,
                active: .native,
                reason: .none
            )
        }

        switch feature {
        case .movement:
            return CoreFeatureSelection(
                feature: feature,
                requested: requested,
                active: movementAvailable ? .core : .native,
                reason: movementAvailable ? .none : .bindingUnavailable
            )
        case .envelope:
            return CoreFeatureSelection(
                feature: feature,
                requested: requested,
                active: .native,
                reason: .bindingUnavailable
            )
        case .pairing:
            return CoreFeatureSelection(
                feature: feature,
                requested: requested,
                active: .native,
                reason: .independentReviewRequired
            )
        case .sync:
            return CoreFeatureSelection(
                feature: feature,
                requested: requested,
                active: .native,
                reason: .fixtureMigrationPending
            )
        }
    }
}

final class AdaptivePointerFilter: @unchecked Sendable {
    private let parameters: OneEuroFilterParameters
    private var native: OneEuroFilter
    private var core: CoreOneEuroFilter?
    private(set) var backend: CoreFeaturePath
    private(set) var didFallback = false

    init(
        backend: CoreFeaturePath = .native,
        parameters: OneEuroFilterParameters = .pointer
    ) {
        self.parameters = parameters
        self.backend = backend
        self.native = OneEuroFilter(parameters: parameters)
        self.core = Self.makeCoreFilter(parameters: parameters)
    }

    func setBackend(_ backend: CoreFeaturePath) {
        guard self.backend != backend else { return }
        self.backend = backend
        if backend == .core, core == nil {
            core = Self.makeCoreFilter(parameters: parameters)
        }
        reset()
    }

    func reset() {
        native.reset()
        try? core?.reset()
        didFallback = false
    }

    func filter(x: Double, y: Double, timestamp: Double) -> (x: Double, y: Double) {
        if backend == .core, let core,
           let point = try? core.filter(x: x, y: y, timestamp: timestamp) {
            return (point.x, point.y)
        }
        if backend == .core {
            didFallback = true
        }
        return native.filter(x: x, y: y, timestamp: timestamp)
    }

    private static func makeCoreFilter(
        parameters: OneEuroFilterParameters
    ) -> CoreOneEuroFilter? {
        try? CoreOneEuroFilter(
            minCutoff: parameters.minCutoff,
            beta: parameters.beta,
            dCutoff: parameters.dCutoff
        )
    }
}
