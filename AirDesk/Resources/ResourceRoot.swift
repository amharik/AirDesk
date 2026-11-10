import Foundation

enum ResourceRootKind: String, CaseIterable, Equatable {
    case appDocuments = "app-documents"
    case userSelected = "user-selected"
}

enum ResourceRootError: Error, Equatable, LocalizedError {
    case invalidIdentifier
    case notFileURL
    case rootNotFound(String)
    case notDirectory(String)
    case deviceWideAccessDenied
    case appScopedDocumentsUnavailable
    case appScopedRootOutsideContainer

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            return "The resource root identifier is invalid."
        case .notFileURL:
            return "The resource root must be a file URL."
        case .rootNotFound(let path):
            return "The resource root does not exist: \(path)"
        case .notDirectory(let path):
            return "The resource root is not a directory: \(path)"
        case .deviceWideAccessDenied:
            return "Device-wide filesystem access is not permitted."
        case .appScopedDocumentsUnavailable:
            return "The app-scoped documents directory is unavailable."
        case .appScopedRootOutsideContainer:
            return "An app-scoped root must be inside the app documents directory."
        }
    }
}

struct ResourceRoot: Equatable {
    static let defaultAppDocumentsIdentifier = "app-documents"

    let id: String
    let kind: ResourceRootKind
    let url: URL

    init(
        id: String,
        kind: ResourceRootKind,
        url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard Self.isValidIdentifier(id) else {
            throw ResourceRootError.invalidIdentifier
        }
        guard url.isFileURL else {
            throw ResourceRootError.notFileURL
        }

        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path != "/" else {
            throw ResourceRootError.deviceWideAccessDenied
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
            throw ResourceRootError.rootNotFound(url.path)
        }
        guard isDirectory.boolValue else {
            throw ResourceRootError.notDirectory(url.path)
        }

        if kind == .appDocuments {
            guard let documents = fileManager.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first else {
                throw ResourceRootError.appScopedDocumentsUnavailable
            }
            let resolvedDocuments = documents
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard Self.isInside(resolved, root: resolvedDocuments) else {
                throw ResourceRootError.appScopedRootOutsideContainer
            }
        }

        self.id = id
        self.kind = kind
        self.url = resolved
    }

    static func appDocuments(
        id: String = defaultAppDocumentsIdentifier,
        fileManager: FileManager = .default
    ) throws -> ResourceRoot {
        guard let documents = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw ResourceRootError.appScopedDocumentsUnavailable
        }
        return try ResourceRoot(
            id: id,
            kind: .appDocuments,
            url: documents,
            fileManager: fileManager
        )
    }

    func startAccessingSecurityScope() -> Bool {
        guard kind == .userSelected else { return false }
        return url.startAccessingSecurityScopedResource()
    }

    func stopAccessingSecurityScope() {
        guard kind == .userSelected else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= 128
            && !value.contains("\0")
    }

    private static func isInside(_ url: URL, root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= rootComponents.count else { return false }
        return Array(components.prefix(rootComponents.count)) == rootComponents
    }
}
