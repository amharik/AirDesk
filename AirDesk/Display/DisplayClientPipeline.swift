import Foundation
import QuartzCore

struct DisplayClientConfiguration: Equatable, Sendable {
    static let standard = DisplayClientConfiguration()

    var pacing = DisplayFramePacingConfiguration.standard
    var maximumDecodeInFlightFrames: Int = 3

    func validate() throws {
        try pacing.validate()
        guard (1...8).contains(maximumDecodeInFlightFrames) else {
            throw DisplayClientError.invalidConfiguration(
                "maximumDecodeInFlightFrames"
            )
        }
    }
}

enum DisplayClientError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            return "The display client configuration is invalid: \(field)."
        }
    }
}

struct DisplayClientMetrics: Equatable, Sendable {
    var receivedEncodedFrames = 0
    var droppedPreKeyframeFrames = 0
    var droppedDecodeBackpressureFrames = 0
    var decodedFrames = 0
    var decodeFailures = 0
    var decodeInFlightFrames = 0
    var totalDecodeLatencySeconds: Double = 0
    var peakDecodeLatencySeconds: Double = 0
    var totalDecodeCPUSeconds: Double = 0
    var pacing = DisplayFramePacingMetrics()

    var droppedEncodedFrames: Int {
        droppedPreKeyframeFrames + droppedDecodeBackpressureFrames
    }

    var averageDecodeLatencyMilliseconds: Double {
        guard decodedFrames > 0 else { return 0 }
        return totalDecodeLatencySeconds / Double(decodedFrames) * 1_000
    }

    var averageDecodeCPUMilliseconds: Double {
        guard decodedFrames > 0 else { return 0 }
        return totalDecodeCPUSeconds / Double(decodedFrames) * 1_000
    }

    var totalPacingDrops: Int {
        pacing.droppedFrames
    }
}

final class DisplayClientPipeline {
    typealias DecoderFactory = (EncodedDisplayFrame) throws ->
        any DisplayVideoDecoder

    let configuration: DisplayClientConfiguration
    let pacer: DisplayFramePacer

    private let decoderFactory: DecoderFactory
    private let lock = NSLock()
    private var decoder: (any DisplayVideoDecoder)?
    private var decoderCodec: DisplayVideoCodec?
    private var decoderWidth = 0
    private var decoderHeight = 0
    private var _metrics = DisplayClientMetrics()
    private var _failure: DisplayDecodeError?
    private var _finished = false

    var onFailure: ((DisplayDecodeError) -> Void)?
    var onPresentedFrame: ((DecodedDisplayFrame) -> Void)?

    init(
        configuration: DisplayClientConfiguration = .standard,
        decoderFactory: @escaping DecoderFactory = {
            try VideoToolboxDisplayDecoder(frame: $0)
        }
    ) throws {
        try configuration.validate()
        self.configuration = configuration
        self.pacer = try DisplayFramePacer(configuration: configuration.pacing)
        self.decoderFactory = decoderFactory
    }

    var metrics: DisplayClientMetrics {
        var snapshot = lock.withLock { _metrics }
        snapshot.pacing = pacer.metrics
        return snapshot
    }

    var failure: DisplayDecodeError? {
        lock.withLock { _failure }
    }

    var isFinished: Bool {
        lock.withLock { _finished }
    }

