import CoreVideo
import XCTest
@testable import AirDesk

final class ScreenCapturePipelineTests: XCTestCase {
    private let capabilities = DisplayVideoCapabilities(
        hevcEncodeSupported: true,
        h264EncodeSupported: true,
        av1EncodeSupported: false
    )

    func testStartsStreamsEncodedFramesAndStops() async throws {
        let source = MockDisplayCaptureSource()
        let encoder = MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        let pipeline = makePipeline(source: source, encoder: encoder)
        var encoded: [EncodedDisplayFrame] = []
        pipeline.onEncodedFrame = { encoded.append($0) }

        try await pipeline.start(configuration: configuration())
        XCTAssertEqual(pipeline.state, .running)
        XCTAssertEqual(pipeline.selectedCodec, .hevc)

        source.emit(sequence: 1)
        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded.first?.sequence, 1)
        XCTAssertTrue(encoded.first?.isKeyframe == true)
        XCTAssertEqual(pipeline.metrics.receivedFrames, 1)
        XCTAssertEqual(pipeline.metrics.encodedFrames, 1)
        XCTAssertEqual(pipeline.metrics.keyframes, 1)
        XCTAssertEqual(pipeline.metrics.inFlightFrames, 0)

        await pipeline.stop()
        XCTAssertEqual(pipeline.state, .stopped)
        XCTAssertEqual(source.stopCount, 1)
        XCTAssertEqual(encoder.finishCount, 1)
    }

    func testBackpressureDropsFramesAndForcesRecoveryKeyframe() async throws {
        let source = MockDisplayCaptureSource()
        let encoder = MockDisplayVideoEncoder(codec: .hevc, autoComplete: false)
        let pipeline = makePipeline(source: source, encoder: encoder)

        try await pipeline.start(configuration: configuration(maxInFlightFrames: 1))
        source.emit(sequence: 1)
        XCTAssertEqual(encoder.encoded.count, 1)
        XCTAssertEqual(pipeline.metrics.inFlightFrames, 1)

        source.emit(sequence: 2)
        XCTAssertEqual(encoder.encoded.count, 1)
        XCTAssertEqual(pipeline.metrics.droppedFrames, 1)

        encoder.completeNext(isKeyframe: false)
        source.emit(sequence: 3)
        XCTAssertEqual(encoder.encoded.count, 2)
        XCTAssertEqual(encoder.encoded.last?.forceKeyframe, true)
        XCTAssertEqual(pipeline.metrics.droppedFrames, 1)
        XCTAssertEqual(pipeline.metrics.encodedFrames, 1)
    }

    func testKeyframeIntervalRequestsPeriodicKeyframes() async throws {
        let source = MockDisplayCaptureSource()
        let encoder = MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        let pipeline = makePipeline(source: source, encoder: encoder)

        try await pipeline.start(configuration: configuration(keyframeIntervalFrames: 2))
        source.emit(sequence: 1)
        source.emit(sequence: 2)
        source.emit(sequence: 3)

        XCTAssertEqual(encoder.encoded.map(\.forceKeyframe), [true, false, true])
        XCTAssertEqual(pipeline.metrics.encodedFrames, 3)
        XCTAssertEqual(pipeline.metrics.keyframes, 2)
    }

    func testFallsBackToH264WhenHEVCIsUnavailable() async throws {
        let source = MockDisplayCaptureSource()
        var requestedCodec: DisplayVideoCodec?
        let pipeline = ScreenCapturePipeline(
            source: source,
            capabilities: DisplayVideoCapabilities(
                hevcEncodeSupported: false,
                h264EncodeSupported: true,
                av1EncodeSupported: false
            ),
            encoderFactory: { codec, _, _, _ in
                requestedCodec = codec
                return MockDisplayVideoEncoder(codec: codec, autoComplete: true)
            }
        )

        try await pipeline.start(configuration: configuration())
        source.emit(sequence: 1)

        XCTAssertEqual(pipeline.selectedCodec, .h264)
        XCTAssertEqual(requestedCodec, .h264)
        XCTAssertEqual(pipeline.metrics.encodedFrames, 1)
    }

    func testAV1DetectionDoesNotSelectAV1Encoder() async throws {
        let source = MockDisplayCaptureSource()
        let pipeline = ScreenCapturePipeline(
            source: source,
            capabilities: DisplayVideoCapabilities(
                hevcEncodeSupported: false,
                h264EncodeSupported: true,
                av1EncodeSupported: true
            ),
            encoderFactory: { codec, _, _, _ in
                MockDisplayVideoEncoder(codec: codec, autoComplete: true)
            }
        )

        try await pipeline.start(
            configuration: configuration(preferredCodec: .av1)
        )
        source.emit(sequence: 1)

        XCTAssertEqual(pipeline.selectedCodec, .h264)
        XCTAssertEqual(pipeline.metrics.encodedFrames, 1)
    }

    func testUnsupportedHardwareCodecFailsBeforeCapture() async throws {
        let source = MockDisplayCaptureSource()
        let pipeline = ScreenCapturePipeline(
            source: source,
            capabilities: .none,
            encoderFactory: { codec, _, _, _ in
                MockDisplayVideoEncoder(codec: codec, autoComplete: true)
            }
        )

        do {
            try await pipeline.start(configuration: configuration())
            XCTFail("Expected codecUnsupported")
        } catch {
            XCTAssertEqual(error as? DisplayCaptureError, .codecUnsupported(.hevc))
        }
        XCTAssertEqual(source.startCount, 0)
        XCTAssertEqual(pipeline.state, .idle)
    }

    func testUnavailableSourceFailsBeforeCapture() async throws {
        let source = MockDisplayCaptureSource()
        source.isAvailable = false
        let pipeline = makePipeline(
            source: source,
            encoder: MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        )

        do {
            try await pipeline.start(configuration: configuration())
            XCTFail("Expected captureUnavailable")
        } catch {
            XCTAssertEqual(error as? DisplayCaptureError, .captureUnavailable)
        }
        XCTAssertEqual(source.startCount, 0)
        XCTAssertEqual(pipeline.state, .idle)
    }

    func testInvalidConfigurationIsRejected() async throws {
        let pipeline = makePipeline(
            source: MockDisplayCaptureSource(),
            encoder: MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        )

        do {
            try await pipeline.start(configuration: configuration(maxInFlightFrames: 0))
            XCTFail("Expected invalidConfiguration")
        } catch {
            XCTAssertEqual(
                error as? DisplayCaptureError,
                .invalidConfiguration("maxInFlightFrames")
            )
        }
        XCTAssertEqual(pipeline.state, .idle)
    }

    func testEncoderCreationFailureFailsClosed() async throws {
        let source = MockDisplayCaptureSource()
        let pipeline = ScreenCapturePipeline(
            source: source,
            capabilities: capabilities,
            encoderFactory: { _, _, _, _ in
                throw DisplayCaptureError.encoderUnavailable("mock")
            }
        )
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .encoderUnavailable("mock"))
            failure.fulfill()
        }

        try await pipeline.start(configuration: configuration())
        source.emit(sequence: 1)
        await fulfillment(of: [failure], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(pipeline.metrics.encodedFrames, 0)
    }

    func testEncoderFailureFailsClosedAndStopsSource() async throws {
        let source = MockDisplayCaptureSource()
        let stop = expectation(description: "source stopped")
        source.onStop = { stop.fulfill() }
        let encoder = MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        encoder.encodeError = .encoderFailure("mock")
        let pipeline = makePipeline(source: source, encoder: encoder)
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .encoderFailure("mock"))
            failure.fulfill()
        }

        try await pipeline.start(configuration: configuration())
        source.emit(sequence: 1)
        await fulfillment(of: [failure, stop], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(encoder.finishCount, 1)
    }

    func testSourceFailureFailsClosed() async throws {
        let source = MockDisplayCaptureSource()
        let encoder = MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        let pipeline = makePipeline(source: source, encoder: encoder)
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .sourceFailure("mock"))
            failure.fulfill()
        }

        try await pipeline.start(configuration: configuration())
        source.emit(sequence: 1)
        source.fail(.sourceFailure("mock"))
        await fulfillment(of: [failure], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
        XCTAssertEqual(encoder.finishCount, 1)
    }

    func testOversizedFramesFailClosed() async throws {
        let source = MockDisplayCaptureSource()
        let pipeline = makePipeline(
            source: source,
            encoder: MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        )
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .invalidFrame("dimensions"))
            failure.fulfill()
        }

        try await pipeline.start(configuration: configuration(maximumDimension: 32))
        source.emit(sequence: 1, width: 64, height: 64)
        await fulfillment(of: [failure], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
    }

    func testDimensionChangeFailsClosed() async throws {
        let source = MockDisplayCaptureSource()
        let pipeline = makePipeline(
            source: source,
            encoder: MockDisplayVideoEncoder(codec: .hevc, autoComplete: true)
        )
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .sourceFailure("capture dimensions changed"))
            failure.fulfill()
        }

        try await pipeline.start(configuration: configuration())
        source.emit(sequence: 1, width: 64, height: 64)
        source.emit(sequence: 2, width: 32, height: 32)
        await fulfillment(of: [failure], timeout: 1)

        XCTAssertEqual(pipeline.state, .failed)
    }

    private func configuration(
        preferredCodec: DisplayVideoCodec = .hevc,
        maxInFlightFrames: Int = 3,
        keyframeIntervalFrames: Int = 60,
        maximumDimension: Int = 4_096
    ) -> DisplayCaptureConfiguration {
        var configuration = DisplayCaptureConfiguration.standard
        configuration.preferredCodec = preferredCodec
        configuration.maxInFlightFrames = maxInFlightFrames
        configuration.keyframeIntervalFrames = keyframeIntervalFrames
        configuration.maximumDimension = maximumDimension
        return configuration
    }

    private func makePipeline(
        source: MockDisplayCaptureSource,
        encoder: MockDisplayVideoEncoder
    ) -> ScreenCapturePipeline {
        ScreenCapturePipeline(
            source: source,
            capabilities: capabilities,
            encoderFactory: { _, _, _, _ in encoder }
        )
    }
}

