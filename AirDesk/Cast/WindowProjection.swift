import Foundation

enum WindowProjectionTargetKind: String, Codable, CaseIterable, Sendable {
    case cast
    case browser
    case android
}

enum WindowProjectionState: String, Codable, Equatable, Sendable {
    case projecting
    case reconnecting
    case restored
    case released
    case failed
}

enum WindowProjectionFailureCode: String, Codable, Equatable, Sendable {
    case invalidIdentity = "invalid-identity"
    case invalidTarget = "invalid-target"
    case duplicateWindow = "duplicate-window"
    case targetConflict = "target-conflict"
    case notFound = "not-found"
    case illegalState = "illegal-state"
    case staleGeneration = "stale-generation"
    case staleRevision = "stale-revision"
}

struct WindowProjectionIdentity: Codable, Equatable, Sendable {
    var windowId: String
    var workspaceId: String
    var title: String
    var hostSessionId: String
    var generation: Int
}

struct WindowProjectionTarget: Codable, Equatable, Sendable {
    var targetId: String
    var kind: WindowProjectionTargetKind
    var displaySessionId: String
}

struct WindowProjection: Equatable, Sendable {
    var identity: WindowProjectionIdentity
    var target: WindowProjectionTarget
    var state: WindowProjectionState
    var surfaceRevision: Int
    var computeLocation: String
    var createdAt: Date
    var updatedAt: Date
    var lastError: String?
}

struct WindowProjectionFailure: Error, Equatable, Sendable {
    let code: WindowProjectionFailureCode
    let message: String
}

enum WindowProjectionResult {
    case success(WindowProjection)
    case failure(WindowProjectionFailure)
}

