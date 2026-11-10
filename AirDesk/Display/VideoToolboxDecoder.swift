import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

struct DecodedDisplayFrame {
    let sequence: UInt64
    let timestampSeconds: Double
    let durationSeconds: Double
    let width: Int
    let height: Int
    let pixelBuffer: CVPixelBuffer
    let decodeLatencySeconds: Double
    let decodeCPUSeconds: Double
}

enum DisplayDecodeError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case unsupportedCodec(DisplayVideoCodec)
    case invalidFrame(String)
    case decoderUnavailable(String)
    case decoderConfigurationFailed(String)
    case decoderFailure(String)
    case finished

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            return "The display decode configuration is invalid: \(field)."
        case .unsupportedCodec(let codec):
            return "Display decoding is unavailable for \(codec.rawValue)."
        case .invalidFrame(let reason):
            return "The encoded display frame is invalid: \(reason)."
        case .decoderUnavailable(let reason):
            return "The display decoder is unavailable: \(reason)."
        case .decoderConfigurationFailed(let field):
            return "The display decoder could not configure \(field)."
        case .decoderFailure(let reason):
            return "The display decoder failed: \(reason)."
        case .finished:
            return "The display decoder has already finished."
        }
    }
}

protocol DisplayVideoDecoder: AnyObject {
    var codec: DisplayVideoCodec { get }
    var isHardwareAccelerated: Bool { get }
    var onFrame: ((DecodedDisplayFrame) -> Void)? { get set }
    var onFailure: ((DisplayDecodeError) -> Void)? { get set }

    func decode(_ frame: EncodedDisplayFrame) throws
    func finish()
}

final class VideoToolboxDisplayDecoder: DisplayVideoDecoder {
    let codec: DisplayVideoCodec
    private let formatDescription: CMVideoFormatDescription
    private let nalUnitHeaderLength: Int
    private let width: Int
    private let height: Int
    private let lock = NSLock()
    private var session: VTDecompressionSession?
    private var finished = false

    private(set) var isHardwareAccelerated = false
    var onFrame: ((DecodedDisplayFrame) -> Void)?
    var onFailure: ((DisplayDecodeError) -> Void)?

