import Foundation

struct TerminalCommandRecord: Equatable, Sendable, Identifiable {
    let id: UInt64
    var phase: TerminalCommandPhase
    var startedAtSequence: UInt64
    var updatedAtSequence: UInt64
    var exitCode: Int?
}

struct TerminalCommandReplaySnapshot: Equatable, Sendable {
    var records: [TerminalCommandRecord]
    var activeRecordId: UInt64?
    var lastSequence: UInt64
}

struct TerminalCommandTimeline: Sendable {
    static let maximumRecords = 64

    private var parser = OSC133Parser()
    private var records: [TerminalCommandRecord] = []
    private var currentIndex: Int?
    private var nextIdentifier: UInt64 = 1
    private(set) var lastSequence: UInt64 = 0

    var allRecords: [TerminalCommandRecord] { records }

    var activeRecord: TerminalCommandRecord? {
        guard let currentIndex, records.indices.contains(currentIndex) else { return nil }
        let record = records[currentIndex]
        return record.phase == .finished ? nil : record
    }

    var snapshot: TerminalCommandReplaySnapshot {
        TerminalCommandReplaySnapshot(
            records: records,
            activeRecordId: activeRecord?.id,
            lastSequence: lastSequence
        )
    }

    mutating func consume(_ data: Data, sequence: UInt64) -> [TerminalCommandRecord] {
        lastSequence = max(lastSequence, sequence)
        let events = parser.consume(data)
        guard !events.isEmpty else { return [] }

        var changedIdentifiers: Set<UInt64> = []
        for event in events {
            switch event {
            case .prompt:
                if let currentIndex,
                   records.indices.contains(currentIndex),
                   records[currentIndex].phase == .prompt {
                    records[currentIndex].updatedAtSequence = sequence
                    changedIdentifiers.insert(records[currentIndex].id)
                } else {
                    startRecord(phase: .prompt, sequence: sequence)
                    if let activeRecord {
                        changedIdentifiers.insert(activeRecord.id)
                    }
                }
            case .input:
                updateCurrent(phase: .input, sequence: sequence, exitCode: nil, changed: &changedIdentifiers)
            case .running:
                updateCurrent(phase: .running, sequence: sequence, exitCode: nil, changed: &changedIdentifiers)
            case .finished(let exitCode):
                updateCurrent(phase: .finished, sequence: sequence, exitCode: exitCode, changed: &changedIdentifiers)
                currentIndex = nil
            }
        }

        return records.filter { changedIdentifiers.contains($0.id) }
    }

    private mutating func startRecord(phase: TerminalCommandPhase, sequence: UInt64) {
        let record = TerminalCommandRecord(
            id: nextIdentifier,
            phase: phase,
            startedAtSequence: sequence,
            updatedAtSequence: sequence,
            exitCode: nil
        )
        nextIdentifier &+= 1
        records.append(record)
        currentIndex = records.count - 1
        trimIfNeeded()
    }

    private mutating func updateCurrent(
        phase: TerminalCommandPhase,
        sequence: UInt64,
        exitCode: Int?,
        changed: inout Set<UInt64>
    ) {
        if currentIndex == nil {
            startRecord(phase: phase, sequence: sequence)
        }
        guard let currentIndex, records.indices.contains(currentIndex) else { return }
        records[currentIndex].phase = phase
        records[currentIndex].updatedAtSequence = sequence
        if let exitCode {
            records[currentIndex].exitCode = exitCode
        }
        changed.insert(records[currentIndex].id)
    }

    private mutating func trimIfNeeded() {
        guard records.count > Self.maximumRecords else { return }
        let overflow = records.count - Self.maximumRecords
        records.removeFirst(overflow)
        if let currentIndex {
            self.currentIndex = max(0, currentIndex - overflow)
        }
    }
}

enum PersistentTerminalEvent: Equatable, Sendable {
    case attached(oldestSequence: UInt64, truncated: Bool)
    case data(Data, sequence: UInt64)
    case command(TerminalCommandRecord)
    case detached
    case exit(code: Int32, message: String?)
    case error(String)
}

enum TerminalHandoffError: Error, Equatable, LocalizedError {
    case wrongSession
    case staleAcknowledgement
    case acknowledgementAhead
    case replayGap

    var errorDescription: String? {
        switch self {
        case .wrongSession:
            return "TerminalReplay: the frame belongs to another session."
        case .staleAcknowledgement:
            return "TerminalReplay: acknowledgements must be monotonic."
        case .acknowledgementAhead:
            return "TerminalReplay: cannot acknowledge data that was not received."
        case .replayGap:
            return "TerminalReplay: acknowledged bytes would skip missing replay data."
        }
    }
}