private final class MockDisplayCaptureSource: DisplayCaptureSource {
    var isAvailable = true
    var onFailure: ((DisplayCaptureError) -> Void)?
    var onStop: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onFrame: ((DisplayCaptureFrame) -> Void)?

    func start(
        configuration: DisplayCaptureConfiguration,
        onFrame: @escaping (DisplayCaptureFrame) -> Void
    ) async throws {
        _ = configuration
        startCount += 1
        self.onFrame = onFrame
    }

    func stop() async {
        stopCount += 1
        onFrame = nil
        onStop?()
    }

    func emit(
        sequence: UInt64,
        width: Int = 64,
        height: Int = 64
    ) {
        onFrame?(DisplayCaptureFrame(
            sequence: sequence,
            timestampSeconds: Double(sequence) / 30.0,
            durationSeconds: 1.0 / 30.0,
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA,
            pixelBuffer: Self.makePixelBuffer(width: width, height: height)
        ))
    }

    func fail(_ error: DisplayCaptureError) {
        onFailure?(error)
    }

    private static func makePixelBuffer(
        width: Int,
        height: Int
    ) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer
        )
        return buffer!
    }
}

private final class MockDisplayVideoEncoder: DisplayVideoEncoder {
    let codec: DisplayVideoCodec
    var isHardwareAccelerated = true
    var onFrame: ((EncodedDisplayFrame) -> Void)?
    var onFailure: ((DisplayCaptureError) -> Void)?
    var encodeError: DisplayCaptureError?
    private(set) var encoded: [(frame: DisplayCaptureFrame, forceKeyframe: Bool)] = []
    private(set) var finishCount = 0
    private let autoComplete: Bool
    private var pending: [(frame: DisplayCaptureFrame, forceKeyframe: Bool)] = []