final class WindowProjectionRegistry {
    private var projections: [String: WindowProjection] = [:]
    private var targets: [String: String] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func begin(
        identity: WindowProjectionIdentity,
        target: WindowProjectionTarget
    ) -> WindowProjectionResult {
        guard Self.isValid(identity) else {
            return .failure(.init(code: .invalidIdentity, message: "Window identity is invalid."))
        }
        guard Self.isValid(target) else {
            return .failure(.init(code: .invalidTarget, message: "Projection target is invalid."))
        }
        if let existing = projections[identity.windowId],
           existing.state != .released, existing.state != .failed {
            return .failure(.init(
                code: .duplicateWindow,
                message: "Window \(identity.windowId) is already projecting."
            ))
        }
        if let owner = targets[target.displaySessionId], owner != identity.windowId {
            return .failure(.init(
                code: .targetConflict,
                message: "Display \(target.displaySessionId) is already projecting window \(owner)."
            ))
        }

        let timestamp = now()
        let projection = WindowProjection(
            identity: identity,
            target: target,
            state: .projecting,
            surfaceRevision: 0,
            computeLocation: "host",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        projections[identity.windowId] = projection
        targets[target.displaySessionId] = identity.windowId
        return .success(projection)
    }

    func acknowledgeSurface(windowId: String, revision: Int) -> WindowProjectionResult {
        guard var projection = projections[windowId] else {
            return .failure(.init(code: .notFound, message: "Window \(windowId) is not projecting."))
        }
        guard projection.state == .projecting || projection.state == .restored else {
            return .failure(.init(
                code: .illegalState,
                message: "Window \(windowId) cannot accept surfaces while \(projection.state.rawValue)."
            ))
        }
        guard revision >= 1 else {
            return .failure(.init(
                code: .staleRevision,
                message: "Surface revision must be a positive integer."
            ))
        }
        guard revision > projection.surfaceRevision else {
            return .failure(.init(
                code: .staleRevision,
                message: "Surface revision \(revision) is not newer than \(projection.surfaceRevision)."
            ))
        }
        projection.surfaceRevision = revision
        projection.updatedAt = now()
        projections[windowId] = projection
        return .success(projection)
    }

    func disconnect(windowId: String, reason: String) -> WindowProjectionResult {
        guard var projection = projections[windowId] else {
            return .failure(.init(code: .notFound, message: "Window \(windowId) is not projecting."))
        }
        if projection.state == .reconnecting {
            return .success(projection)
        }
        guard projection.state == .projecting || projection.state == .restored else {
            return .failure(.init(
                code: .illegalState,
                message: "Window \(windowId) cannot disconnect from \(projection.state.rawValue)."
            ))
        }
        projection.state = .reconnecting
        projection.lastError = reason
        projection.updatedAt = now()
        projections[windowId] = projection
        return .success(projection)
    }

    func resume(
        windowId: String,
        target: WindowProjectionTarget,
        generation: Int
    ) -> WindowProjectionResult {
        guard var projection = projections[windowId] else {
            return .failure(.init(code: .notFound, message: "Window \(windowId) is not projecting."))
        }
        guard projection.state == .reconnecting else {
            return .failure(.init(
                code: .illegalState,
                message: "Window \(windowId) is not reconnecting."
            ))
        }
        guard Self.isValid(target) else {
            return .failure(.init(code: .invalidTarget, message: "Projection target is invalid."))
        }
        guard generation >= projection.identity.generation else {
            return .failure(.init(code: .staleGeneration, message: "Reconnect generation is stale."))
        }
        if let owner = targets[target.displaySessionId], owner != windowId {
            return .failure(.init(
                code: .targetConflict,
                message: "Display \(target.displaySessionId) is already projecting window \(owner)."
            ))
        }

        if target.displaySessionId != projection.target.displaySessionId {
            targets.removeValue(forKey: projection.target.displaySessionId)
            targets[target.displaySessionId] = windowId
        }
        projection.target = target
        projection.identity.generation = generation
        projection.state = .restored
        projection.lastError = nil
        projection.updatedAt = now()
        projections[windowId] = projection
        return .success(projection)
    }

    func release(windowId: String) -> WindowProjectionResult {
        guard var projection = projections[windowId] else {
            return .failure(.init(code: .notFound, message: "Window \(windowId) is not projecting."))
        }
        if projection.state == .released {
            return .success(projection)
        }
        targets.removeValue(forKey: projection.target.displaySessionId)
        projection.state = .released
        projection.updatedAt = now()
        projections[windowId] = projection
        return .success(projection)
    }

    func fail(windowId: String, reason: String) -> WindowProjectionResult {
        guard var projection = projections[windowId] else {
            return .failure(.init(code: .notFound, message: "Window \(windowId) is not projecting."))
        }
        targets.removeValue(forKey: projection.target.displaySessionId)
        projection.state = .failed
        projection.lastError = reason
        projection.updatedAt = now()
        projections[windowId] = projection
        return .success(projection)
    }

    func get(windowId: String) -> WindowProjection? {
        projections[windowId]
    }

    func list() -> [WindowProjection] {
        projections.values
            .filter { $0.state != .released }
            .sorted { $0.identity.windowId < $1.identity.windowId }
    }

    private static func isValid(_ identity: WindowProjectionIdentity) -> Bool {
        isValidIdentifier(identity.windowId) &&
            isValidIdentifier(identity.workspaceId) &&
            isValidIdentifier(identity.hostSessionId) &&
            !identity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            identity.title.count <= 256 &&
            identity.generation >= 0
    }

    private static func isValid(_ target: WindowProjectionTarget) -> Bool {
        WindowProjectionTargetKind.allCases.contains(target.kind) &&
            isValidIdentifier(target.targetId) &&
            isValidIdentifier(target.displaySessionId)
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...128).contains(bytes.count), let first = bytes.first else {
            return false
        }
        let isFirst = (48...57).contains(first) ||
            (65...90).contains(first) ||
            (97...122).contains(first)
        guard isFirst else { return false }
        return bytes.allSatisfy { byte in
            (48...57).contains(byte) ||
                (65...90).contains(byte) ||
                (97...122).contains(byte) ||
                byte == 45 ||
                byte == 46 ||
                byte == 58 ||
                byte == 95
        }
    }
}
