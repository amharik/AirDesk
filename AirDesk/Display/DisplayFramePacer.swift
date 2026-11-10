import Foundation
import QuartzCore
import UIKit

struct DisplayFramePacingConfiguration: Equatable, Sendable {
    static let standard = DisplayFramePacingConfiguration()

    var targetFramesPerSecond: Int = 60
    var maximumQueuedFrames: Int = 2
    var maximumFrameAgeSeconds: Double = 0.25

    func validate() throws {
        guard (1...240).contains(targetFramesPerSecond) else {
            throw DisplayFramePacingError.invalidConfiguration(
                "targetFramesPerSecond"
            )
        }
        guard (1...8).contains(maximumQueuedFrames) else {
            throw DisplayFramePacingError.invalidConfiguration(
                "maximumQueuedFrames"
            )
        }
        guard maximumFrameAgeSeconds.isFinite,
              (0.016...5).contains(maximumFrameAgeSeconds) else {
            throw DisplayFramePacingError.invalidConfiguration(
                "maximumFrameAgeSeconds"
            )
        }
    }

    var minimumPresentationInterval: TimeInterval {
        1 / Double(targetFramesPerSecond)
    }
}

enum DisplayFramePacingError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            return "The display frame pacing configuration is invalid: \(field)."
        }
    }
}

struct DisplayFramePacingMetrics: Equatable, Sendable {
    var receivedFrames = 0
    var presentedFrames = 0
    var droppedFrames = 0
    var overflowDrops = 0
    var lateFrames = 0
    var currentQueueDepth = 0
    var maximumQueueDepth = 0
    var lastPresentationIntervalSeconds: Double = 0
    var totalQueueDelaySeconds: Double = 0
    var peakQueueDelaySeconds: Double = 0

    var averageQueueDelayMilliseconds: Double {
        guard presentedFrames > 0 else { return 0 }
        return totalQueueDelaySeconds / Double(presentedFrames) * 1_000
    }

    var droppedFrameRatio: Double {
        guard receivedFrames > 0 else { return 0 }
        return Double(droppedFrames) / Double(receivedFrames)
    }
}

final class DisplayFramePacer {
    let configuration: DisplayFramePacingConfiguration

    private struct QueuedFrame {
        let frame: DecodedDisplayFrame
        let enqueuedAtSeconds: Double
    }

    private let lock = NSLock()
    private var queue: [QueuedFrame] = []
    private var lastPresentationTime: TimeInterval?
    private var _metrics = DisplayFramePacingMetrics()

    init(configuration: DisplayFramePacingConfiguration = .standard) throws {
        try configuration.validate()
        self.configuration = configuration
    }

    var metrics: DisplayFramePacingMetrics {
        lock.withLock { _metrics }
    }

    @discardableResult
    func enqueue(
        _ frame: DecodedDisplayFrame,
        receivedAt seconds: TimeInterval
    ) -> Bool {
        guard seconds.isFinite else { return false }

        lock.lock()
        _metrics.receivedFrames += 1
        if queue.count >= configuration.maximumQueuedFrames {
            queue.removeFirst()
            _metrics.droppedFrames += 1
            _metrics.overflowDrops += 1
        }
        queue.append(QueuedFrame(frame: frame, enqueuedAtSeconds: seconds))
        _metrics.currentQueueDepth = queue.count
        _metrics.maximumQueueDepth = max(
            _metrics.maximumQueueDepth,
            queue.count
        )
        lock.unlock()
        return true
    }

    func presentFrameIfAvailable(
        at now: TimeInterval
    ) -> DecodedDisplayFrame? {
        guard now.isFinite else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if let lastPresentationTime,
           now - lastPresentationTime < configuration.minimumPresentationInterval
            - 0.001 {
            return nil
        }

        while let first = queue.first,
              now - first.enqueuedAtSeconds > configuration.maximumFrameAgeSeconds {
            queue.removeFirst()
            _metrics.droppedFrames += 1
            _metrics.lateFrames += 1
        }

        guard !queue.isEmpty else {
            _metrics.currentQueueDepth = 0
            return nil
        }

        let queued = queue.removeFirst()
        if let lastPresentationTime {
            _metrics.lastPresentationIntervalSeconds = max(
                0,
                now - lastPresentationTime
            )
        }
        lastPresentationTime = now
        _metrics.presentedFrames += 1
        _metrics.currentQueueDepth = queue.count
        let delay = max(0, now - queued.enqueuedAtSeconds)
        _metrics.totalQueueDelaySeconds += delay
        _metrics.peakQueueDelaySeconds = max(
            _metrics.peakQueueDelaySeconds,
            delay
        )
        return queued.frame
    }

    func removeAll() {
        lock.withLock {
            queue.removeAll(keepingCapacity: false)
            _metrics.currentQueueDepth = 0
        }
    }
}

@MainActor
final class DisplayFramePacingDriver {
    let pacer: DisplayFramePacer
    var onPresent: ((DecodedDisplayFrame) -> Void)?

    private var displayLink: CADisplayLink?

    init(pacer: DisplayFramePacer) {
        self.pacer = pacer
    }

    deinit {
        displayLink?.invalidate()
    }

    func start(screen: UIScreen? = nil) {
        stop()
        let screen = screen ?? UIScreen.main
        let target = min(
            pacer.configuration.targetFramesPerSecond,
            max(1, screen.maximumFramesPerSecond)
        )
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(handleDisplayLink(_:))
        )
        displayLink.preferredFramesPerSecond = target
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayLink(_ displayLink: CADisplayLink) {
        let now = displayLink.timestamp > 0
            ? displayLink.timestamp
            : CACurrentMediaTime()
        guard let frame = pacer.presentFrameIfAvailable(at: now) else {
            return
        }
        onPresent?(frame)
    }
}
