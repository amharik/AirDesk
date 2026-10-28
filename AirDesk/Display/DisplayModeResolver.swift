import Foundation

enum DisplayModeResolver {
    static func resolvedMode(
        for kind: DisplayKind,
        hasExternalDisplay: Bool,
        isMirroring: Bool
    ) -> SessionMode {
        if isMirroring, kind != .cast, kind != .preview {
            return .mirrored
        }
        if hasExternalDisplay, kind != .cast, kind != .preview {
            return .extended
        }
        switch kind {
        case .cast: return .cast
        case .preview: return .preview
        case .airPlay: return .mirrored
        case .wired, .external: return .extended
        }
    }

    static func effectiveMode(
        current: SessionMode,
        hasExternalDisplay: Bool,
        isMirroring: Bool
    ) -> SessionMode {
        if isMirroring, current != .cast {
            return .mirrored
        }
        if hasExternalDisplay, current != .cast {
            return .extended
        }
        return current
    }

    static func fallbackMode(
        for kind: DisplayKind?,
        hasExternalDisplay: Bool,
        isMirroring: Bool
    ) -> SessionMode {
        guard let kind else { return .preview }
        if kind == .cast { return .cast }
        if hasExternalDisplay { return .extended }
        if isMirroring { return .mirrored }
        return .preview
    }
}
