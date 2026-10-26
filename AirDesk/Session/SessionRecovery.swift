import Foundation

struct SessionRecovery: Equatable {
    private(set) var attempts: Int = 0
    private(set) var lastAttempt: Date?
    var maximumAttempts: Int = 4

    static func backoff(for attempt: Int) -> TimeInterval {
        let clamped = min(max(attempt, 0), 5)
        return min(0.5 * pow(2.0, Double(clamped)), 8.0)
    }

    mutating func beginAttempt(now: Date = Date()) -> TimeInterval? {
        guard attempts < maximumAttempts else { return nil }
        attempts += 1
        lastAttempt = now
        return Self.backoff(for: attempts - 1)
    }

    mutating func reset() {
        attempts = 0
        lastAttempt = nil
    }

    var canRetry: Bool {
        attempts < maximumAttempts
    }
}
