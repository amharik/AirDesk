@preconcurrency import AVFoundation
import Foundation

struct CameraCaptureConfiguration: Equatable, Sendable {
    static let standard = CameraCaptureConfiguration(
        width: 1_280,
        height: 720,
        framesPerSecond: 30,
        maximumFrameBytes: 4 * 1_024 * 1_024
    )

    var width: Int
    var height: Int
    var framesPerSecond: Int
    var maximumFrameBytes: Int

    func validate() throws {
        guard (1...4_096).contains(width), (1...4_096).contains(height) else {
            throw CameraCaptureError.invalidConfiguration("frame dimensions")
        }
        guard (1...60).contains(framesPerSecond) else {
            throw CameraCaptureError.invalidConfiguration("frame rate")
        }
        guard (1...64 * 1_024 * 1_024).contains(maximumFrameBytes) else {
            throw CameraCaptureError.invalidConfiguration("maximum frame bytes")
        }
    }
}

struct CameraFrame: Equatable, Sendable {
    let sequence: UInt64
    let timestampSeconds: Double
    let width: Int
    let height: Int
    let pixelFormat: UInt32
    let bytes: Data
}

enum CameraCaptureError: Error, Equatable, LocalizedError {
    case invalidConfiguration(String)
    case invalidRequest(String)
    case permissionNotDetermined
    case permissionDenied(String)
    case permissionRestricted
    case cameraUnavailable
    case authorizationDenied
    case authorizationRevoked
    case leaseExpired
    case capabilityBusy
    case capabilityRestricted
    case agentUnavailable
    case alreadyRunning
    case finished
    case sourceFailure(String)
    case cancelled

    init(deviceAgentError error: DeviceAgentError) {
        switch error {
        case .authorizationDenied:
            self = .authorizationDenied
        case .authorizationRevoked:
            self = .authorizationRevoked
        case .platformPermissionDenied(let permission):
            self = .permissionDenied(permission)
        case .capabilityUnavailable:
            self = .cameraUnavailable
        case .capabilityUnknown(let capUri):
            self = .invalidRequest("unknown capability: \(capUri)")
        case .capabilityBusy:
            self = .capabilityBusy
        case .capabilityRestricted:
            self = .capabilityRestricted
        case .agentUnavailable:
            self = .agentUnavailable
        case .operationNotAllowed(let operation):
            self = .invalidRequest("operation not allowed: \(operation)")
        case .leaseNotFound(let leaseId):
            self = .invalidRequest("lease not found: \(leaseId)")
        default:
            self = .authorizationDenied
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let field):
            return "The camera configuration is invalid: \(field)."
        case .invalidRequest(let reason):
            return "The camera capture request is invalid: \(reason)."
        case .permissionNotDetermined:
            return "Camera permission has not been determined."
        case .permissionDenied(let permission):
            return "The camera permission \(permission) is denied."
        case .permissionRestricted:
            return "Camera access is restricted by the system."
        case .cameraUnavailable:
            return "No camera is available for capture."
        case .authorizationDenied:
            return "The device agent did not authorize camera capture."
        case .authorizationRevoked:
            return "Camera capture authorization was revoked."
        case .leaseExpired:
            return "The camera capture lease expired."
        case .capabilityBusy:
            return "The camera capability is busy."
        case .capabilityRestricted:
            return "The camera capability is restricted by policy."
        case .agentUnavailable:
            return "The device agent is unavailable."
        case .alreadyRunning:
            return "Camera capture is already running."
        case .finished:
            return "The camera capture stream has already finished."
        case .sourceFailure(let reason):
            return "The camera source failed: \(reason)."
        case .cancelled:
            return "Camera capture was cancelled."
        }
    }
}

@MainActor
protocol CameraCaptureSource: AnyObject {
    var isAvailable: Bool { get }
    var permissionStatus: CameraPermissionStatus { get }

    func start(
        configuration: CameraCaptureConfiguration,
        onFrame: @escaping @MainActor (CameraFrame) -> Void
    ) async throws

    func stop() async
}

@MainActor
final class AVFoundationCameraCaptureSource: CameraCaptureSource {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.airdesk.camera.session")
    private let videoQueue = DispatchQueue(
        label: "com.airdesk.camera.frames",
        qos: .userInitiated
    )
    private let output = AVCaptureVideoDataOutput()
    private let frameDelegate = FrameDelegate()
    private var running = false

    init() {
        output.setSampleBufferDelegate(frameDelegate, queue: videoQueue)
    }

