import CoreVideo
import XCTest
@testable import AirDesk

final class DisplayClientPipelineTests: XCTestCase {
    func testDropsFramesUntilFirstDecodableKeyframe() throws {
        var createdDecoders: [MockDisplayVideoDecoder] = []
        let pipeline = try makePipeline { frame in
            let decoder = MockDisplayVideoDecoder(codec: frame.codec)
            createdDecoders.append(decoder)
            return decoder
        }

        try pipeline.submit(encoded(sequence: 1, isKeyframe: false))
        XCTAssertTrue(createdDecoders.isEmpty)
        XCTAssertEqual(pipeline.metrics.receivedEncodedFrames, 1)
        XCTAssertEqual(pipeline.metrics.droppedPreKeyframeFrames, 1)

        try pipeline.submit(encoded(sequence: 2, isKeyframe: true))
        XCTAssertEqual(createdDecoders.count, 1)
        XCTAssertEqual(pipeline.metrics.decodedFrames, 1)
        XCTAssertEqual(pipeline.metrics.decodeInFlightFrames, 0)
    }

    func testBoundsDecodeBackpressureAndRecovers() throws {
        var decoder: MockDisplayVideoDecoder?
        var configuration = DisplayClientConfiguration.standard
        configuration.maximumDecodeInFlightFrames = 1
        let pipeline = try makePipeline(configuration: configuration) { frame in
            let created = MockDisplayVideoDecoder(codec: frame.codec)
            created.autoComplete = false
            decoder = created
            return created
        }

        try pipeline.submit(encoded(sequence: 1, isKeyframe: true))
        XCTAssertEqual(pipeline.metrics.decodeInFlightFrames, 1)

        try pipeline.submit(encoded(sequence: 2, isKeyframe: true))
        XCTAssertEqual(pipeline.metrics.droppedDecodeBackpressureFrames, 1)
        XCTAssertEqual(pipeline.metrics.decodedFrames, 0)

        decoder?.completeNext()
        XCTAssertEqual(pipeline.metrics.decodeInFlightFrames, 0)
        XCTAssertEqual(pipeline.metrics.decodedFrames, 1)
        XCTAssertEqual(pipeline.metrics.pacing.receivedFrames, 1)
    }

    func testPresentsDecodedFramesAtDisplayRefreshInterval() throws {
        let pipeline = try makePipeline { frame in
            MockDisplayVideoDecoder(codec: frame.codec)
        }
        var presented: [UInt64] = []
        pipeline.onPresentedFrame = { presented.append($0.sequence) }

        try pipeline.submit(encoded(sequence: 1, isKeyframe: true))

        XCTAssertEqual(pipeline.presentFrameIfAvailable(at: 10)?.sequence, 1)
        XCTAssertNil(pipeline.presentFrameIfAvailable(at: 10.005))
        XCTAssertEqual(presented, [1])
        XCTAssertEqual(pipeline.metrics.pacing.presentedFrames, 1)
        XCTAssertEqual(pipeline.metrics.pacing.currentQueueDepth, 0)
    }

    func testAggregatesDecodeLatencyAndCPUMetrics() throws {
        var decoder: MockDisplayVideoDecoder?
        let pipeline = try makePipeline { frame in
            let created = MockDisplayVideoDecoder(codec: frame.codec)
            created.nextDecodeLatencySeconds = 0.004
            created.nextDecodeCPUSeconds = 0.001
            decoder = created
            return created
        }

        try pipeline.submit(encoded(sequence: 1, isKeyframe: true))
        try pipeline.submit(encoded(sequence: 2, isKeyframe: false))
        _ = decoder

        XCTAssertEqual(pipeline.metrics.decodedFrames, 2)
        XCTAssertEqual(pipeline.metrics.totalDecodeLatencySeconds, 0.008, accuracy: 0.0001)
        XCTAssertEqual(pipeline.metrics.peakDecodeLatencySeconds, 0.004, accuracy: 0.0001)
        XCTAssertEqual(pipeline.metrics.averageDecodeLatencyMilliseconds, 4, accuracy: 0.1)
        XCTAssertEqual(pipeline.metrics.totalDecodeCPUSeconds, 0.002, accuracy: 0.0001)
        XCTAssertEqual(pipeline.metrics.averageDecodeCPUMilliseconds, 1, accuracy: 0.1)
    }

