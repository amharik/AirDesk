import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class VideoToolboxEncoder: DisplayVideoEncoder {
    let codec: DisplayVideoCodec
    private let configuration: DisplayCaptureConfiguration
    private let width: Int
    private let height: Int
    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var finished = false

    private(set) var isHardwareAccelerated = false
    var onFrame: ((EncodedDisplayFrame) -> Void)?
    var onFailure: ((DisplayCaptureError) -> Void)?

    init(
        codec: DisplayVideoCodec,
        configuration: DisplayCaptureConfiguration,
        width: Int,
        height: Int
    ) throws {
        guard width > 0,
              height > 0,
              width <= configuration.maximumDimension,
              height <= configuration.maximumDimension else {
            throw DisplayCaptureError.invalidFrame("encoder dimensions")
        }
        try configuration.validate()

        self.codec = codec
        self.configuration = configuration
        self.width = width
        self.height = height

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: codec.cmCodecType,
            encoderSpecification: DisplayVideoCapabilities.hardwareSpecification,
            imageBufferAttributes: [
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: Self.compressionOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw DisplayCaptureError.encoderUnavailable(
                "VideoToolbox session creation failed (\(status))"
            )
        }

        do {
            try Self.configure(session, codec: codec, configuration: configuration)
        } catch {
            VTCompressionSessionInvalidate(session)
            throw error
        }

        self.session = session
        var property: CFTypeRef?
        let propertyStatus = VTSessionCopyProperty(
            session,
            key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
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

    func encode(
        _ frame: DisplayCaptureFrame,
        forceKeyframe: Bool
    ) throws {
        lock.lock()
        guard !finished, let session else {
            lock.unlock()
            throw DisplayCaptureError.finished
        }
        lock.unlock()

        guard frame.width == width, frame.height == height else {
            throw DisplayCaptureError.invalidFrame("encoder dimensions changed")
        }

        let metadata = FrameMetadata(
            sequence: frame.sequence,
            timestampSeconds: frame.timestampSeconds,
            durationSeconds: frame.durationSeconds
        )
        let refCon = Unmanaged.passRetained(metadata).toOpaque()
        let frameProperties: CFDictionary? = forceKeyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        var infoFlags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: frame.pixelBuffer,
            presentationTimeStamp: CMTime(
                seconds: frame.timestampSeconds,
                preferredTimescale: 600
            ),
            duration: CMTime(
                seconds: frame.durationSeconds,
                preferredTimescale: 600
            ),
            frameProperties: frameProperties,
            sourceFrameRefcon: refCon,
            infoFlagsOut: &infoFlags
        )

        if status != noErr {
            Unmanaged<FrameMetadata>.fromOpaque(refCon).release()
            throw DisplayCaptureError.encoderFailure(
                "VideoToolbox encode failed (\(status))"
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
        VTCompressionSessionCompleteFrames(
            session,
            untilPresentationTimeStamp: .invalid
        )
        VTCompressionSessionInvalidate(session)
    }

    private static func configure(
        _ session: VTCompressionSession,
        codec: DisplayVideoCodec,
        configuration: DisplayCaptureConfiguration
    ) throws {
        try setProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: NSNumber(value: true)
        )
        try setProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: NSNumber(value: false)
        )
        try setProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: NSNumber(value: configuration.framesPerSecond)
        )
        try setProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: NSNumber(value: configuration.keyframeIntervalFrames)
        )
        try setProperty(
            session,
            key: kVTCompressionPropertyKey_MaxFrameDelayCount,
            value: NSNumber(value: 1)
        )
        try setProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: NSNumber(value: configuration.averageBitRate)
        )

        switch codec {
        case .hevc:
            try setProperty(
                session,
                key: kVTCompressionPropertyKey_ProfileLevel,
                value: kVTProfileLevel_HEVC_Main_AutoLevel
            )
        case .h264:
            try setProperty(
                session,
                key: kVTCompressionPropertyKey_ProfileLevel,
                value: kVTProfileLevel_H264_High_AutoLevel
            )
        case .av1:
            break
        }
    }

    private static func setProperty(
        _ session: VTCompressionSession,
        key: CFString,
        value: CFTypeRef
    ) throws {
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else {
            throw DisplayCaptureError.encoderConfigurationFailed(
                String(describing: key)
            )
        }
    }

    private static let compressionOutputCallback: VTCompressionOutputCallback = {
        refCon,
        sourceFrameRefCon,
        status,
        infoFlags,
        sampleBuffer in
        _ = infoFlags
        guard let refCon else { return }
        let encoder = Unmanaged<VideoToolboxEncoder>
            .fromOpaque(refCon)
            .takeUnretainedValue()
        encoder.handleCompressionOutput(
            status: status,
            sampleBuffer: sampleBuffer,
            sourceFrameRefCon: sourceFrameRefCon
        )
    }

    private func handleCompressionOutput(
        status: OSStatus,
        sampleBuffer: CMSampleBuffer?,
        sourceFrameRefCon: UnsafeMutableRawPointer?
    ) {
        let metadata = sourceFrameRefCon.map {
            Unmanaged<FrameMetadata>.fromOpaque($0).takeRetainedValue()
        }

        guard status == noErr else {
            onFailure?(.encoderFailure("VideoToolbox encode failed (\(status))"))
            return
        }
        guard let sampleBuffer, let metadata else {
            onFailure?(.encoderFailure("VideoToolbox returned no frame"))
            return
        }
        guard let frame = makeFrame(sampleBuffer, metadata: metadata) else {
            onFailure?(.encoderFailure("VideoToolbox frame parsing failed"))
            return
        }

        lock.lock()
        let finished = self.finished
        lock.unlock()
        guard !finished else { return }
        onFrame?(frame)
    }

    private func makeFrame(
        _ sampleBuffer: CMSampleBuffer,
        metadata: FrameMetadata
    ) -> EncodedDisplayFrame? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0 else {
            return nil
        }
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0 else { return nil }

        var data = Data(count: length)
        let copyStatus: OSStatus = data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return OSStatus(-1)
            }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: length,
                destination: baseAddress
            )
        }
        guard copyStatus == noErr else { return nil }

        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = presentation.isValid
            ? CMTimeGetSeconds(presentation)
            : metadata.timestampSeconds
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let durationSeconds = duration.isValid && !duration.isIndefinite
            ? CMTimeGetSeconds(duration)
            : metadata.durationSeconds
        let (parameterSets, nalUnitHeaderLength) = parameterSets(from: format)
        guard !parameterSets.isEmpty else { return nil }

        return EncodedDisplayFrame(
            sequence: metadata.sequence,
            timestampSeconds: timestamp,
            durationSeconds: durationSeconds,
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            codec: codec,
            isKeyframe: isKeyframe(sampleBuffer),
            data: data,
            parameterSets: parameterSets,
            nalUnitHeaderLength: nalUnitHeaderLength
        )
    }

    private func parameterSets(
        from format: CMVideoFormatDescription
    ) -> ([Data], Int) {
        var count = 0
        var nalUnitHeaderLength: Int32 = 4
        var sets: [Data] = []

        switch codec {
        case .hevc:
            let countStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &nalUnitHeaderLength
            )
            guard countStatus == noErr, (1...16).contains(count) else {
                return ([], 4)
            }
            for index in 0..<count {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    format,
                    parameterSetIndex: index,
                    parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                guard status == noErr, let pointer, size > 0 else {
                    return ([], 4)
                }
                sets.append(Data(bytes: pointer, count: size))
            }
        case .h264:
            let countStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &nalUnitHeaderLength
            )
            guard countStatus == noErr, (1...16).contains(count) else {
                return ([], 4)
            }
            for index in 0..<count {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                let status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    format,
                    parameterSetIndex: index,
                    parameterSetPointerOut: &pointer,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                guard status == noErr, let pointer, size > 0 else {
                    return ([], 4)
                }
                sets.append(Data(bytes: pointer, count: size))
            }
        case .av1:
            return ([], 4)
        }

        return (sets, Int(nalUnitHeaderLength))
    }

    private func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[CFString: Any]],
            let first = attachments.first else {
            return true
        }
        let notSync = (first[kCMSampleAttachmentKey_NotSync] as? NSNumber)?.boolValue
            ?? false
        return !notSync
    }

    private final class FrameMetadata {
        let sequence: UInt64
        let timestampSeconds: Double
        let durationSeconds: Double

        init(
            sequence: UInt64,
            timestampSeconds: Double,
            durationSeconds: Double
        ) {
            self.sequence = sequence
            self.timestampSeconds = timestampSeconds
            self.durationSeconds = durationSeconds
        }
    }
}
