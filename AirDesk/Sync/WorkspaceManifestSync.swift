import Foundation

enum WorkspaceManifestSyncError: Error, Equatable, LocalizedError {
    case workspaceMismatch
    case invalidField(String)

    var errorDescription: String? {
        switch self {
        case .workspaceMismatch:
            return "The sync snapshot belongs to another workspace."
        case .invalidField(let path):
            return "The sync snapshot field \(path) is invalid."
        }
    }
}

extension WorkspaceManifest {
    func syncSnapshot() throws -> WorkspaceSyncSnapshot {
        let deviceId = metadata.lastActiveDeviceId ?? owner.identityId
        func field(_ path: String, _ value: WorkspaceSyncJSONValue) -> WorkspaceSyncJSONValue {
            guard mergeMetadata.mergeClass(for: path) == .lww else { return value }
            return WorkspaceSyncLWWValue(value: value, revision: revision, deviceId: deviceId).json
        }

        var fields: [String: WorkspaceSyncJSONValue] = [:]
        fields["metadata.name"] = field("metadata.name", .string(metadata.name))
        fields["metadata.updatedAt"] = field("metadata.updatedAt", try Self.jsonValue(metadata.updatedAt))
        fields["metadata.lastActiveDeviceId"] = field(
            "metadata.lastActiveDeviceId",
            metadata.lastActiveDeviceId.map { .string($0) } ?? .null
        )
        fields["layout.displays"] = field("layout.displays", try Self.jsonValue(layout.displays))
        fields["layout.windows"] = field("layout.windows", try Self.jsonValue(layout.windows))
        fields["layout.focusOrder"] = field("layout.focusOrder", try Self.jsonValue(layout.focusOrder))
        fields["layout.activeWindowId"] = field(
            "layout.activeWindowId",
            layout.activeWindowId.map { .string($0) } ?? .null
        )
        fields["preferences"] = field("preferences", try Self.jsonValue(preferences))
        fields["applications"] = try Self.jsonValue(applications)
        fields["instances"] = try Self.jsonValue(instances)
        fields["executionBindings"] = try Self.jsonValue(executionBindings)
        fields["resources"] = try Self.jsonValue(resources)
        fields["owner"] = try Self.jsonValue(owner)

        return WorkspaceSyncSnapshot(
            workspaceId: id,
            hostEpoch: hostEpoch,
            workspaceSeq: workspaceSeq,
            revision: revision,
            fields: fields,
            metadata: mergeMetadata.fields
        )
    }

    static func applying(
        _ snapshot: WorkspaceSyncSnapshot,
        to base: WorkspaceManifest
    ) throws -> WorkspaceManifest {
        guard snapshot.workspaceId == base.id else {
            throw WorkspaceManifestSyncError.workspaceMismatch
        }

        let mergeMetadata = WorkspaceMergeMetadata(fields: snapshot.metadata)
        func payload(_ path: String, _ value: WorkspaceSyncJSONValue) -> WorkspaceSyncJSONValue {
            guard mergeMetadata.mergeClass(for: path) == .lww else { return value }
            return WorkspaceSyncLWWValue(json: value)?.value ?? value
        }

        var manifest = base
        manifest.workspaceSeq = snapshot.workspaceSeq
        manifest.revision = snapshot.revision
        manifest.hostEpoch = snapshot.hostEpoch
        manifest.mergeMetadata = mergeMetadata

        if let value = snapshot.fields["metadata.name"] {
            manifest.metadata.name = try decode(
                payload("metadata.name", value),
                as: String.self,
                path: "metadata.name"
            )
        }
        if let value = snapshot.fields["metadata.updatedAt"] {
            manifest.metadata.updatedAt = try decode(
                payload("metadata.updatedAt", value),
                as: Date.self,
                path: "metadata.updatedAt"
            )
        }
        if let value = snapshot.fields["metadata.lastActiveDeviceId"] {
            manifest.metadata.lastActiveDeviceId = try decodeOptional(
                payload("metadata.lastActiveDeviceId", value),
                as: String.self,
                path: "metadata.lastActiveDeviceId"
            )
        }
        if let value = snapshot.fields["layout.displays"] {
            manifest.layout.displays = try decode(
                payload("layout.displays", value),
                as: [WorkspaceDisplay].self,
                path: "layout.displays"
            )
        }
        if let value = snapshot.fields["layout.windows"] {
            manifest.layout.windows = try decode(
                payload("layout.windows", value),
                as: [WorkspaceWindow].self,
                path: "layout.windows"
            )
        }
        if let value = snapshot.fields["layout.focusOrder"] {
            manifest.layout.focusOrder = try decode(
                payload("layout.focusOrder", value),
                as: [String].self,
                path: "layout.focusOrder"
            )
        }
        if let value = snapshot.fields["layout.activeWindowId"] {
            manifest.layout.activeWindowId = try decodeOptional(
                payload("layout.activeWindowId", value),
                as: String.self,
                path: "layout.activeWindowId"
            )
        }
        if let value = snapshot.fields["preferences"] {
            manifest.preferences = try decode(
                payload("preferences", value),
                as: WorkspacePreferences.self,
                path: "preferences"
            )
        }
        if let value = snapshot.fields["applications"] {
            manifest.applications = try decode(
                payload("applications", value),
                as: [WorkspaceApplication].self,
                path: "applications"
            )
        }
        if let value = snapshot.fields["instances"] {
            manifest.instances = try decode(
                payload("instances", value),
                as: [WorkspaceApplicationInstance].self,
                path: "instances"
            )
        }
        if let value = snapshot.fields["executionBindings"] {
            manifest.executionBindings = try decode(
                payload("executionBindings", value),
                as: [WorkspaceExecutionBinding].self,
                path: "executionBindings"
            )
        }
        if let value = snapshot.fields["resources"] {
            manifest.resources = try decode(
                payload("resources", value),
                as: [WorkspaceResourceReference].self,
                path: "resources"
            )
        }
        if let value = snapshot.fields["owner"] {
            manifest.owner = try decode(
                payload("owner", value),
                as: WorkspaceOwner.self,
                path: "owner"
            )
        }

        return manifest
    }

    private static func jsonValue<T: Encodable>(_ value: T) throws -> WorkspaceSyncJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(WorkspaceSyncJSONValue.self, from: data)
    }

    private static func decode<T: Decodable>(
        _ value: WorkspaceSyncJSONValue,
        as type: T.Type,
        path: String
    ) throws -> T {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WorkspaceManifestSyncError.invalidField(path)
        }
    }

    private static func decodeOptional<T: Decodable>(
        _ value: WorkspaceSyncJSONValue,
        as type: T.Type,
        path: String
    ) throws -> T? {
        if value == .null { return nil }
        return try decode(value, as: type, path: path)
    }
}
