import CoreMedia
import CoreVideo
import Foundation
import ReplayKit
import VideoToolbox

enum DisplayVideoCodec: String, CaseIterable, Equatable, Sendable {
    case hevc
    case h264
    case av1

    var cmCodecType: CMVideoCodecType {
        switch self {
        case .hevc:
            return kCMVideoCodecType_HEVC
        case .h264:
            return kCMVideoCodecType_H264
        case .av1:
            return kCMVideoCodecType_AV1
        }
    }
}

struct DisplayVideoCapabilities: Equatable, Sendable {
    var hevcEncodeSupported: Bool
    var h264EncodeSupported: Bool
    var av1EncodeSupported: Bool

    static let none = DisplayVideoCapabilities(
        hevcEncodeSupported: false,
        h264EncodeSupported: false,
        av1EncodeSupported: false
    )

    static func detect() -> DisplayVideoCapabilities {
        DisplayVideoCapabilities(
            hevcEncodeSupported: canCreateHardwareSession(for: .hevc),
            h264EncodeSupported: canCreateHardwareSession(for: .h264),
            av1EncodeSupported: canCreateHardwareSession(for: .av1)
        )
    }

    func supports(_ codec: DisplayVideoCodec) -> Bool {
        switch codec {
        case .hevc:
            return hevcEncodeSupported
        case .h264:
            return h264EncodeSupported
        case .av1:
            return av1EncodeSupported
        }
    }

    private static func canCreateHardwareSession(
        for codec: DisplayVideoCodec
    ) -> Bool {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 64,
            height: 64,
            codecType: codec.cmCodecType,
            encoderSpecification: hardwareSpecification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        return status == noErr
    }

    static var hardwareSpecification: CFDictionary {
        [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
        ] as CFDictionary
    }
}

struct DisplayCaptureConfiguration: Equatable, Sendable {
    static let standard = DisplayCaptureConfiguration()

    var preferredCodec: DisplayVideoCodec = .hevc
    var framesPerSecond: Int = 30
    var maxInFlightFrames: Int = 3
    var keyframeIntervalFrames: Int = 60
    var averageBitRate: Int = 8_000_000
    var maximumDimension: Int = 4_096

    func validate() throws {
        guard (1...60).contains(framesPerSecond) else {
            throw DisplayCaptureError.invalidConfiguration("framesPerSecond")
        }
        guard (1...8).contains(maxInFlightFrames) else {
            throw DisplayCaptureError.invalidConfiguration("maxInFlightFrames")
        }
        guard (1...600).contains(keyframeIntervalFrames) else {
            throw DisplayCaptureError.invalidConfiguration("keyframeIntervalFrames")
        }
        guard (100_000...50_000_000).contains(averageBitRate) else {
            throw DisplayCaptureError.invalidConfiguration("averageBitRate")
        }
        guard (16...8_192).contains(maximumDimension) else {
            throw DisplayCaptureError.invalidConfiguration("maximumDimension")
        }
    }
}

enum DisplayCaptureState: Equatable {
    case idle
    case starting
    case running
    case stopped
    case failed
}

struct DisplayCaptureMetrics: Equatable {
    var receivedFrames = 0
    var encodedFrames = 0
    var droppedFrames = 0
    var keyframes = 0
    var totalEncodedBytes = 0
    var inFlightFrames = 0
}

enum DisplayCaptureError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case captureUnavailable
    case alreadyRunning
    case finished
    case codecUnsupported(DisplayVideoCodec)
    case encoderUnavailable(String)
    case encoderConfigurationFailed(String)
    case encoderFailure(String)
    case invalidFrame(String)
    case sourceFailure(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            return "The display capture configuration is invalid: \(field)."
        case .captureUnavailable:
            return "Display capture is unavailable on this device."
        case .alreadyRunning:
            return "Display capture is already running."
        case .finished:
            return "The display capture pipeline has already finished."
        case .codecUnsupported(let codec):
            return "Hardware encoding is unavailable for \(codec.rawValue)."
        case .encoderUnavailable(let reason):
            return "The display encoder is unavailable: \(reason)."
        case .encoderConfigurationFailed(let field):
            return "The display encoder could not configure \(field)."
        case .encoderFailure(let reason):
            return "The display encoder failed: \(reason)."
        case .invalidFrame(let reason):
            return "The display frame is invalid: \(reason)."
        case .sourceFailure(let reason):
            return "The display capture source failed: \(reason)."
        case .cancelled:
            return "Display capture was cancelled."
        }
    }
}