    func submit(_ frame: EncodedDisplayFrame) throws {
        var decoderToUse: (any DisplayVideoDecoder)?

        lock.lock()
        guard !_finished else {
            lock.unlock()
            throw DisplayDecodeError.finished
        }
        if let _failure {
            lock.unlock()
            throw _failure
        }

        _metrics.receivedEncodedFrames += 1
        guard _metrics.decodeInFlightFrames
            < configuration.maximumDecodeInFlightFrames else {
            _metrics.droppedDecodeBackpressureFrames += 1
            lock.unlock()
            return
        }

        if decoder == nil {
            guard frame.isKeyframe else {
                _metrics.droppedPreKeyframeFrames += 1
                lock.unlock()
                return
            }
            do {
                let created = try decoderFactory(frame)
                created.onFrame = { [weak self] decoded in
                    self?.handleDecoded(
                        decoded,
                        receivedAt: CACurrentMediaTime()
                    )
                }
                created.onFailure = { [weak self] error in
                    self?.handleFailure(error)
                }
                decoder = created
                decoderCodec = frame.codec
                decoderWidth = frame.width
                decoderHeight = frame.height
                decoderToUse = created
            } catch {
                let typed = Self.map(error)
                _metrics.decodeFailures += 1
                _failure = typed
                let callback = onFailure
                lock.unlock()
                callback?(typed)
                throw typed
            }
        } else {
            decoderToUse = decoder
        }

        guard frame.codec == decoderCodec,
              frame.width == decoderWidth,
              frame.height == decoderHeight else {
            let typed = DisplayDecodeError.invalidFrame(
                "decoder dimensions changed"
            )
            _metrics.decodeFailures += 1
            _failure = typed
            let failingDecoder = decoder
            decoder = nil
            decoderCodec = nil
            decoderWidth = 0
            decoderHeight = 0
            let callback = onFailure
            lock.unlock()
            callback?(typed)
            Self.finishLater(failingDecoder)
            throw typed
        }

        _metrics.decodeInFlightFrames += 1
        lock.unlock()

        do {
            try decoderToUse?.decode(frame)
        } catch {
            let typed = Self.map(error)
            handleFailure(typed)
            throw typed
        }
    }

    func presentFrameIfAvailable(
        at time: TimeInterval
    ) -> DecodedDisplayFrame? {
        guard let frame = pacer.presentFrameIfAvailable(at: time) else {
            return nil
        }
        onPresentedFrame?(frame)
        return frame
    }

    func finish() {
        let oldDecoder: (any DisplayVideoDecoder)? = lock.withLock {
            guard !_finished else { return nil }
            _finished = true
            let oldDecoder = decoder
            decoder = nil
            decoderCodec = nil
            decoderWidth = 0
            decoderHeight = 0
            _metrics.decodeInFlightFrames = 0
            return oldDecoder
        }
        pacer.removeAll()
        oldDecoder?.finish()
    }

    private func handleDecoded(
        _ frame: DecodedDisplayFrame,
        receivedAt: TimeInterval
    ) {
        lock.lock()
        guard !_finished, _failure == nil else {
            lock.unlock()
            return
        }
        if _metrics.decodeInFlightFrames > 0 {
            _metrics.decodeInFlightFrames -= 1
        }
        _metrics.decodedFrames += 1
        _metrics.totalDecodeLatencySeconds += frame.decodeLatencySeconds
        _metrics.peakDecodeLatencySeconds = max(
            _metrics.peakDecodeLatencySeconds,
            frame.decodeLatencySeconds
        )
        _metrics.totalDecodeCPUSeconds += frame.decodeCPUSeconds
        lock.unlock()

        pacer.enqueue(frame, receivedAt: receivedAt)
    }

    private func handleFailure(_ error: DisplayDecodeError) {
        let typed = Self.map(error)
        lock.lock()
        guard !_finished, _failure == nil else {
            lock.unlock()
            return
        }
        if _metrics.decodeInFlightFrames > 0 {
            _metrics.decodeInFlightFrames -= 1
        }
        _metrics.decodeFailures += 1
        _failure = typed
        let failingDecoder = decoder
        decoder = nil
        decoderCodec = nil
        decoderWidth = 0
        decoderHeight = 0
        let callback = onFailure
        lock.unlock()

        Self.finishLater(failingDecoder)
        callback?(typed)
    }

    private static func finishLater(
        _ decoder: (any DisplayVideoDecoder)?
    ) {
        guard let decoder else { return }
        DispatchQueue.global(qos: .utility).async {
            decoder.finish()
        }
    }

    private static func map(_ error: Error) -> DisplayDecodeError {
        if let typed = error as? DisplayDecodeError {
            return typed
        }
        return .decoderFailure(error.localizedDescription)
    }
}
