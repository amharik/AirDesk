import Foundation

final class WorkspaceLayoutController {
    let host: WorkspaceHost

    init(host: WorkspaceHost) {
        self.host = host
    }

    func layout() throws -> WorkspaceLayout {
        guard let manifest = try loadManifest() else {
            throw WorkspaceLayoutError.workspaceMissing
        }
        return manifest.layout
    }

    @discardableResult
    func upsertDisplay(_ display: WorkspaceDisplay) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            if let index = manifest.layout.displays.firstIndex(where: { $0.id == display.id }) {
                manifest.layout.displays[index] = display
            } else {
                manifest.layout.displays.append(display)
            }
        }
    }

    @discardableResult
    func removeDisplay(id: String) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            guard manifest.layout.displays.contains(where: { $0.id == id }) else {
                throw WorkspaceLayoutError.displayMissing(id)
            }
            guard !manifest.layout.windows.contains(where: { $0.displayId == id }) else {
                throw WorkspaceLayoutError.displayInUse(id)
            }
            manifest.layout.displays.removeAll { $0.id == id }
        }
    }

    @discardableResult
    func upsertWindow(_ window: WorkspaceWindow) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            try validateWindowReferences(window, in: manifest)
            if let index = manifest.layout.windows.firstIndex(where: { $0.id == window.id }) {
                manifest.layout.windows[index] = window
            } else {
                manifest.layout.windows.append(window)
            }
        }
    }

    @discardableResult
    func moveAndResize(
        windowId: String,
        displayId: String,
        bounds: WorkspaceRect,
        isMinimized: Bool? = nil
    ) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            guard let index = manifest.layout.windows.firstIndex(where: { $0.id == windowId }) else {
                throw WorkspaceLayoutError.windowMissing(windowId)
            }
            guard displayId.isEmpty || manifest.layout.displays.contains(where: { $0.id == displayId }) else {
                throw WorkspaceLayoutError.displayMissing(displayId)
            }

            manifest.layout.windows[index].displayId = displayId
            manifest.layout.windows[index].bounds = bounds
            if let isMinimized {
                manifest.layout.windows[index].isMinimized = isMinimized
            }
        }
    }

    @discardableResult
    func setMinimized(windowId: String, isMinimized: Bool) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            guard let index = manifest.layout.windows.firstIndex(where: { $0.id == windowId }) else {
                throw WorkspaceLayoutError.windowMissing(windowId)
            }
            manifest.layout.windows[index].isMinimized = isMinimized
        }
    }

    @discardableResult
    func focus(windowId: String) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            guard manifest.layout.windows.contains(where: { $0.id == windowId }) else {
                throw WorkspaceLayoutError.windowMissing(windowId)
            }
            manifest.layout.focusOrder.removeAll { $0 == windowId }
            manifest.layout.focusOrder.append(windowId)
            manifest.layout.activeWindowId = windowId
        }
    }

    @discardableResult
    func removeWindow(id: String) throws -> WorkspaceManifest {
        try mutateWorkspace { manifest in
            guard manifest.layout.windows.contains(where: { $0.id == id }) else {
                throw WorkspaceLayoutError.windowMissing(id)
            }
            manifest.layout.windows.removeAll { $0.id == id }
            manifest.layout.focusOrder.removeAll { $0 == id }
            if manifest.layout.activeWindowId == id {
                manifest.layout.activeWindowId = nil
            }
        }
    }

    private func mutateWorkspace(
        _ body: (inout WorkspaceManifest) throws -> Void
    ) throws -> WorkspaceManifest {
        guard let current = try loadManifest() else {
            throw WorkspaceLayoutError.workspaceMissing
        }

        do {
            return try host.mutate(expectedWorkspaceSeq: current.workspaceSeq, body)
        } catch let error as WorkspaceHostError {
            throw WorkspaceLayoutError.host(error)
        }
    }

    private func loadManifest() throws -> WorkspaceManifest? {
        do {
            return try host.load()
        } catch let error as WorkspaceHostError {
            throw WorkspaceLayoutError.host(error)
        }
    }

    private func validateWindowReferences(
        _ window: WorkspaceWindow,
        in manifest: WorkspaceManifest
    ) throws {
        guard !window.surface.isEmpty else {
            throw WorkspaceLayoutError.invalidWindow(window.id)
        }
        guard manifest.instances.contains(where: { $0.id == window.instanceId }) else {
            throw WorkspaceLayoutError.instanceMissing(window.instanceId)
        }
        guard !window.displayId.isEmpty else {
            return
        }
        guard manifest.layout.displays.contains(where: { $0.id == window.displayId }) else {
            throw WorkspaceLayoutError.displayMissing(window.displayId)
        }
    }
}

enum WorkspaceLayoutError: Error, Equatable, LocalizedError {
    case workspaceMissing
    case displayMissing(String)
    case displayInUse(String)
    case windowMissing(String)
    case instanceMissing(String)
    case invalidWindow(String)
    case host(WorkspaceHostError)

    var errorDescription: String? {
        switch self {
        case .workspaceMissing:
            return "No workspace exists yet."
        case .displayMissing(let displayId):
            return "Display \(displayId) does not exist."
        case .displayInUse(let displayId):
            return "Display \(displayId) still has windows."
        case .windowMissing(let windowId):
            return "Window \(windowId) does not exist."
        case .instanceMissing(let instanceId):
            return "Application instance \(instanceId) does not exist."
        case .invalidWindow(let windowId):
            return "Window \(windowId) is invalid."
        case .host(let error):
            return error.localizedDescription
        }
    }
}
