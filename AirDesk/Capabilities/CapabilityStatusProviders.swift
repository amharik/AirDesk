import AVFoundation
import Foundation

enum CameraPermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

protocol CameraCapabilityProviding {
    var hardwareAvailable: Bool { get }
    var permissionStatus: CameraPermissionStatus { get }
    func requestPermission() async -> CameraPermissionStatus
}

struct AVCameraCapabilityProvider: CameraCapabilityProviding {
    var hardwareAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var permissionStatus: CameraPermissionStatus {
        CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestPermission() async -> CameraPermissionStatus {
        let granted: Bool = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            return CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
        }
        return .authorized
    }
}

protocol FileAccessCapabilityProviding {
    var appScopedDocumentsAvailable: Bool { get }
}

struct SystemFileAccessCapabilityProvider: FileAccessCapabilityProviding {
    var appScopedDocumentsAvailable: Bool {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first != nil
    }
}