struct DisplayCaptureFrame {
    let sequence: UInt64
    let timestampSeconds: Double
    let durationSeconds: Double
    let width: Int
    let height: Int
    let pixelFormat: OSType
    let pixelBuffer: CVPixelBuffer
}

struct EncodedDisplayFrame: Equatable, Sendable {
    let sequence: UInt64
    let timestampSeconds: Double
    let durationSeconds: Double
    let width: Int
    let height: Int
    let codec: DisplayVideoCodec
    let isKeyframe: Bool
    let data: Data
    let parameterSets: [Data]
    let nalUnitHeaderLength: Int

    init(
        sequence: UInt64,
        timestampSeconds: Double,
        durationSeconds: Double,
        width: Int,
        height: Int,
        codec: DisplayVideoCodec,
        isKeyframe: Bool,
        data: Data,
        parameterSets: [Data] = [],
        nalUnitHeaderLength: Int = 4
    ) {
        self.sequence = sequence
        self.timestampSeconds = timestampSeconds
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.codec = codec
        self.isKeyframe = isKeyframe
        self.data = data
        self.parameterSets = parameterSets
        self.nalUnitHeaderLength = nalUnitHeaderLength
    }
}

protocol DisplayCaptureSource: AnyObject {
    var isAvailable: Bool { get }
    var onFailure: ((DisplayCaptureError) -> Void)? { get set }

    func start(
        configuration: DisplayCaptureConfiguration,
        onFrame: @escaping (DisplayCaptureFrame) -> Void
    ) async throws

    func stop() async
}

protocol DisplayVideoEncoder: AnyObject {
    var codec: DisplayVideoCodec { get }
    var isHardwareAccelerated: Bool { get }
    var onFrame: ((EncodedDisplayFrame) -> Void)? { get set }
    var onFailure: ((DisplayCaptureError) -> Void)? { get set }

    func encode(_ frame: DisplayCaptureFrame, forceKeyframe: Bool) throws
    func finish()
}

final class ScreenCapturePipeline {
    typealias EncoderFactory = (
        DisplayVideoCodec,
        DisplayCaptureConfiguration,
        Int,
        Int
    ) throws -> any DisplayVideoEncoder

    private let source: any DisplayCaptureSource
    private let capabilities: DisplayVideoCapabilities
    private let encoderFactory: EncoderFactory
    private let lock = NSLock()

    private var _state: DisplayCaptureState = .idle
    private var _configuration = DisplayCaptureConfiguration.standard
    private var _metrics = DisplayCaptureMetrics()
    private var _encoder: (any DisplayVideoEncoder)?
    private var _selectedCodec: DisplayVideoCodec?
    private var _encoderWidth = 0
    private var _encoderHeight = 0
    private var _lastFailure: DisplayCaptureError?
    private var _framesSinceKeyframe = 0
    private var _requestKeyframe = true

    var onEncodedFrame: ((EncodedDisplayFrame) -> Void)?
    var onFailure: ((DisplayCaptureError) -> Void)?

    init(
        source: any DisplayCaptureSource,
        capabilities: DisplayVideoCapabilities = .detect(),
        encoderFactory: @escaping EncoderFactory = {
            try VideoToolboxEncoder(
                codec: $0,
                configuration: $1,
                width: $2,
                height: $3
            )
        }
    ) {
        self.source = source
        self.capabilities = capabilities
        self.encoderFactory = encoderFactory
    }

    deinit {
        let encoder = _encoder
        _encoder = nil
        source.onFailure = nil
        encoder?.finish()
    }

    var state: DisplayCaptureState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    var metrics: DisplayCaptureMetrics {
        lock.lock()
        defer { lock.unlock() }
        return _metrics
    }

