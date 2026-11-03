import Foundation

enum ControllerRole: String, Codable, CaseIterable, Sendable {
    case primaryDriver = "primary-driver"
    case pinnedSurfaceDriver = "pinned-surface-driver"
    case passiveObserver = "passive-observer"
}

struct ControllerAttachment: Equatable, Sendable {
    var controllerId: String
    var deviceId: String
    var role: ControllerRole
    var targetWindowId: String?
    var targetPtyId: String?
    var lastSeen: Date
}

struct InputPoint: Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

struct InputCursorUpdate: Equatable, Sendable {
    var controllerId: String
    var local: InputPoint
    var shared: InputPoint?
}

struct InputLeaseChange: Equatable, Sendable {
    var previousControllerId: String?
    var activeControllerId: String?
    var leaseEpoch: UInt64
    var releasedAllInput: Bool
    var reason: String
}

struct InputAuditEntry: Equatable, Sendable {
    var timestamp: Date
    var controllerId: String
    var action: String
    var accepted: Bool
    var detail: String
}

enum InputLeaseError: Error, Equatable, LocalizedError {
    case controllerAlreadyAttached(String)
    case controllerMissing(String)
    case unauthenticatedConnection
    case sessionMismatch
    case generationMismatch(expected: UInt64, received: UInt64)
    case epochRejected(currentEpoch: UInt64)
    case sequenceRejected(controllerId: String, sequence: Int)
    case leaseBusy(activeControllerId: String)
    case noActiveLease
    case roleNotPermitted(controllerId: String, role: ControllerRole)
    case targetMismatch(controllerId: String)
    case pinnedRoleRequiresTarget(String)
    case preemptionNotConfirmed
    case preemptionRateLimited(String)
    case invalidCoordinates

    var errorDescription: String? {
        switch self {
        case .controllerAlreadyAttached(let id):
            return "Controller \(id) is already attached."
        case .controllerMissing(let id):
            return "Controller \(id) is not attached."
        case .unauthenticatedConnection:
            return "Input requires an authenticated connection."
        case .sessionMismatch:
            return "Input belongs to a different session."
        case .generationMismatch(let expected, let received):
            return "Input generation \(received) does not match session generation \(expected)."
        case .epochRejected(let current):
            return "Input lease epoch is stale; current epoch is \(current)."
        case .sequenceRejected(let id, let sequence):
            return "Controller \(id) sent duplicate or stale sequence \(sequence)."
        case .leaseBusy(let id):
            return "Controller \(id) still holds the primary lease."
        case .noActiveLease:
            return "No controller holds the primary lease."
        case .roleNotPermitted(let id, let role):
            return "Controller \(id) with role \(role.rawValue) cannot send this input."
        case .targetMismatch(let id):
            return "Controller \(id) sent input outside its pinned target."
        case .pinnedRoleRequiresTarget(let id):
            return "Controller \(id) requires a window or PTY target for its pinned role."
        case .preemptionNotConfirmed:
            return "Force preemption requires explicit confirmation on the requesting device."
        case .preemptionRateLimited(let id):
            return "Controller \(id) is rate-limited from another force preemption."
        case .invalidCoordinates:
            return "Input coordinates are outside the normalized desktop bounds."
        }
    }
}

final class InputLeaseManager {
    private(set) var sessionId: String = ""
    private(set) var generation: UInt64 = 0
    private(set) var leaseEpoch: UInt64 = 0
    private(set) var activeControllerId: String?
    private(set) var sharedCursor: InputPoint?
    private(set) var lastMovementFrame: PackedMovementFrame?
    private(set) var audit: [InputAuditEntry] = []

    var onLeaseChange: ((InputLeaseChange) -> Void)?

    private var attachments: [String: ControllerAttachment] = [:]
    private var localCursors: [String: InputPoint] = [:]
    private var lastSequences: [String: Int] = [:]
    private var lastMovementSequences: [String: UInt32] = [:]
    private var lastPreemptionAt: [String: Date] = [:]
    private var pressedKeys: [String: Set<String>] = [:]
    private var pressedButtons: [String: Set<UInt8>] = [:]

