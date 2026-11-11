import Foundation
import XCTest
@testable import AirDesk

private actor RecordingTerminalTransport: TerminalFabricTransport {
    private(set) var frames: [TerminalFabricFrame] = []

    func send(_ frame: TerminalFabricFrame) async throws {
        frames.append(frame)
    }

    func sentFrames() -> [TerminalFabricFrame] {
        frames
    }
}

final class RemoteSSHReattachTests: XCTestCase {
    func testCommandTimelineTracksActiveRecordAndExitCode() {
        var timeline = TerminalCommandTimeline()

        timeline.consume(Data("\u{1B}]133;A\u{07}".utf8), sequence: 1)
        XCTAssertEqual(timeline.activeRecord?.phase, .prompt)

        timeline.consume(Data("\u{1B}]133;B\u{07}".utf8), sequence: 2)
        XCTAssertEqual(timeline.activeRecord?.phase, .input)

        timeline.consume(Data("\u{1B}]133;C\u{1B}\\".utf8), sequence: 3)
        XCTAssertEqual(timeline.activeRecord?.phase, .running)

        let changed = timeline.consume(Data("\u{1B}]133;D;7\u{07}".utf8), sequence: 4)
        XCTAssertEqual(changed.last?.phase, .finished)
        XCTAssertEqual(changed.last?.exitCode, 7)
        XCTAssertNil(timeline.activeRecord)

        let snapshot = timeline.snapshot
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.startedAtSequence, 1)
        XCTAssertEqual(snapshot.records.first?.updatedAtSequence, 4)
        XCTAssertNil(snapshot.activeRecordId)
        XCTAssertEqual(snapshot.lastSequence, 4)