    var configuration: DisplayCaptureConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return _configuration
    }

    var selectedCodec: DisplayVideoCodec? {
        lock.lock()
        defer { lock.unlock() }
        return _selectedCodec
    }

    var isRunning: Bool {
        state == .running
    }

    func start(
        configuration: DisplayCaptureConfiguration = .standard
    ) async throws {
        try configuration.validate()

        let startError: DisplayCaptureError? = lock.withLock {
            guard _state == .idle else {
                return _state == .starting || _state == .running
                    ? DisplayCaptureError.alreadyRunning
                    : DisplayCaptureError.finished
            }
            _state = .starting
            _configuration = configuration
            _metrics = DisplayCaptureMetrics()
            _encoder = nil
            _selectedCodec = nil
            _encoderWidth = 0
            _encoderHeight = 0
            _lastFailure = nil
            _framesSinceKeyframe = 0
            _requestKeyframe = true
            return nil
        }
        if let startError {
            throw startError
        }

        do {
            guard source.isAvailable else {
                throw DisplayCaptureError.captureUnavailable
            }
            let codec = try selectCodec(for: configuration)
            lock.withLock {
                _selectedCodec = codec
            }

            source.onFailure = { [weak self] error in
                self?.handleFailure(error)
            }
            try await source.start(configuration: configuration) { [weak self] frame in
                self?.handleCaptureFrame(frame)
            }

            let snapshot = lock.withLock {
                if _state == .starting {
                    _state = .running
                }
                return (_state, _lastFailure, _encoder)
            }

            guard snapshot.0 == .starting || snapshot.0 == .running else {
                snapshot.2?.finish()
                source.onFailure = nil
                await source.stop()
                throw snapshot.1 ?? DisplayCaptureError.cancelled
            }
        } catch {
            let typed = Self.map(error)
            let encoder: (any DisplayVideoEncoder)? = lock.withLock {
                if _state == .starting {
                    _state = .idle
                }
                let encoder = _encoder
                _encoder = nil
                _selectedCodec = nil
                _encoderWidth = 0
                _encoderHeight = 0
                return encoder
            }
            encoder?.finish()
            source.onFailure = nil
            await source.stop()
            throw typed
        }
    }

    func stop() async {
        let context: (stopped: Bool, encoder: (any DisplayVideoEncoder)?) = lock.withLock {
            guard _state == .starting || _state == .running else {
                return (false, nil)
            }
            _state = .stopped
            let encoder = _encoder
            _encoder = nil
            _selectedCodec = nil
            _encoderWidth = 0
            _encoderHeight = 0
            _metrics.inFlightFrames = 0
            source.onFailure = nil
            return (true, encoder)
        }
        guard context.stopped else { return }

        context.encoder?.finish()
        await source.stop()
    }

    private func selectCodec(
        for configuration: DisplayCaptureConfiguration
    ) throws -> DisplayVideoCodec {
        let candidates = [
            configuration.preferredCodec,
            DisplayVideoCodec.hevc,
            DisplayVideoCodec.h264
        ]
        for codec in candidates
        where codec != .av1 && capabilities.supports(codec) {
            return codec
        }
        throw DisplayCaptureError.codecUnsupported(configuration.preferredCodec)
    }

    private func handleCaptureFrame(_ frame: DisplayCaptureFrame) {
        guard frame.width > 0,
              frame.height > 0,
              frame.width <= configuration.maximumDimension,
              frame.height <= configuration.maximumDimension else {
            handleFailure(.invalidFrame("dimensions"))
            return
        }

        lock.lock()
        guard _state == .starting || _state == .running else {
            lock.unlock()
            return
        }
        guard let codec = _selectedCodec else {
            lock.unlock()
            handleFailure(.encoderUnavailable("no selected codec"))
            return
        }

        _metrics.receivedFrames += 1
        if _metrics.inFlightFrames >= _configuration.maxInFlightFrames {
            _metrics.droppedFrames += 1
            _requestKeyframe = true
            lock.unlock()
            return
        }

        var encoder = _encoder
        if encoder == nil {
            do {
                let created = try encoderFactory(
                    codec,
                    _configuration,
                    frame.width,
                    frame.height
                )
                created.onFrame = { [weak self] encoded in
                    self?.handleEncodedFrame(encoded)
                }
                created.onFailure = { [weak self] error in
                    self?.handleFailure(error)
                }
                _encoder = created
                _encoderWidth = frame.width
                _encoderHeight = frame.height
                encoder = created
            } catch {
                lock.unlock()
                handleFailure(Self.map(error))
                return
            }
        }

        guard frame.width == _encoderWidth, frame.height == _encoderHeight else {
            lock.unlock()
            handleFailure(.sourceFailure("capture dimensions changed"))
            return
        }

        let forceKeyframe = _metrics.encodedFrames == 0
            || _requestKeyframe
            || _framesSinceKeyframe + 1 >= _configuration.keyframeIntervalFrames
        if forceKeyframe {
            _framesSinceKeyframe = 0
        } else {
            _framesSinceKeyframe += 1
        }
        _metrics.inFlightFrames += 1
        lock.unlock()

        do {
            try encoder?.encode(frame, forceKeyframe: forceKeyframe)
        } catch {
            handleFailure(Self.map(error))
        }
    }

    private func handleEncodedFrame(_ frame: EncodedDisplayFrame) {
        lock.lock()
        guard _state == .starting || _state == .running else {
            lock.unlock()
            return
        }
        if _metrics.inFlightFrames > 0 {
            _metrics.inFlightFrames -= 1
        }
        _metrics.encodedFrames += 1
        _metrics.totalEncodedBytes += frame.data.count
        if frame.isKeyframe {
            _metrics.keyframes += 1
            _framesSinceKeyframe = 0
            _requestKeyframe = false
        }
        let callback = onEncodedFrame
        lock.unlock()
        callback?(frame)
    }

    private func handleFailure(_ error: DisplayCaptureError) {
        let typed = Self.map(error)
        lock.lock()
        guard _state == .starting || _state == .running else {
            lock.unlock()
            return
        }
        let shouldStopSource = _state == .running
        _state = .failed
        _lastFailure = typed
        let encoder = _encoder
        _encoder = nil
        _selectedCodec = nil
        _encoderWidth = 0
        _encoderHeight = 0
        _metrics.inFlightFrames = 0
        source.onFailure = nil
        let callback = onFailure
        lock.unlock()

        encoder?.finish()
        if shouldStopSource {
            let source = self.source
            Task { await source.stop() }
        }
        callback?(typed)
    }

    private static func map(_ error: Error) -> DisplayCaptureError {
        if let typed = error as? DisplayCaptureError {
            return typed
        }
        return .sourceFailure(error.localizedDescription)
    }
}