    func beginSession(sessionId: String, generation: UInt64, now: Date = Date()) {
        self.sessionId = sessionId
        beginGeneration(generation, now: now)
    }

    func endSession() {
        beginSession(sessionId: "", generation: 0)
    }

    func beginGeneration(_ generation: UInt64, now: Date = Date()) {
        self.generation = generation
        leaseEpoch = 0
        activeControllerId = nil
        sharedCursor = nil
        lastMovementFrame = nil
        attachments.removeAll()
        localCursors.removeAll()
        lastSequences.removeAll()
        lastMovementSequences.removeAll()
        lastPreemptionAt.removeAll()
        pressedKeys.removeAll()
        pressedButtons.removeAll()
        audit.removeAll()
        _ = now
    }

    func attach(
        controllerId: String,
        deviceId: String,
        role: ControllerRole,
        targetWindowId: String? = nil,
        targetPtyId: String? = nil,
        now: Date = Date()
    ) throws {
        guard !controllerId.isEmpty else { throw InputLeaseError.controllerMissing(controllerId) }
        guard attachments[controllerId] == nil else {
            throw InputLeaseError.controllerAlreadyAttached(controllerId)
        }
        if role == .pinnedSurfaceDriver,
           targetWindowId?.isEmpty != false,
           targetPtyId?.isEmpty != false {
            throw InputLeaseError.pinnedRoleRequiresTarget(controllerId)
        }
        attachments[controllerId] = ControllerAttachment(
            controllerId: controllerId,
            deviceId: deviceId,
            role: role,
            targetWindowId: targetWindowId,
            targetPtyId: targetPtyId,
            lastSeen: now
        )
    }

    func detach(controllerId: String, now: Date = Date()) {
        releaseAllInput(controllerId: controllerId)
        attachments.removeValue(forKey: controllerId)
        localCursors.removeValue(forKey: controllerId)
        lastSequences.removeValue(forKey: controllerId)
        lastMovementSequences.removeValue(forKey: controllerId)
        if activeControllerId == controllerId {
            _ = rotateLease(
                to: nil,
                previous: controllerId,
                reason: "controller-disconnected",
                now: now
            )
        }
    }

    @discardableResult
    func requestLease(
        controllerId: String,
        forcePreempt: Bool = false,
        confirmed: Bool = false,
        now: Date = Date()
    ) throws -> InputLeaseChange {
        guard let attachment = attachments[controllerId] else {
            throw InputLeaseError.controllerMissing(controllerId)
        }
        guard attachment.role != .pinnedSurfaceDriver else {
            throw InputLeaseError.roleNotPermitted(controllerId: controllerId, role: attachment.role)
        }
        if activeControllerId == controllerId {
            return InputLeaseChange(
                previousControllerId: controllerId,
                activeControllerId: controllerId,
                leaseEpoch: leaseEpoch,
                releasedAllInput: false,
                reason: "already-active"
            )
        }

        if let activeControllerId, let active = attachments[activeControllerId] {
            let idle = now.timeIntervalSince(active.lastSeen) > 0.5
            if forcePreempt {
                guard confirmed else {
                    record(controllerId, action: "force-preempt", accepted: false, detail: "not-confirmed", now: now)
                    throw InputLeaseError.preemptionNotConfirmed
                }
                if let last = lastPreemptionAt[controllerId],
                   now.timeIntervalSince(last) < 10 {
                    record(controllerId, action: "force-preempt", accepted: false, detail: "rate-limited", now: now)
                    throw InputLeaseError.preemptionRateLimited(controllerId)
                }
                lastPreemptionAt[controllerId] = now
            } else if !idle {
                record(controllerId, action: "request-lease", accepted: false, detail: "busy", now: now)
                throw InputLeaseError.leaseBusy(activeControllerId: activeControllerId)
            }
        }

        let previous = activeControllerId
        attachments[controllerId] = ControllerAttachment(
            controllerId: controllerId,
            deviceId: attachment.deviceId,
            role: .primaryDriver,
            targetWindowId: attachment.targetWindowId,
            targetPtyId: attachment.targetPtyId,
            lastSeen: now
        )
        if let previous, previous != controllerId, var old = attachments[previous] {
            old.role = .passiveObserver
            attachments[previous] = old
            localCursors.removeValue(forKey: previous)
        }
        record(controllerId, action: "request-lease", accepted: true, detail: "granted", now: now)
        return rotateLease(
            to: controllerId,
            previous: previous,
            reason: forcePreempt ? "force-preempt" : "request",
            now: now,
            rotateEpoch: true
        )
    }

