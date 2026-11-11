import CoreGraphics
import Foundation

enum CursorShape: String, Codable, CaseIterable, Sendable {
    case arrow
    case iBeam = "i-beam"
    case pointingHand = "pointing-hand"
    case resizeHorizontal = "resize-horizontal"
    case resizeVertical = "resize-vertical"
    case resizeDiagonal = "resize-diagonal"
    case move
    case notAllowed = "not-allowed"
    case hidden

    var systemImage: String {
        switch self {
        case .arrow: return "cursorarrow"
        case .iBeam: return "text.cursor"
        case .pointingHand: return "hand.point.up.left.fill"
        case .resizeHorizontal: return "arrow.left.and.right"
        case .resizeVertical: return "arrow.up.and.down"
        case .resizeDiagonal: return "arrow.up.left.and.arrow.down.right"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .notAllowed: return "nosign"
        case .hidden: return "cursorarrow"
        }
    }

    var nominalSize: CGFloat {
        switch self {
        case .iBeam: return 22
        case .pointingHand: return 24
        case .resizeHorizontal, .resizeVertical, .resizeDiagonal, .move: return 20
        case .notAllowed: return 22
        case .arrow, .hidden: return 22
        }
    }

    var defaultHotspot: CGPoint {
        switch self {
        case .iBeam: return CGPoint(x: 0.5, y: 0.5)
        case .pointingHand: return CGPoint(x: 0.18, y: 0.12)
        case .resizeHorizontal, .resizeVertical, .resizeDiagonal, .move: return CGPoint(x: 0.5, y: 0.5)
        case .notAllowed: return CGPoint(x: 0.5, y: 0.5)
        case .arrow, .hidden: return CGPoint(x: 0.22, y: 0.16)
        }
    }
}

enum CursorMetadataError: Error, Equatable, LocalizedError {
    case unsupportedVersion
    case invalidSession
    case invalidGeneration
    case invalidSequence
    case invalidHotspot
    case hiddenCursorMustNotBeVisible
    case sessionMismatch
    case generationMismatch
    case staleSequence

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Unsupported cursor metadata version."
        case .invalidSession: return "Invalid cursor metadata session."
        case .invalidGeneration: return "Invalid cursor metadata generation."
        case .invalidSequence: return "Invalid cursor metadata sequence."
        case .invalidHotspot: return "Cursor hotspot must be normalized."
        case .hiddenCursorMustNotBeVisible: return "A hidden cursor cannot be marked visible."
        case .sessionMismatch: return "Cursor metadata belongs to another session."
        case .generationMismatch: return "Cursor metadata belongs to another generation."
        case .staleSequence: return "Cursor metadata is stale."
        }
    }
}

struct CursorMetadata: Codable, Equatable, Sendable {
    var version: Int = 1
    var sessionId: String
    var generation: Int
    var seq: Int
    var shape: CursorShape
    var hotspotX: Double
    var hotspotY: Double
    var visible: Bool

    func validated(
        expectedSessionId: String? = nil,
        expectedGeneration: Int? = nil,
        afterSequence: Int? = nil
    ) throws -> CursorMetadata {
        guard version == 1 else { throw CursorMetadataError.unsupportedVersion }
        guard !sessionId.isEmpty, sessionId.count <= 64, !sessionId.contains("\u{0000}") else {
            throw CursorMetadataError.invalidSession
        }
        guard generation >= 0, generation <= Int(Int32.max) else {
            throw CursorMetadataError.invalidGeneration
        }
        guard seq >= 0, seq <= Int(Int32.max) else {
            throw CursorMetadataError.invalidSequence
        }
        guard hotspotX.isFinite, hotspotY.isFinite,
              (0...1).contains(hotspotX), (0...1).contains(hotspotY) else {
            throw CursorMetadataError.invalidHotspot
        }
        guard !(shape == .hidden && visible) else {
            throw CursorMetadataError.hiddenCursorMustNotBeVisible
        }
        if let expectedSessionId, sessionId != expectedSessionId {
            throw CursorMetadataError.sessionMismatch
        }
        if let expectedGeneration, generation != expectedGeneration {
            throw CursorMetadataError.generationMismatch
        }
        if let afterSequence, seq < afterSequence {
            throw CursorMetadataError.staleSequence
        }
        return self
    }

