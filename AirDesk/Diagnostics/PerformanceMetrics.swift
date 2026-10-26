import Foundation
import OSLog
import QuartzCore

struct MetricTransition: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let name: String
}

@MainActor
final class PerformanceMetrics: ObservableObject {
    @Published private(set) var eventsSent: Int = 0
    @Published private(set) var eventsPerSecond: Int = 0
    @Published private(set) var p50Latency: Double = 0
    @Published private(set) var p95Latency: Double = 0
    @Published private(set) var lastLatency: Double = 0
    @Published private(set) var sessionId: String = ""
    @Published private(set) var sessionStarted: Date?
    @Published private(set) var transitions: [MetricTransition] = []

    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Metrics")
    private var pending: [Int: TimeInterval] = [:]
    private var samples: [Double] = []
    private var recentSendTimes: [TimeInterval] = []
    private var timer: Timer?
    private var sentAtLastTick = 0

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func beginSession(_ id: String) {
        sessionId = id
        sessionStarted = Date()
        eventsSent = 0
        eventsPerSecond = 0
        sentAtLastTick = 0
        samples.removeAll()
        pending.removeAll()
        recentSendTimes.removeAll()
        p50Latency = 0
        p95Latency = 0
        lastLatency = 0
        transitions.removeAll()
        mark("session.begin")
    }

    func endSession() {
        mark("session.end")
        sessionStarted = nil
        pending.removeAll()
        eventsPerSecond = 0
        recentSendTimes.removeAll()
    }

    func recordSent(_ event: InputEvent) {
        eventsSent += 1
        let now = CACurrentMediaTime()
        pending[event.seq] = now
        recentSendTimes.append(now)
        if recentSendTimes.count > 240 {
            recentSendTimes.removeFirst(recentSendTimes.count - 240)
        }
        if pending.count > 240 {
            let oldest = pending.keys.sorted().prefix(pending.count - 200)
            oldest.forEach { pending.removeValue(forKey: $0) }
        }
    }

    func recordAck(seq: Int) {
        guard let sent = pending.removeValue(forKey: seq) else { return }
        let latency = (CACurrentMediaTime() - sent) * 1000
        lastLatency = latency
        samples.append(latency)
        if samples.count > 120 {
            samples.removeFirst(samples.count - 120)
        }
        updatePercentiles()
    }

    func mark(_ name: String) {
        transitions.append(MetricTransition(timestamp: Date(), name: name))
        if transitions.count > 80 {
            transitions.removeFirst(transitions.count - 80)
        }
        logger.debug("\(name, privacy: .public)")
    }

    private func tick() {
        let now = CACurrentMediaTime()
        recentSendTimes.removeAll { now - $0 > 1.0 }
        eventsPerSecond = recentSendTimes.count
    }

    private func updatePercentiles() {
        guard !samples.isEmpty else { return }
        let sorted = samples.sorted()
        p50Latency = sorted[Int(Double(sorted.count - 1) * 0.50)]
        p95Latency = sorted[Int(Double(sorted.count - 1) * 0.95)]
    }
}