    @discardableResult
    func releaseLease(controllerId: String, now: Date = Date()) throws -> InputLeaseChange {
        guard attachments[controllerId] != nil else {
            throw InputLeaseError.controllerMissing(controllerId)
        }
        guard activeControllerId == controllerId else {
            throw InputLeaseError.noActiveLease
        }
        record(controllerId, action: "release-lease", accepted: true, detail: "released", now: now)
        return rotateLease(
            to: nil,
            previous: controllerId,
            reason: "release",
            now: now,
            rotateEpoch: true
        )
    }

    func heartbeat(controllerId: String, now: Date = Date()) {
        guard var attachment = attachments[controllerId] else { return }
        attachment.lastSeen = now
        attachments[controllerId] = attachment
    }

    @discardableResult
    func expireLease(now: Date = Date()) -> InputLeaseChange? {
        guard let activeControllerId,
              let active = attachments[activeControllerId],
              now.timeIntervalSince(active.lastSeen) > 3 else {
            return nil
        }
        record(activeControllerId, action: "lease-expired", accepted: true, detail: "heartbeat-timeout", now: now)
        return rotateLease(
            to: nil,
            previous: activeControllerId,
            reason: "heartbeat-timeout",
            now: now,
            rotateEpoch: true
        )
    }

    func validateEdge(
        _ event: InputEvent,
        on context: InputConnectionContext,
        now: Date = Date()
    ) throws -> ValidatedInputEdge {
        guard context.authenticated else { throw InputLeaseError.unauthenticatedConnection }
        guard context.generation == generation else {
            throw InputLeaseError.generationMismatch(expected: generation, received: context.generation)
        }
        guard context.sessionId == sessionId else { throw InputLeaseError.sessionMismatch }
        guard let attachment = attachments[context.controllerId] else {
            throw InputLeaseError.controllerMissing(context.controllerId)
        }
        guard context.leaseEpoch == leaseEpoch else {
            throw InputLeaseError.epochRejected(currentEpoch: leaseEpoch)
        }
        if let last = lastSequences[context.controllerId], event.seq <= last {
            throw InputLeaseError.sequenceRejected(
                controllerId: context.controllerId,
                sequence: event.seq
            )
        }

        switch event.type {
        case .keyDown, .keyUp, .textInput, .focusChanged:
            guard attachment.role == .primaryDriver, activeControllerId == context.controllerId else {
                throw InputLeaseError.roleNotPermitted(
                    controllerId: context.controllerId,
                    role: attachment.role
                )
            }
        case .pointerDown, .pointerUp, .pointerClick, .pointerCancel, .scroll:
            guard attachment.role != .passiveObserver else {
                throw InputLeaseError.roleNotPermitted(
                    controllerId: context.controllerId,
                    role: attachment.role
                )
            }
            if attachment.role == .primaryDriver, activeControllerId != context.controllerId {
                throw InputLeaseError.roleNotPermitted(
                    controllerId: context.controllerId,
                    role: attachment.role
                )
            }
            if attachment.role == .pinnedSurfaceDriver, let target = event.target {
                let allowed = target == attachment.targetWindowId || target == attachment.targetPtyId
                guard allowed else { throw InputLeaseError.targetMismatch(controllerId: context.controllerId) }
            }
        case .pointerMove, .viewportChanged, .sessionStart, .sessionEnd:
            break
        }

        lastSequences[context.controllerId] = event.seq
        if event.type == .pointerDown, let button = event.button {
            pressedButtons[context.controllerId, default: []].insert(UInt8(clamping: button))
        } else if event.type == .pointerUp, let button = event.button {
            pressedButtons[context.controllerId]?.remove(UInt8(clamping: button))
        } else if event.type == .keyDown, let key = event.key {
            pressedKeys[context.controllerId, default: []].insert(key)
        } else if event.type == .keyUp, let key = event.key {
            pressedKeys[context.controllerId]?.remove(key)
        }
        return ValidatedInputEdge(event: event, context: context)
    }