        timeline.consume(Data("\u{1B}]133;A\u{07}".utf8), sequence: 5)
        XCTAssertEqual(timeline.activeRecord?.phase, .prompt)
        XCTAssertEqual(timeline.snapshot.records.count, 2)
    }

    func testSessionReattachesFromLastAcknowledgedSequenceWithoutDuplicates() async throws {
        let transport = RecordingTerminalTransport()
        let session = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1",
            transport: transport
        )

        try await session.attach()
        var sent = await transport.sentFrames()
        XCTAssertEqual(sent.first?.frameType, .attach)
        XCTAssertEqual(sent.first?.replayFromSequence, 0)

        var events = try await session.receive(
            TerminalFabricFrame(frameType: .attached, sessionId: "session-1", oldestSequence: 1)
        )
        XCTAssertEqual(events, [.attached(oldestSequence: 1, truncated: false)])

        events = try await session.receive(
            TerminalFabricFrame(
                frameType: .data,
                sessionId: "session-1",
                sequence: 1,
                data: Data("one".utf8)
            )
        )
        XCTAssertEqual(events, [.data(Data("one".utf8), sequence: 1)])
        try await session.acknowledge(1)

        events = try await session.receive(
            TerminalFabricFrame(
                frameType: .data,
                sessionId: "session-1",
                sequence: 2,
                data: Data("two".utf8)
            )
        )
        XCTAssertEqual(events, [.data(Data("two".utf8), sequence: 2)])
        try await session.acknowledge(2)

        events = try await session.receive(
            TerminalFabricFrame(
                frameType: .data,
                sessionId: "session-1",
                sequence: 2,
                data: Data("duplicate".utf8)
            )
        )
        XCTAssertTrue(events.isEmpty)

        try await session.attach()
        sent = await transport.sentFrames()
        XCTAssertEqual(sent.last?.frameType, .attach)
        XCTAssertEqual(sent.last?.replayFromSequence, 2)

        let acknowledged = await session.acknowledgedSequence
        let received = await session.receivedSequence
        XCTAssertEqual(acknowledged, 2)
        XCTAssertEqual(received, 2)
    }

    func testSecondClientKeepsIndependentAcknowledgementAndReplayCursor() async throws {
        let firstTransport = RecordingTerminalTransport()
        let secondTransport = RecordingTerminalTransport()
        let first = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "first",
            leaseId: "lease-1",
            transport: firstTransport
        )
        let second = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "second",
            leaseId: "lease-1",
            transport: secondTransport
        )

        try await first.attach()
        try await second.attach()
        let attached = TerminalFabricFrame(
            frameType: .attached,
            sessionId: "session-1",
            oldestSequence: 1
        )
        let data = TerminalFabricFrame(
            frameType: .data,
            sessionId: "session-1",
            sequence: 1,
            data: Data("shared".utf8)
        )
        _ = try await first.receive(attached)
        _ = try await second.receive(attached)
        _ = try await first.receive(data)
        _ = try await second.receive(data)

        try await first.acknowledge(1)
        try await second.attach()
        let secondSent = await secondTransport.sentFrames()
        XCTAssertEqual(secondSent.last?.replayFromSequence, 0)
        XCTAssertEqual(secondSent.last?.clientId, "second")

        try await second.acknowledge(1)
        try await second.attach()
        let reattached = await secondTransport.sentFrames()
        XCTAssertEqual(reattached.last?.replayFromSequence, 1)
        let firstAcknowledged = await first.acknowledgedSequence
        XCTAssertEqual(firstAcknowledged, 1)
    }

    func testTruncatedReplayCannotAcknowledgeAcrossGap() async throws {
        let transport = RecordingTerminalTransport()
        let session = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1",
            transport: transport
        )

        try await session.attach()
        _ = try await session.receive(
            TerminalFabricFrame(
                frameType: .attached,
                sessionId: "session-1",
                oldestSequence: 5,
                truncated: true
            )
        )
        _ = try await session.receive(
            TerminalFabricFrame(
                frameType: .data,
                sessionId: "session-1",
                sequence: 5,
                data: Data("after-gap".utf8)
            )
        )

        let hasGap = await session.hasReplayGap
        XCTAssertTrue(hasGap)
        do {
            try await session.acknowledge(5)
            XCTFail("Expected a replay-gap acknowledgement failure")
        } catch {
            XCTAssertEqual(error as? TerminalHandoffError, .replayGap)
        }
        try await session.acknowledge(0)
    }

    func testCommandRecordsAreSeparateFromTerminalBytes() async throws {
        let transport = RecordingTerminalTransport()
        let session = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1",
            transport: transport
        )

        let bytes = Data("\u{1B}]133;A\u{07}$ \u{1B}]133;B\u{07}ls\r\u{1B}]133;C\u{1B}\\output".utf8)
        let events = try await session.receive(
            TerminalFabricFrame(
                frameType: .data,
                sessionId: "session-1",
                sequence: 1,
                data: bytes
            )
        )

        XCTAssertEqual(events.first, .data(bytes, sequence: 1))
        XCTAssertTrue(events.dropFirst().contains { event in
            if case .command(let record) = event {
                return record.phase == .running
            }
            return false
        })
        let snapshot = await session.replayCommands()
        XCTAssertEqual(snapshot.activeRecordId, 1)
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.phase, .running)
    }

    func testReconnectPreservesActiveCommandWithoutSyntheticTerminalData() async throws {
        let transport = RecordingTerminalTransport()
        let session = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1",
            transport: transport
        )

        let bytes = Data("\u{1B}]133;A\u{07}prompt\u{1B}]133;B\u{07}vim\r\u{1B}]133;C\u{1B}\\".utf8)
        _ = try await session.receive(
            TerminalFabricFrame(
                frameType: .data,
                sessionId: "session-1",
                sequence: 1,
                data: bytes
            )
        )
        try await session.acknowledge(1)

        try await session.attach()
        let sent = await transport.sentFrames()
        XCTAssertEqual(sent.last?.frameType, .attach)
        XCTAssertEqual(sent.last?.replayFromSequence, 1)

        let snapshot = await session.commandSnapshot
        XCTAssertEqual(snapshot.activeRecordId, 1)
        XCTAssertEqual(snapshot.records.first?.phase, .running)
        let active = await session.activeCommand
        XCTAssertEqual(active?.id, 1)
    }

    func testWrongSessionIsRejected() async throws {
        let session = PersistentTerminalSession(
            sessionId: "session-1",
            clientId: "client-1",
            leaseId: "lease-1",
            transport: RecordingTerminalTransport()
        )

        do {
            _ = try await session.receive(
                TerminalFabricFrame(frameType: .attached, sessionId: "other")
            )
            XCTFail("Expected a wrong-session failure")
        } catch {
            XCTAssertEqual(error as? TerminalHandoffError, .wrongSession)
        }
    }
}
