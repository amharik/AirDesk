import CoreGraphics
import Foundation
import QuartzCore

struct PointerState: Equatable, Sendable {
    private(set) var position: CGPoint
    private(set) var lastMoveTime: TimeInterval
    var sensitivity: Double
    var accelerationEnabled: Bool
    let filterEnabled: Bool
    private var filter: AdaptivePointerFilter

    init(
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        sensitivity: Double = 0.9,
        accelerationEnabled: Bool = true,
        filterEnabled: Bool = true,
        filterParameters: OneEuroFilterParameters = .pointer,
        filterBackend: CoreFeaturePath = .native
    ) {
        self.position = position
        self.sensitivity = sensitivity
        self.accelerationEnabled = accelerationEnabled
        self.filterEnabled = filterEnabled
        self.filter = AdaptivePointerFilter(backend: filterBackend, parameters: filterParameters)
        self.lastMoveTime = 0
    }

    static func == (left: PointerState, right: PointerState) -> Bool {
        left.position == right.position
            && left.lastMoveTime == right.lastMoveTime
            && left.sensitivity == right.sensitivity
            && left.accelerationEnabled == right.accelerationEnabled
            && left.filterEnabled == right.filterEnabled
            && left.filter.backend == right.filter.backend
    }

    static let baseGain: Double = 2.0
    static let minimumSensitivity: Double = 0.25
    static let maximumSensitivity: Double = 2.0

    mutating func move(delta: CGSize, viewport: CGSize, timestamp: TimeInterval = CACurrentMediaTime()) -> CGPoint {
        guard viewport.width > 0, viewport.height > 0 else { return position }
        guard delta.width.isFinite, delta.height.isFinite else { return position }

        var gain = Self.baseGain * min(max(sensitivity, Self.minimumSensitivity), Self.maximumSensitivity)

        if accelerationEnabled {
            let elapsed = max(timestamp - lastMoveTime, 1.0 / 240.0)
            let speed = hypot(delta.width, delta.height) / elapsed
            let boost = min(speed / 2200.0, 0.85) * 0.55
            gain *= 1 + boost
        }

        let nx = Double(delta.width) / Double(viewport.width) * gain
        let ny = Double(delta.height) / Double(viewport.height) * gain

        let clampedDX = min(max(nx, -0.35), 0.35)
        let clampedDY = min(max(ny, -0.35), 0.35)

        let targetX = min(max(position.x + clampedDX, 0), 1)
        let targetY = min(max(position.y + clampedDY, 0), 1)
        if filterEnabled {
            let filtered = filter.filter(
                x: Double(targetX),
                y: Double(targetY),
                timestamp: timestamp
            )
            position.x = min(max(filtered.x, 0), 1)
            position.y = min(max(filtered.y, 0), 1)
        } else {
            position.x = targetX
            position.y = targetY
        }
        lastMoveTime = timestamp
        return position
    }

    mutating func setPosition(_ point: CGPoint) {
        position = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        filter.reset()
    }

    mutating func center() {
        position = CGPoint(x: 0.5, y: 0.5)
        lastMoveTime = 0
        filter.reset()
    }

    mutating func setFilterBackend(_ backend: CoreFeaturePath) {
        filter.setBackend(backend)
    }

    var activeFilterBackend: CoreFeaturePath {
        filter.backend
    }

    static func scrollDelta(dx: Double, dy: Double, naturalScrolling: Bool) -> (Double, Double) {
        let direction = naturalScrolling ? -1.0 : 1.0
        return (dx * direction, dy * direction)
    }
}