    init(codec: DisplayVideoCodec, autoComplete: Bool) {
        self.codec = codec
        self.autoComplete = autoComplete
    }

    func encode(
        _ frame: DisplayCaptureFrame,
        forceKeyframe: Bool
    ) throws {
        if let encodeError {
            throw encodeError
        }
        encoded.append((frame, forceKeyframe))
        if autoComplete {
            onFrame?(makeEncodedFrame(frame, isKeyframe: forceKeyframe))
        } else {
            pending.append((frame, forceKeyframe))
        }
    }

    func completeNext(isKeyframe: Bool? = nil) {
        guard !pending.isEmpty else { return }
        let entry = pending.removeFirst()
        onFrame?(makeEncodedFrame(
            entry.frame,
            isKeyframe: isKeyframe ?? entry.forceKeyframe
        ))
    }

    func finish() {
        finishCount += 1
        onFrame = nil
        pending.removeAll()
    }

    private func makeEncodedFrame(
        _ frame: DisplayCaptureFrame,
        isKeyframe: Bool
    ) -> EncodedDisplayFrame {
        EncodedDisplayFrame(
            sequence: frame.sequence,
            timestampSeconds: frame.timestampSeconds,
            durationSeconds: frame.durationSeconds,
            width: frame.width,
            height: frame.height,
            codec: codec,
            isKeyframe: isKeyframe,
            data: Data([0x01, 0x02, 0x03])
        )
    }
}
