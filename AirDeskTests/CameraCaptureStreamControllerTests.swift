import XCTest
@testable import AirDesk

@MainActor
final class CameraCaptureStreamControllerTests: XCTestCase {
    func testStartRequiresDeviceAgentAuthorization() async throws {
        let agent = try makeAgent(authorization: .denied)
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(agent: agent, source: source)

        do {
            try await controller.start(request: makeRequest())
            XCTFail("Expected camera capture authorization to be denied")
        } catch {
            XCTAssertEqual(error as? CameraCaptureError, .authorizationDenied)
        }

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(source.startCount, 0)
        XCTAssertTrue(agent.activeLeases().isEmpty)
    }

    func testStartRequiresPlatformPermissionAndReleasesLease() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        source.permissionStatus = .denied
        let controller = CameraCaptureStreamController(agent: agent, source: source)

        do {
            try await controller.start(request: makeRequest())
            XCTFail("Expected camera permission to be denied")
        } catch {
            XCTAssertEqual(
                error as? CameraCaptureError,
                .permissionDenied(CapabilityCatalog.cameraPermission)
            )
        }

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(source.startCount, 0)
        XCTAssertTrue(agent.activeLeases().isEmpty)
    }

    func testStreamsFramesAndStopsCleanly() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(agent: agent, source: source)
        var iterator = controller.frames.makeAsyncIterator()

        try await controller.start(request: makeRequest())

        XCTAssertEqual(controller.state, .running)
        XCTAssertEqual(agent.activeLeases().count, 1)
        XCTAssertEqual(controller.activeLease?.operations, ["capture"])

        source.emit(makeFrame(sequence: 1, byteCount: 8))
        let frame = try await iterator.next()
        XCTAssertEqual(frame?.sequence, 1)
        XCTAssertEqual(frame?.bytes, Data(repeating: 0, count: 8))
        XCTAssertEqual(controller.metrics.receivedFrames, 1)
        XCTAssertEqual(controller.metrics.admittedFrames, 1)

        await controller.stop()

        XCTAssertEqual(controller.state, .stopped)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertTrue(agent.activeLeases().isEmpty)
        let end = try await iterator.next()
        XCTAssertNil(end)
    }

    func testBackpressureDropsFramesBeyondBufferLimit() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(
            agent: agent,
            source: source,
            maxBufferedFrames: 2
        )

        try await controller.start(request: makeRequest())
        for sequence in 1...5 {
            source.emit(makeFrame(sequence: UInt64(sequence)))
        }

        XCTAssertEqual(controller.metrics.receivedFrames, 5)
        XCTAssertEqual(controller.metrics.admittedFrames, 2)
        XCTAssertEqual(controller.metrics.droppedFrames, 3)

        await controller.stop()
    }

    func testCancellationIsTypedAndStopsSource() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(agent: agent, source: source)
        var iterator = controller.frames.makeAsyncIterator()

        try await controller.start(request: makeRequest())
        await controller.cancel()

        XCTAssertEqual(controller.state, .cancelled)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertTrue(agent.activeLeases().isEmpty)

        do {
            _ = try await iterator.next()
            XCTFail("Expected cancellation to terminate the frame stream")
        } catch {
            XCTAssertEqual(error as? CameraCaptureError, .cancelled)
        }
    }

    func testCancellationDiscardsBufferedFrames() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(agent: agent, source: source)

        try await controller.start(request: makeRequest())
        source.emit(makeFrame(sequence: 1))
        source.emit(makeFrame(sequence: 2))
        await controller.cancel()

        var iterator = controller.frames.makeAsyncIterator()
        do {
            let frame = try await iterator.next()
            XCTFail("Expected buffered frames to be discarded, received \(String(describing: frame))")
        } catch {
            XCTAssertEqual(error as? CameraCaptureError, .cancelled)
        }
    }

    func testRevocationDuringStreamFailsTyped() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(agent: agent, source: source)
        var iterator = controller.frames.makeAsyncIterator()

        try await controller.start(request: makeRequest())
        agent.disconnect()
        await drainTasks()

        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertTrue(agent.activeLeases().isEmpty)

        do {
            _ = try await iterator.next()
            XCTFail("Expected revoked authorization to terminate the frame stream")
        } catch {
            XCTAssertEqual(error as? CameraCaptureError, .authorizationRevoked)
        }
    }

    func testLeaseExpiryDuringStreamFailsTyped() async throws {
        let clock = MutableClock(value: 1_000_000)
        let agent = try makeAgent(nowMillis: { clock.value })
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(
            agent: agent,
            source: source,
            nowMillis: { clock.value }
        )
        var iterator = controller.frames.makeAsyncIterator()

        try await controller.start(request: makeRequest())
        let lease = try XCTUnwrap(controller.activeLease)
        clock.value = lease.expiresAtEpochMillis

        source.emit(makeFrame(sequence: 1))
        await drainTasks()

        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(controller.metrics.admittedFrames, 0)
        XCTAssertTrue(agent.activeLeases().isEmpty)

        do {
            _ = try await iterator.next()
            XCTFail("Expected the expired lease to terminate the frame stream")
        } catch {
            XCTAssertEqual(error as? CameraCaptureError, .leaseExpired)
        }
    }

    func testOversizedFramesAreDroppedAndCounted() async throws {
        let agent = try makeAgent()
        let source = FakeCameraCaptureSource()
        let controller = CameraCaptureStreamController(agent: agent, source: source)
        let configuration = CameraCaptureConfiguration(
            width: 1,
            height: 1,
            framesPerSecond: 30,
            maximumFrameBytes: 8
        )

        try await controller.start(request: makeRequest(), configuration: configuration)
        source.emit(makeFrame(sequence: 1, byteCount: 9))
        source.emit(makeFrame(sequence: 2, byteCount: 8))

        XCTAssertEqual(controller.metrics.receivedFrames, 2)
        XCTAssertEqual(controller.metrics.oversizedFrames, 1)
        XCTAssertEqual(controller.metrics.admittedFrames, 1)
        XCTAssertEqual(controller.metrics.droppedFrames, 0)

        await controller.stop()
    }

    private func makeAgent(
        authorization: CapabilityAuthorization = .granted,
        availability: CapabilityAvailability = .available,
        permission: DeviceAgentPlatformPermissionState = .granted,
        nowMillis: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        }
    ) throws -> DeviceAgent {
        let capability = DeviceAgentCapability(
            capUri: CapabilityCatalog.cameraCapUri,
            version: 1,
            providerDeviceId: "ad-device:test",
            operations: ["capture", "stop"],
            permissions: [CapabilityCatalog.cameraPermission],
            execution: "on-device-capture",
            transport: "none",
            constraints: #"{"streaming":true,"remoteInvocation":false}"#,
            availability: availability,
            authorization: authorization,
            label: "Camera capture",
            summary: "Camera capture for tests.",
            note: "Test camera capability.",
            authorizationRef: "grant-camera"
        )
        let identity = DeviceAgentIdentity(
            deviceId: "ad-device:test",
            displayName: "Test device",
            platform: "ios",
            algorithm: "ed25519",
            publicKeySpkiBase64Url: "test-key",
            createdAtEpochMillis: 0
        )
        let agent = try DeviceAgent(
            identity: identity,
            capabilities: [capability],
            permissions: [CapabilityCatalog.cameraPermission: permission],
            leaseDurationMillis: 60_000,
            now: nowMillis
        )
        agent.start()
        return agent
    }

    private func makeRequest(
        operations: [String] = ["capture"]
    ) -> DeviceAgentCapabilityRequest {
        DeviceAgentCapabilityRequest(
            capUri: CapabilityCatalog.cameraCapUri,
            operations: operations,
            workspaceId: "workspace.local",
            applicationId: "app.camera",
            requesterDeviceId: "ad-device:controller-1",
            sessionId: "session-1",
            leaseId: "lease-camera-1",
            auditId: "audit-camera-1"
        )
    }

    private func makeFrame(sequence: UInt64, byteCount: Int = 4) -> CameraFrame {
        CameraFrame(
            sequence: sequence,
            timestampSeconds: Double(sequence),
            width: 1,
            height: 1,
            pixelFormat: 32,
            bytes: Data(repeating: 0, count: byteCount)
        )
    }

    private func drainTasks() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}

private final class MutableClock {
    var value: Int64

    init(value: Int64) {
        self.value = value
    }
}

@MainActor
private final class FakeCameraCaptureSource: CameraCaptureSource {
    var isAvailable = true
    var permissionStatus: CameraPermissionStatus = .authorized
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configuration: CameraCaptureConfiguration?
    private var onFrame: (@MainActor (CameraFrame) -> Void)?

    func start(
        configuration: CameraCaptureConfiguration,
        onFrame: @escaping @MainActor (CameraFrame) -> Void
    ) async throws {
        startCount += 1
        if let startError {
            throw startError
        }
        self.configuration = configuration
        self.onFrame = onFrame
    }

    func stop() async {
        stopCount += 1
        onFrame = nil
    }

    func emit(_ frame: CameraFrame) {
        onFrame?(frame)
    }
}