    func testDecoderFailureFailsClosedAndRejectsFurtherFrames() throws {
        var decoder: MockDisplayVideoDecoder?
        let finished = expectation(description: "decoder finished")
        let pipeline = try makePipeline { frame in
            let created = MockDisplayVideoDecoder(codec: frame.codec)
            created.decodeError = .decoderFailure("mock")
            created.onFinish = { finished.fulfill() }
            decoder = created
            return created
        }
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .decoderFailure("mock"))
            failure.fulfill()
        }

        XCTAssertThrowsError(
            try pipeline.submit(encoded(sequence: 1, isKeyframe: true))
        ) { error in
            XCTAssertEqual(error as? DisplayDecodeError, .decoderFailure("mock"))
        }
        wait(for: [failure, finished], timeout: 1)
        XCTAssertEqual(pipeline.metrics.decodeFailures, 1)
        XCTAssertEqual(pipeline.metrics.decodeInFlightFrames, 0)
        XCTAssertEqual(pipeline.failure, .decoderFailure("mock"))
        XCTAssertEqual(decoder?.finishCount, 1)

        XCTAssertThrowsError(
            try pipeline.submit(encoded(sequence: 2, isKeyframe: true))
        ) { error in
            XCTAssertEqual(error as? DisplayDecodeError, .decoderFailure("mock"))
        }
    }

    func testDecoderCreationFailureFailsClosed() throws {
        let pipeline = try makePipeline { _ in
            throw DisplayDecodeError.decoderUnavailable("mock")
        }
        let failure = expectation(description: "failure")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .decoderUnavailable("mock"))
            failure.fulfill()
        }

        XCTAssertThrowsError(
            try pipeline.submit(encoded(sequence: 1, isKeyframe: true))
        )
        wait(for: [failure], timeout: 1)
        XCTAssertEqual(pipeline.metrics.decodeFailures, 1)
        XCTAssertEqual(pipeline.metrics.decodedFrames, 0)
    }

    func testDimensionChangeFailsClosed() throws {
        let pipeline = try makePipeline { frame in
            MockDisplayVideoDecoder(codec: frame.codec)
        }
        try pipeline.submit(encoded(sequence: 1, isKeyframe: true, width: 64, height: 64))
        XCTAssertThrowsError(
            try pipeline.submit(encoded(sequence: 2, isKeyframe: true, width: 32, height: 32))
        ) { error in
            XCTAssertEqual(
                error as? DisplayDecodeError,
                .invalidFrame("decoder dimensions changed")
            )
        }
        XCTAssertEqual(pipeline.metrics.decodeFailures, 1)
    }

    func testFinishStopsDecoderAndRejectsFrames() throws {
        var decoder: MockDisplayVideoDecoder?
        let pipeline = try makePipeline { frame in
            let created = MockDisplayVideoDecoder(codec: frame.codec)
            decoder = created
            return created
        }
        try pipeline.submit(encoded(sequence: 1, isKeyframe: true))

        pipeline.finish()
        XCTAssertTrue(pipeline.isFinished)
        XCTAssertEqual(decoder?.finishCount, 1)

        XCTAssertThrowsError(
            try pipeline.submit(encoded(sequence: 2, isKeyframe: true))
        ) { error in
            XCTAssertEqual(error as? DisplayDecodeError, .finished)
        }
    }

    func testPacerEnforcesTargetInterval() throws {
        let pacer = try DisplayFramePacer(configuration: pacingConfiguration())
        XCTAssertTrue(pacer.enqueue(decoded(sequence: 1), receivedAt: 1))
        XCTAssertTrue(pacer.enqueue(decoded(sequence: 2), receivedAt: 1.001))

        XCTAssertEqual(pacer.presentFrameIfAvailable(at: 1)?.sequence, 1)
        XCTAssertNil(pacer.presentFrameIfAvailable(at: 1.005))
        XCTAssertEqual(pacer.presentFrameIfAvailable(at: 1.02)?.sequence, 2)
        XCTAssertEqual(pacer.metrics.presentedFrames, 2)
        XCTAssertEqual(pacer.metrics.lastPresentationIntervalSeconds, 0.02, accuracy: 0.001)
    }

    func testPacerDropsOverflowAndKeepsNewestFrame() throws {
        var configuration = pacingConfiguration()
        configuration.maximumQueuedFrames = 1
        let pacer = try DisplayFramePacer(configuration: configuration)

        pacer.enqueue(decoded(sequence: 1), receivedAt: 1)
        pacer.enqueue(decoded(sequence: 2), receivedAt: 1.001)

        XCTAssertEqual(pacer.metrics.overflowDrops, 1)
        XCTAssertEqual(pacer.metrics.droppedFrames, 1)
        XCTAssertEqual(pacer.metrics.currentQueueDepth, 1)
        XCTAssertEqual(pacer.presentFrameIfAvailable(at: 1.01)?.sequence, 2)
    }

    func testPacerDropsExpiredFrames() throws {
        var configuration = pacingConfiguration()
        configuration.maximumFrameAgeSeconds = 0.05
        let pacer = try DisplayFramePacer(configuration: configuration)

        pacer.enqueue(decoded(sequence: 1), receivedAt: 1)
        XCTAssertNil(pacer.presentFrameIfAvailable(at: 1.1))
        XCTAssertEqual(pacer.metrics.lateFrames, 1)
        XCTAssertEqual(pacer.metrics.droppedFrames, 1)
        XCTAssertEqual(pacer.metrics.currentQueueDepth, 0)
    }

    func testPacerRejectsInvalidConfiguration() {
        var configuration = pacingConfiguration()
        configuration.targetFramesPerSecond = 0
        XCTAssertThrowsError(try DisplayFramePacer(configuration: configuration)) {
            XCTAssertEqual(
                $0 as? DisplayFramePacingError,
                .invalidConfiguration("targetFramesPerSecond")
            )
        }
    }

    func testDecoderRejectsAV1() {
        XCTAssertThrowsError(
            try VideoToolboxDisplayDecoder(frame: encoded(
                sequence: 1,
                isKeyframe: true,
                codec: .av1
            ))
        ) { error in
            XCTAssertEqual(error as? DisplayDecodeError, .unsupportedCodec(.av1))
        }
    }

    func testDecoderRejectsMissingParameterSets() {
        XCTAssertThrowsError(
            try VideoToolboxDisplayDecoder(frame: encoded(
                sequence: 1,
                isKeyframe: true,
                parameterSets: []
            ))
        ) { error in
            XCTAssertEqual(
                error as? DisplayDecodeError,
                .invalidFrame("missing parameter sets")
            )
        }
    }

    private func makePipeline(
        configuration: DisplayClientConfiguration = .standard,
        decoderFactory: @escaping DisplayClientPipeline.DecoderFactory = {
            try VideoToolboxDisplayDecoder(frame: $0)
        }
    ) throws -> DisplayClientPipeline {
        try DisplayClientPipeline(
            configuration: configuration,
            decoderFactory: decoderFactory
        )
    }

    private func pacingConfiguration() -> DisplayFramePacingConfiguration {
        var configuration = DisplayFramePacingConfiguration.standard
        configuration.targetFramesPerSecond = 60
        configuration.maximumQueuedFrames = 2
        configuration.maximumFrameAgeSeconds = 0.25
        return configuration
    }

    private func encoded(
        sequence: UInt64,
        isKeyframe: Bool,
        codec: DisplayVideoCodec = .hevc,
        width: Int = 64,
        height: Int = 64,
        parameterSets: [Data] = [Data([1, 2, 3]), Data([4, 5])]
    ) -> EncodedDisplayFrame {
        EncodedDisplayFrame(
            sequence: sequence,
            timestampSeconds: Double(sequence) / 60,
            durationSeconds: 1 / 60,
            width: width,
            height: height,
            codec: codec,
            isKeyframe: isKeyframe,
            data: Data([0, 0, 0, 2, 9, 10]),
            parameterSets: parameterSets
        )
    }

    private func decoded(sequence: UInt64) -> DecodedDisplayFrame {
        DecodedDisplayFrame(
            sequence: sequence,
            timestampSeconds: Double(sequence) / 60,
            durationSeconds: 1 / 60,
            width: 64,
            height: 64,
            pixelBuffer: Self.makePixelBuffer(width: 64, height: 64),
            decodeLatencySeconds: 0.004,
            decodeCPUSeconds: 0.001
        )
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

private final class MockDisplayVideoDecoder: DisplayVideoDecoder {
    let codec: DisplayVideoCodec
    var isHardwareAccelerated = true
    var onFrame: ((DecodedDisplayFrame) -> Void)?
    var onFailure: ((DisplayDecodeError) -> Void)?
    var autoComplete = true
    var decodeError: DisplayDecodeError?
    var nextDecodeLatencySeconds = 0.004
    var nextDecodeCPUSeconds = 0.001
    var onFinish: (() -> Void)?
    private(set) var decoded: [EncodedDisplayFrame] = []
    private(set) var finishCount = 0
    private var pending: [EncodedDisplayFrame] = []

    init(codec: DisplayVideoCodec) {
        self.codec = codec
    }

    func decode(_ frame: EncodedDisplayFrame) throws {
        if let decodeError {
            throw decodeError
        }
        decoded.append(frame)
        if autoComplete {
            completeNext()
        } else {
            pending.append(frame)
        }
    }

    func completeNext() {
        guard let frame = pending.isEmpty ? decoded.last : pending.removeFirst() else {
            return
        }
        onFrame?(DecodedDisplayFrame(
            sequence: frame.sequence,
            timestampSeconds: frame.timestampSeconds,
            durationSeconds: frame.durationSeconds,
            width: frame.width,
            height: frame.height,
            pixelBuffer: Self.makePixelBuffer(width: frame.width, height: frame.height),
            decodeLatencySeconds: nextDecodeLatencySeconds,
            decodeCPUSeconds: nextDecodeCPUSeconds
        ))
    }

    func finish() {
        finishCount += 1
        onFinish?()
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
