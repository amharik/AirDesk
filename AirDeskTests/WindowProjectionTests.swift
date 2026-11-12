import XCTest
@testable import AirDesk

@MainActor
final class WindowProjectionTests: XCTestCase {
    private let identity = WindowProjectionIdentity(
        windowId: "window-editor",
        workspaceId: "workspace-alpha",
        title: "Editor",
        hostSessionId: "session-host",
        generation: 1
    )
    private let castTarget = WindowProjectionTarget(
        targetId: "cast-studio",
        kind: .cast,
        displaySessionId: "display-cast"
    )

    func testProjectsOnHostAndRecordsSurfaceRevisions() throws {
        let registry = makeRegistry()
        let started = try projection(registry.begin(identity: identity, target: castTarget))

        XCTAssertEqual(started.state, .projecting)
        XCTAssertEqual(started.computeLocation, "host")
        XCTAssertEqual(started.surfaceRevision, 0)

        let surface = try projection(
            registry.acknowledgeSurface(windowId: identity.windowId, revision: 4)
        )
        XCTAssertEqual(surface.surfaceRevision, 4)
    }

    func testReconnectRestoresWindowIdentityOnAnotherTarget() throws {
        let registry = makeRegistry()
        _ = try projection(registry.begin(identity: identity, target: castTarget))
        _ = try projection(
            registry.acknowledgeSurface(windowId: identity.windowId, revision: 2)
        )
        let disconnected = try projection(
            registry.disconnect(windowId: identity.windowId, reason: "network")
        )
        XCTAssertEqual(disconnected.state, .reconnecting)
        XCTAssertEqual(disconnected.surfaceRevision, 2)

        let browserTarget = WindowProjectionTarget(
            targetId: "browser-laptop",
            kind: .browser,
            displaySessionId: "display-browser"
        )
        let resumed = try projection(
            registry.resume(windowId: identity.windowId, target: browserTarget, generation: 2)
        )
        XCTAssertEqual(resumed.state, .restored)
        XCTAssertEqual(resumed.identity.windowId, identity.windowId)
        XCTAssertEqual(resumed.identity.workspaceId, identity.workspaceId)
        XCTAssertEqual(resumed.identity.hostSessionId, identity.hostSessionId)
        XCTAssertEqual(resumed.identity.generation, 2)
        XCTAssertEqual(resumed.target, browserTarget)
        XCTAssertEqual(resumed.computeLocation, "host")
        XCTAssertEqual(resumed.surfaceRevision, 2)
    }

    func testRejectsDuplicateWindowsAndTargetConflicts() throws {
        let registry = makeRegistry()
        _ = try projection(registry.begin(identity: identity, target: castTarget))

        let duplicate = registry.begin(
            identity: identity,
            target: WindowProjectionTarget(
                targetId: "android-phone",
                kind: .android,
                displaySessionId: "display-android"
            )
        )
        let duplicateFailure = try failure(duplicate)
        XCTAssertEqual(duplicateFailure.code, .duplicateWindow)

        let conflict = registry.begin(
            identity: WindowProjectionIdentity(
                windowId: "window-terminal",
                workspaceId: identity.workspaceId,
                title: "Terminal",
                hostSessionId: identity.hostSessionId,
                generation: 1
            ),
            target: castTarget
        )
        let conflictFailure = try failure(conflict)
        XCTAssertEqual(conflictFailure.code, .targetConflict)
    }

    func testRejectsStaleGenerationAndRevision() throws {
        let registry = makeRegistry()
        _ = try projection(registry.begin(identity: identity, target: castTarget))
        _ = try projection(
            registry.acknowledgeSurface(windowId: identity.windowId, revision: 5)
        )

        let staleSurface = registry.acknowledgeSurface(
            windowId: identity.windowId,
            revision: 5
        )
        let staleSurfaceFailure = try failure(staleSurface)
        XCTAssertEqual(staleSurfaceFailure.code, .staleRevision)

        _ = try projection(
            registry.disconnect(windowId: identity.windowId, reason: "network")
        )
        let staleGeneration = registry.resume(
            windowId: identity.windowId,
            target: castTarget,
            generation: 0
        )
        let staleGenerationFailure = try failure(staleGeneration)
        XCTAssertEqual(staleGenerationFailure.code, .staleGeneration)
    }

    func testCastCoordinatorPublishesProjectionLifecycle() throws {
        let coordinator = CastSessionCoordinator(adapter: FakeWindowProjectionCastAdapter())
        XCTAssertTrue(coordinator.projectedWindows.isEmpty)

        _ = try projection(coordinator.beginWindowProjection(identity, to: castTarget))
        XCTAssertEqual(coordinator.projectedWindows.map(\.state), [.projecting])

        _ = try projection(
            coordinator.acknowledgeProjectedSurface(windowId: identity.windowId, revision: 3)
        )
        XCTAssertEqual(coordinator.projectedWindows.first?.surfaceRevision, 3)

        _ = try projection(
            coordinator.disconnectWindowProjection(windowId: identity.windowId, reason: "network")
        )
        XCTAssertEqual(coordinator.projectedWindows.first?.state, .reconnecting)

        _ = try projection(
            coordinator.resumeWindowProjection(
                windowId: identity.windowId,
                to: castTarget,
                generation: 2
            )
        )
        XCTAssertEqual(coordinator.projectedWindows.first?.state, .restored)

        _ = try projection(coordinator.releaseWindowProjection(windowId: identity.windowId))
        XCTAssertTrue(coordinator.projectedWindows.isEmpty)
    }

    private func makeRegistry() -> WindowProjectionRegistry {
        var now = Date(timeIntervalSince1970: 1_000)
        return WindowProjectionRegistry {
            now = now.addingTimeInterval(1)
            return now
        }
    }

    private func projection(_ result: WindowProjectionResult) throws -> WindowProjection {
        switch result {
        case .success(let projection):
            return projection
        case .failure(let failure):
            throw failure
        }
    }

    private func failure(_ result: WindowProjectionResult) throws -> WindowProjectionFailure {
        switch result {
        case .success:
            throw WindowProjectionFailure(code: .illegalState, message: "expected failure")
        case .failure(let failure):
            return failure
        }
    }
}

@MainActor
private final class FakeWindowProjectionCastAdapter: GoogleCastAdapter {
    let isAvailable = true
    let isSimulated = true
    let discoveredDevices: [CastDevice] = []
    weak var delegate: (any GoogleCastAdapterDelegate)?

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to device: CastDevice) async throws {}
    func disconnect() {}
    func send(_ event: InputEvent) {}
    func sendControl(_ message: CastControlMessage) {}
}