protocol TerminalFabricTransport: Sendable {
    func send(_ frame: TerminalFabricFrame) async throws
}

actor PersistentTerminalSession {
    let sessionId: String
    let clientId: String
    let leaseId: String

    private let transport: any TerminalFabricTransport
    private var replay = PersistentTerminalReplayState()
    private var timeline = TerminalCommandTimeline()
    private var lastReceivedSequence: UInt64 = 0
    private var lastAcknowledgedSequence: UInt64 = 0
    private var firstGapSequence: UInt64?
    private var attached = false

    init(
        sessionId: String,
        clientId: String,
        leaseId: String,
        transport: any TerminalFabricTransport
    ) {
        self.sessionId = sessionId
        self.clientId = clientId
        self.leaseId = leaseId
        self.transport = transport
    }

    var acknowledgedSequence: UInt64 { lastAcknowledgedSequence }
    var receivedSequence: UInt64 { lastReceivedSequence }
    var isAttached: Bool { attached }
    var hasReplayGap: Bool { firstGapSequence != nil }
    var activeCommand: TerminalCommandRecord? { timeline.activeRecord }
    var commandRecords: [TerminalCommandRecord] { timeline.allRecords }
    var commandSnapshot: TerminalCommandReplaySnapshot { timeline.snapshot }

    func attach(after sequence: UInt64? = nil) async throws {
        let after = sequence ?? lastAcknowledgedSequence
        let frame = TerminalFabricFrame.attach(
            sessionId: sessionId,
            clientId: clientId,
            leaseId: leaseId,
            afterSequence: after
        )
        try await transport.send(frame)
    }

    func write(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        var frame = TerminalFabricFrame.request(
            .data,
            sessionId: sessionId,
            clientId: clientId,
            leaseId: leaseId
        )
        frame.data = data
        try await transport.send(frame)
    }

    func resize(columns: UInt32, rows: UInt32) async throws {
        var frame = TerminalFabricFrame.request(
            .resize,
            sessionId: sessionId,
            clientId: clientId,
            leaseId: leaseId
        )
        frame.columns = columns
        frame.rows = rows
        try await transport.send(frame)
    }

    func detach() async throws {
        try await transport.send(
            .request(
                .detach,
                sessionId: sessionId,
                clientId: clientId,
                leaseId: leaseId
            )
        )
        attached = false
    }

    func receive(_ frame: TerminalFabricFrame) throws -> [PersistentTerminalEvent] {
        guard frame.sessionId == sessionId else { throw TerminalHandoffError.wrongSession }

        switch frame.frameType {
        case .attached:
            attached = true
            let expected = lastAcknowledgedSequence.saturatingAdd(1)
            if frame.oldestSequence > expected {
                noteGap(startingAt: expected)
            }
            _ = replay.accept(frame)
            return [
                .attached(
                    oldestSequence: frame.oldestSequence,
                    truncated: frame.truncated || hasReplayGap
                )
            ]
        case .data:
            guard frame.sequence > lastReceivedSequence else { return [] }
            noteGap(startingAt: lastReceivedSequence.saturatingAdd(1), actual: frame.sequence)
            lastReceivedSequence = frame.sequence
            _ = replay.accept(frame)
            var events: [PersistentTerminalEvent] = [
                .data(frame.data, sequence: frame.sequence)
            ]
            for record in timeline.consume(frame.data, sequence: frame.sequence) {
                events.append(.command(record))
            }
            return events
        case .detach:
            attached = false
            return [.detached]
        case .exit:
            attached = false
            return [.exit(code: frame.exitCode, message: frame.message)]
        case .error:
            return [.error(frame.message ?? "Terminal error")]
        case .attach, .resize:
            return []
        }
    }

    func acknowledge(_ sequence: UInt64) throws {
        guard sequence <= lastReceivedSequence else {
            throw TerminalHandoffError.acknowledgementAhead
        }
        guard sequence >= lastAcknowledgedSequence else {
            throw TerminalHandoffError.staleAcknowledgement
        }
        if let firstGapSequence, sequence >= firstGapSequence {
            throw TerminalHandoffError.replayGap
        }
        lastAcknowledgedSequence = sequence
    }

    func replayCommands() -> TerminalCommandReplaySnapshot {
        timeline.snapshot
    }

    private func noteGap(startingAt expected: UInt64, actual: UInt64? = nil) {
        let missingThrough = actual.map { $0 - 1 } ?? expected
        guard missingThrough >= expected else { return }
        if firstGapSequence == nil || expected < firstGapSequence! {
            firstGapSequence = expected
        }
    }
}

private extension UInt64 {
    func saturatingAdd(_ value: UInt64) -> UInt64 {
        let (result, overflow) = addingReportingOverflow(value)
        return overflow ? UInt64.max : result
    }
}