    func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorMetadataError.invalidSession
        }
        return object
    }

    static func decode(from object: [String: Any]) throws -> CursorMetadata {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(CursorMetadata.self, from: data)
    }
}

struct LocalCursorSnapshot: Equatable, Sendable {
    var point: CGPoint
    var shape: CursorShape
    var hotspot: CGPoint
    var isVisible: Bool
}

struct LocalCursorFrameClock: Sendable {
    let minimumInterval: TimeInterval
    private var lastSample: TimeInterval?

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    mutating func reset() {
        lastSample = nil
    }

    mutating func shouldSample(at time: TimeInterval) -> Bool {
        guard time.isFinite else { return false }
        if let lastSample, time - lastSample < minimumInterval {
            return false
        }
        lastSample = time
        return true
    }
}

@MainActor
final class LocalCursorPresentation: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var localCursorEnabled = false
    @Published private(set) var shape: CursorShape = .arrow
    @Published private(set) var hotspot: CGPoint = CursorShape.arrow.defaultHotspot
    @Published private(set) var isRemoteCursorVisible = false
    @Published private(set) var isHostCursorSuppressed = false

    var onHostCursorVisibleChanged: ((Bool) -> Void)?

    private(set) var target: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var renderedPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var frameClock: LocalCursorFrameClock
    private var sessionId = ""
    private var generation = 0
    private var lastMetadataSequence = -1

    init(frameInterval: TimeInterval = 1.0 / 120.0) {
        frameClock = LocalCursorFrameClock(minimumInterval: frameInterval)
    }

    func start(
        sessionId: String,
        generation: Int = 0,
        localCursorEnabled: Bool = true
    ) {
        guard !sessionId.isEmpty, sessionId.count <= 64 else { return }
        if isActive, self.sessionId == sessionId {
            setLocalCursorEnabled(localCursorEnabled)
            return
        }
        if isActive {
            end()
        }

        self.sessionId = sessionId
        self.generation = generation
        lastMetadataSequence = -1
        target = CGPoint(x: 0.5, y: 0.5)
        renderedPoint = target
        shape = .arrow
        hotspot = CursorShape.arrow.defaultHotspot
        isRemoteCursorVisible = false
        isActive = true
        frameClock.reset()
        setLocalCursorEnabled(localCursorEnabled)
    }

    func setLocalCursorEnabled(_ enabled: Bool) {
        let shouldSuppressHost = isActive && enabled
        guard localCursorEnabled != enabled || (enabled && !isHostCursorSuppressed) else {
            return
        }
        localCursorEnabled = enabled
        isRemoteCursorVisible = false
        updateHostSuppression(shouldSuppressHost)
    }

    func move(to point: CGPoint) {
        guard isActive else { return }
        target = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    func frame(at time: TimeInterval) -> LocalCursorSnapshot? {
        guard isActive, localCursorEnabled else { return nil }
        guard frameClock.shouldSample(at: time) else { return nil }
        renderedPoint = target
        return LocalCursorSnapshot(
            point: renderedPoint,
            shape: shape,
            hotspot: hotspot,
            isVisible: true
        )
    }

    @discardableResult
    func apply(_ metadata: CursorMetadata) throws -> Bool {
        let checked = try metadata.validated(
            expectedSessionId: sessionId,
            expectedGeneration: generation,
            afterSequence: lastMetadataSequence
        )
        lastMetadataSequence = checked.seq
        shape = checked.shape
        hotspot = CGPoint(x: checked.hotspotX, y: checked.hotspotY)
        isRemoteCursorVisible = checked.visible && !localCursorEnabled
        return isRemoteCursorVisible
    }

    func end() {
        guard isActive else { return }
        isActive = false
        localCursorEnabled = false
        isRemoteCursorVisible = false
        target = CGPoint(x: 0.5, y: 0.5)
        renderedPoint = target
        frameClock.reset()
        lastMetadataSequence = -1
        updateHostSuppression(false)
    }

    private func updateHostSuppression(_ suppressed: Bool) {
        guard isHostCursorSuppressed != suppressed else { return }
        isHostCursorSuppressed = suppressed
        onHostCursorVisibleChanged?(!suppressed)
    }
}