    var isAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var permissionStatus: CameraPermissionStatus {
        CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func start(
        configuration: CameraCaptureConfiguration,
        onFrame: @escaping @MainActor (CameraFrame) -> Void
    ) async throws {
        try configuration.validate()
        guard !running else { throw CameraCaptureError.alreadyRunning }
        guard isAvailable else { throw CameraCaptureError.cameraUnavailable }
        switch permissionStatus {
        case .authorized:
            break
        case .notDetermined:
            throw CameraCaptureError.permissionNotDetermined
        case .denied:
            throw CameraCaptureError.permissionDenied(CapabilityCatalog.cameraPermission)
        case .restricted:
            throw CameraCaptureError.permissionRestricted
        }

        frameDelegate.configure(
            maximumFrameBytes: configuration.maximumFrameBytes,
            handler: onFrame
        )
        do {
            try await configureSession(configuration)
        } catch {
            frameDelegate.configure(maximumFrameBytes: 0, handler: nil)
            throw error
        }
        running = true
    }

    func stop() async {
        guard running else { return }
        running = false
        frameDelegate.configure(maximumFrameBytes: 0, handler: nil)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                if session.isRunning {
                    session.stopRunning()
                }
                continuation.resume()
            }
        }
    }

    private func configureSession(
        _ configuration: CameraCaptureConfiguration
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [session, output] in
                session.beginConfiguration()
                do {
                    for input in session.inputs {
                        session.removeInput(input)
                    }
                    for existingOutput in session.outputs {
                        session.removeOutput(existingOutput)
                    }

                    guard let device = AVCaptureDevice.default(
                        .builtInWideAngleCamera,
                        for: .video,
                        position: .back
                    ) ?? AVCaptureDevice.default(for: .video) else {
                        throw CameraCaptureError.cameraUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        throw CameraCaptureError.cameraUnavailable
                    }
                    session.addInput(input)

                    if session.canSetSessionPreset(.hd1280x720) {
                        session.sessionPreset = .hd1280x720
                    }

                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                    ]
                    guard session.canAddOutput(output) else {
                        throw CameraCaptureError.cameraUnavailable
                    }
                    session.addOutput(output)

                    if let connection = output.connection(with: .video),
                       connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }

                    try Self.applyFrameRate(
                        configuration.framesPerSecond,
                        to: device
                    )

                    session.commitConfiguration()
                    session.startRunning()
                    continuation.resume()
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func applyFrameRate(
        _ framesPerSecond: Int,
        to device: AVCaptureDevice
    ) throws {
        let supportsRate = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.maxFrameRate >= Double(framesPerSecond)
                && $0.minFrameRate <= Double(framesPerSecond)
        }
        guard supportsRate else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    private final class FrameDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        private let lock = NSLock()
        private var maximumFrameBytes = 0
        private var sequence: UInt64 = 0
        private var handler: (@MainActor (CameraFrame) -> Void)?

        func configure(
            maximumFrameBytes: Int,
            handler: (@MainActor (CameraFrame) -> Void)?
        ) {
            lock.lock()
            self.maximumFrameBytes = maximumFrameBytes
            self.sequence = 0
            self.handler = handler
            lock.unlock()
        }

        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            _ = output
            _ = connection
            guard let frame = makeFrame(from: sampleBuffer) else { return }
            lock.lock()
            let maximumFrameBytes = self.maximumFrameBytes
            guard maximumFrameBytes > 0, frame.bytes.count <= maximumFrameBytes else {
                lock.unlock()
                return
            }
            sequence &+= 1
            let sequencedFrame = CameraFrame(
                sequence: sequence,
                timestampSeconds: frame.timestampSeconds,
                width: frame.width,
                height: frame.height,
                pixelFormat: frame.pixelFormat,
                bytes: frame.bytes
            )
            let handler = self.handler
            lock.unlock()
            guard let handler else { return }
            Task { @MainActor in
                handler(sequencedFrame)
            }
        }

        private func makeFrame(from sampleBuffer: CMSampleBuffer) -> CameraFrame? {
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return nil
            }
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            let rowBytes = width * 4
            guard width > 0, height > 0, bytesPerRow >= rowBytes else { return nil }
            guard CVPixelBufferLockBaseAddress(imageBuffer, .readOnly) == kCVReturnSuccess else {
                return nil
            }
            defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else {
                return nil
            }

            var bytes = Data()
            bytes.reserveCapacity(rowBytes * height)
            for row in 0..<height {
                let rowAddress = baseAddress
                    .advanced(by: row * bytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)
                bytes.append(rowAddress, count: rowBytes)
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let timestamp = presentationTime.isValid
                ? CMTimeGetSeconds(presentationTime)
                : Date().timeIntervalSince1970
            return CameraFrame(
                sequence: 0,
                timestampSeconds: timestamp,
                width: width,
                height: height,
                pixelFormat: CVPixelBufferGetPixelFormatType(imageBuffer),
                bytes: bytes
            )
        }
    }
}