    func acceptMovement(
        _ frame: PackedMovementFrame,
        on context: InputConnectionContext
    ) -> PackedMovementFrame? {
        guard context.authenticated,
              context.generation == generation,
              let attachment = attachments[context.controllerId],
              attachment.role != .passiveObserver,
              UInt16(truncatingIfNeeded: leaseEpoch) == frame.leaseEpochLow else {
            return nil
        }
        if let last = lastMovementSequences[context.controllerId], frame.seq <= last {
            return nil
        }
        if attachment.role == .primaryDriver, activeControllerId != context.controllerId {
            return nil
        }
        lastMovementSequences[context.controllerId] = frame.seq
        lastMovementFrame = frame
        let point = InputPoint(x: Double(frame.x), y: Double(frame.y))
        localCursors[context.controllerId] = point
        if attachment.role == .primaryDriver {
            sharedCursor = point
        }
        return frame
    }

    func moveCursor(
        controllerId: String,
        to point: InputPoint,
        epoch: UInt64
    ) throws -> InputCursorUpdate {
        guard (0...1).contains(point.x), (0...1).contains(point.y) else {
            throw InputLeaseError.invalidCoordinates
        }
        guard epoch == leaseEpoch else { throw InputLeaseError.epochRejected(currentEpoch: leaseEpoch) }
        guard let attachment = attachments[controllerId] else {
            throw InputLeaseError.controllerMissing(controllerId)
        }
        switch attachment.role {
        case .primaryDriver:
            guard activeControllerId == controllerId else {
                throw InputLeaseError.roleNotPermitted(controllerId: controllerId, role: attachment.role)
            }
            localCursors[controllerId] = point
            sharedCursor = point
            return InputCursorUpdate(controllerId: controllerId, local: point, shared: point)
        case .pinnedSurfaceDriver:
            localCursors[controllerId] = point
            return InputCursorUpdate(controllerId: controllerId, local: point, shared: nil)
        case .passiveObserver:
            throw InputLeaseError.roleNotPermitted(controllerId: controllerId, role: attachment.role)
        }
    }

    func releaseAllInput(controllerId: String) {
        pressedKeys.removeValue(forKey: controllerId)
        pressedButtons.removeValue(forKey: controllerId)
    }

    func pressedKeys(for controllerId: String) -> Set<String> {
        pressedKeys[controllerId] ?? []
    }

    func pressedButtons(for controllerId: String) -> Set<UInt8> {
        pressedButtons[controllerId] ?? []
    }

    private func rotateLease(
        to controllerId: String?,
        previous: String?,
        reason: String,
        now: Date,
        rotateEpoch: Bool = true
    ) -> InputLeaseChange {
        if rotateEpoch {
            leaseEpoch = max(leaseEpoch + 1, 1)
        }
        if let previous {
            releaseAllInput(controllerId: previous)
        }
        activeControllerId = controllerId
        if let controllerId, var attachment = attachments[controllerId] {
            attachment.lastSeen = now
            attachments[controllerId] = attachment
        }
        let change = InputLeaseChange(
            previousControllerId: previous,
            activeControllerId: controllerId,
            leaseEpoch: leaseEpoch,
            releasedAllInput: previous != nil,
            reason: reason
        )
        onLeaseChange?(change)
        return change
    }

    private func record(
        _ controllerId: String,
        action: String,
        accepted: Bool,
        detail: String,
        now: Date
    ) {
        audit.append(InputAuditEntry(
            timestamp: now,
            controllerId: controllerId,
            action: action,
            accepted: accepted,
            detail: detail
        ))
    }
}