final class ReplayKitDisplayCaptureSource: NSObject, DisplayCaptureSource {
    private let lock = NSLock()
    private let recorder = RPScreenRecorder.shared()
    private var running = false
    private var sequence: UInt64 = 0

    var onFailure: ((DisplayCaptureError) -> Void)?

    var isAvailable: Bool {
        recorder.isAvailable
    }

    func start(
        configuration: DisplayCaptureConfiguration,
        onFrame: @escaping (DisplayCaptureFrame) -> Void
    ) async throws {
        try configuration.validate()
        guard recorder.isAvailable else {
            throw DisplayCaptureError.captureUnavailable
        }

        let startError: DisplayCaptureError? = lock.withLock {
            guard !running, !recorder.isRecording else {
                return .alreadyRunning
            }
            running = true
            sequence = 0
            return nil
        }
        if let startError {
            throw startError
        }

        recorder.isMicrophoneEnabled = false
        recorder.delegate = self

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                    guard let self else { return }
                    if let error {
                        self.report(error)
                        return
                    }
                    guard bufferType == .video else { return }
                    self.emit(sampleBuffer, onFrame: onFrame)
                } completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            lock.withLock {
                running = false
            }
            recorder.delegate = nil
            throw DisplayCaptureError.sourceFailure(error.localizedDescription)
        }
    }

    func stop() async {
        let wasRunning = lock.withLock {
            guard running else { return false }
            running = false
            return true
        }
        guard wasRunning else { return }

        recorder.delegate = nil
        await withCheckedContinuation { continuation in
            recorder.stopCapture { _ in
                continuation.resume()
            }
        }
    }

    private func emit(
        _ sampleBuffer: CMSampleBuffer,
        onFrame: @escaping (DisplayCaptureFrame) -> Void
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = presentation.isValid
            ? CMTimeGetSeconds(presentation)
            : Date().timeIntervalSince1970
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let durationSeconds = duration.isValid && !duration.isIndefinite
            ? CMTimeGetSeconds(duration)
            : 1.0 / 30.0

        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        sequence &+= 1
        let frameSequence = sequence
        lock.unlock()

        onFrame(DisplayCaptureFrame(
            sequence: frameSequence,
            timestampSeconds: timestamp,
            durationSeconds: durationSeconds,
            width: width,
            height: height,
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
            pixelBuffer: pixelBuffer
        ))
    }

    private func report(_ error: Error) {
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        running = false
        let callback = onFailure
        lock.unlock()
        callback?(.sourceFailure(error.localizedDescription))
    }
}

extension ReplayKitDisplayCaptureSource: RPScreenRecorderDelegate {
    func screenRecorder(
        _ screenRecorder: RPScreenRecorder,
        didStopWithError error: Error
    ) {
        _ = screenRecorder
        report(error)
    }
}