    init(frame: EncodedDisplayFrame) throws {
        guard frame.codec != .av1 else {
            throw DisplayDecodeError.unsupportedCodec(.av1)
        }
        guard frame.width > 0,
              frame.height > 0,
              frame.width <= 8_192,
              frame.height <= 8_192 else {
            throw DisplayDecodeError.invalidConfiguration("dimensions")
        }
        guard !frame.data.isEmpty else {
            throw DisplayDecodeError.invalidFrame("empty compressed data")
        }
        guard (1...4).contains(frame.nalUnitHeaderLength) else {
            throw DisplayDecodeError.invalidConfiguration("nalUnitHeaderLength")
        }

        codec = frame.codec
        nalUnitHeaderLength = frame.nalUnitHeaderLength
        width = frame.width
        height = frame.height
        formatDescription = try Self.makeFormatDescription(
            codec: frame.codec,
            parameterSets: frame.parameterSets,
            nalUnitHeaderLength: frame.nalUnitHeaderLength
        )

        var session: VTDecompressionSession?
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: Self.decompressionOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let specification = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ] as CFDictionary
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: specification,
            imageBufferAttributes: attributes,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw DisplayDecodeError.decoderUnavailable(
                "VideoToolbox session creation failed (\(status))"
            )
        }
        self.session = session

        var property: CFTypeRef?
        let propertyStatus = VTSessionCopyProperty(
            session,
            key: kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
            allocator: kCFAllocatorDefault,
            valueOut: &property
        )
        if propertyStatus == noErr, let value = property as? NSNumber {
            isHardwareAccelerated = value.boolValue
        }
    }

    deinit {
        finish()
    }

    func decode(_ frame: EncodedDisplayFrame) throws {
        lock.lock()
        guard !finished, let session else {
            lock.unlock()
            throw DisplayDecodeError.finished
        }
        lock.unlock()

        guard frame.codec == codec else {
            throw DisplayDecodeError.invalidFrame("codec changed")
        }
        guard frame.width == width, frame.height == height else {
            throw DisplayDecodeError.invalidFrame("decoder dimensions changed")
        }
        guard frame.nalUnitHeaderLength == nalUnitHeaderLength else {
            throw DisplayDecodeError.invalidFrame("NAL unit header length changed")
        }
        guard !frame.data.isEmpty else {
            throw DisplayDecodeError.invalidFrame("empty compressed data")
        }

        let sampleBuffer = try makeSampleBuffer(frame)
        let metadata = FrameMetadata(
            sequence: frame.sequence,
            timestampSeconds: frame.timestampSeconds,
            durationSeconds: frame.durationSeconds,
            startedAtSeconds: Self.currentUptimeSeconds(),
            cpuStartedAtSeconds: Self.currentCPUTimeSeconds()
        )
        let refCon = Unmanaged.passRetained(metadata).toOpaque()
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [],
            frameRefcon: refCon,
            infoFlagsOut: &infoFlags
        )
        if status != noErr {
            Unmanaged<FrameMetadata>.fromOpaque(refCon).release()
            throw DisplayDecodeError.decoderFailure(
                "VideoToolbox decode failed (\(status))"
            )
        }
    }

    func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let session = self.session
        self.session = nil
        lock.unlock()

        guard let session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        VTDecompressionSessionInvalidate(session)
    }

    private func makeSampleBuffer(
        _ frame: EncodedDisplayFrame
    ) throws -> CMSampleBuffer {
        guard frame.timestampSeconds.isFinite,
              frame.durationSeconds.isFinite,
              frame.timestampSeconds >= 0,
              frame.durationSeconds > 0 else {
            throw DisplayDecodeError.invalidFrame("timing")
        }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: frame.data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: frame.data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == noErr, let blockBuffer else {
            throw DisplayDecodeError.decoderFailure(
                "VideoToolbox block buffer creation failed (\(blockStatus))"
            )
        }

        let copyStatus: OSStatus = frame.data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return OSStatus(-1)
            }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: frame.data.count
            )
        }
        guard copyStatus == noErr else {
            throw DisplayDecodeError.decoderFailure(
                "VideoToolbox block buffer copy failed (\(copyStatus))"
            )
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(
                seconds: frame.durationSeconds,
                preferredTimescale: 600
            ),
            presentationTimeStamp: CMTime(
                seconds: frame.timestampSeconds,
                preferredTimescale: 600
            ),
            decodeTimeStamp: .invalid
        )
        var sampleSize = frame.data.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw DisplayDecodeError.decoderFailure(
                "VideoToolbox sample buffer creation failed (\(sampleStatus))"
            )
        }
        return sampleBuffer
    }

    private func handleOutput(
        status: OSStatus,
        imageBuffer: CVImageBuffer?,
        presentationTimeStamp: CMTime,
        presentationDuration: CMTime,
        metadata: FrameMetadata
    ) {
        guard status == noErr, let imageBuffer else {
            onFailure?(.decoderFailure("VideoToolbox decode failed (\(status))"))
            return
        }
        let now = Self.currentUptimeSeconds()
        let cpuNow = Self.currentCPUTimeSeconds()
        let pixelBuffer = imageBuffer as CVPixelBuffer
        let timestamp = presentationTimeStamp.isValid
            ? CMTimeGetSeconds(presentationTimeStamp)
            : metadata.timestampSeconds
        let duration = presentationDuration.isValid
            && !presentationDuration.isIndefinite
            ? CMTimeGetSeconds(presentationDuration)
            : metadata.durationSeconds
        let frame = DecodedDisplayFrame(
            sequence: metadata.sequence,
            timestampSeconds: timestamp,
            durationSeconds: duration,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelBuffer: pixelBuffer,
            decodeLatencySeconds: max(0, now - metadata.startedAtSeconds),
            decodeCPUSeconds: max(0, cpuNow - metadata.cpuStartedAtSeconds)
        )

        let isFinished = lock.withLock { finished }
        guard !isFinished else { return }
        onFrame?(frame)
    }

    private static let decompressionOutputCallback: VTDecompressionOutputCallback = {
        refCon,
        sourceFrameRefCon,
        status,
        flags,
        imageBuffer,
        presentationTimeStamp,
        presentationDuration in
        _ = flags
        guard let refCon else { return }
        let decoder = Unmanaged<VideoToolboxDisplayDecoder>
            .fromOpaque(refCon)
            .takeUnretainedValue()
        guard let sourceFrameRefCon else {
            decoder.onFailure?(.decoderFailure("VideoToolbox returned no frame metadata"))
            return
        }
        let metadata = Unmanaged<FrameMetadata>
            .fromOpaque(sourceFrameRefCon)
            .takeRetainedValue()
        decoder.handleOutput(
            status: status,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            presentationDuration: presentationDuration,
            metadata: metadata
        )
    }

    private static func makeFormatDescription(
        codec: DisplayVideoCodec,
        parameterSets: [Data],
        nalUnitHeaderLength: Int
    ) throws -> CMVideoFormatDescription {
        guard codec != .av1 else {
            throw DisplayDecodeError.unsupportedCodec(.av1)
        }
        guard !parameterSets.isEmpty, parameterSets.count <= 16 else {
            throw DisplayDecodeError.invalidFrame("missing parameter sets")
        }
        var formatDescription: CMVideoFormatDescription?
        let status = try withParameterSetPointers(parameterSets) {
            pointers,
            sizes in
            switch codec {
            case .hevc:
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSets.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: Int32(nalUnitHeaderLength),
                    extensions: nil,
                    formatDescriptionOut: &formatDescription
                )
            case .h264:
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: parameterSets.count,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: Int32(nalUnitHeaderLength),
                    formatDescriptionOut: &formatDescription
                )
            case .av1:
                throw DisplayDecodeError.unsupportedCodec(.av1)
            }
        }
        guard status == noErr, let formatDescription else {
            throw DisplayDecodeError.decoderConfigurationFailed(
                "parameter sets (\(status))"
            )
        }
        return formatDescription
    }

    private static func withParameterSetPointers<Result>(
        _ parameterSets: [Data],
        _ body: (
            UnsafePointer<UnsafePointer<UInt8>>,
            UnsafePointer<Int>
        ) throws -> Result
    ) throws -> Result {
        let sizes = parameterSets.map(\.count)
        func recurse(
            _ index: Int,
            _ pointers: [UnsafePointer<UInt8>]
        ) throws -> Result {
            guard index < parameterSets.count else {
                return try pointers.withUnsafeBufferPointer { pointerBuffer in
                    try sizes.withUnsafeBufferPointer { sizeBuffer in
                        try body(pointerBuffer.baseAddress!, sizeBuffer.baseAddress!)
                    }
                }
            }
            return try parameterSets[index].withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer
                    .bindMemory(to: UInt8.self)
                    .baseAddress else {
                    throw DisplayDecodeError.invalidFrame("empty parameter set")
                }
                return try recurse(index + 1, pointers + [baseAddress])
            }
        }
        return try recurse(0, [])
    }

    private static func currentUptimeSeconds() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    private static func currentCPUTimeSeconds() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID))
            / 1_000_000_000
    }

    private final class FrameMetadata {
        let sequence: UInt64
        let timestampSeconds: Double
        let durationSeconds: Double
        let startedAtSeconds: Double
        let cpuStartedAtSeconds: Double

        init(
            sequence: UInt64,
            timestampSeconds: Double,
            durationSeconds: Double,
            startedAtSeconds: Double,
            cpuStartedAtSeconds: Double
        ) {
            self.sequence = sequence
            self.timestampSeconds = timestampSeconds
            self.durationSeconds = durationSeconds
            self.startedAtSeconds = startedAtSeconds
            self.cpuStartedAtSeconds = cpuStartedAtSeconds
        }
    }
}
