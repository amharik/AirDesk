#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${AIRDESK_CORE_TMP:-$(mktemp -d)}"
if [ -z "${AIRDESK_CORE_TMP:-}" ]; then
  trap 'rm -rf "$TMP"' EXIT
fi

mkdir -p "$TMP/Sources/AirDeskWorkspaceCore" "$TMP/Tests/AirDeskWorkspaceCoreTests"

SOURCES=(
  "AirDesk/Workspace/WorkspaceManifest.swift"
  "AirDesk/Workspace/WorkspaceStore.swift"
  "AirDesk/Workspace/WorkspaceHost.swift"
  "AirDesk/Workspace/WorkspaceOrchestrator.swift"
  "AirDesk/Workspace/WorkspaceLayoutController.swift"
  "AirDesk/Workspace/WorkspaceBootstrapper.swift"
  "AirDesk/Workspace/WorkspaceStatusCopy.swift"
  "AirDesk/Workspace/ApplicationInstanceStatus.swift"
  "AirDesk/Workspace/RuntimeQuota.swift"
  "AirDesk/Workspace/ApplicationLifecycleController.swift"
  "AirDesk/Models/RuntimeLocation.swift"
  "AirDesk/Runtime/RuntimeState.swift"
  "AirDesk/Runtime/RuntimeProvider.swift"
  "AirDesk/Runtime/RuntimeRegistry.swift"
  "AirDesk/Input/InputEvent.swift"
  "AirDesk/Input/InputDispatcher.swift"
  "AirDesk/Input/InputProtocolV2.swift"
  "AirDesk/Input/InputLeaseManager.swift"
  "AirDesk/Protocol/PackedMovementFrame.swift"
)

TESTS=(
  "AirDeskTests/NativeWorkspaceStoreTests.swift"
  "AirDeskTests/WorkspaceManifestTests.swift"
  "AirDeskTests/WorkspaceHostTests.swift"
  "AirDeskTests/WorkspaceOrchestratorTests.swift"
  "AirDeskTests/WorkspaceLayoutControllerTests.swift"
  "AirDeskTests/WorkspaceBootstrapperTests.swift"
  "AirDeskTests/WorkspaceStatusCopyTests.swift"
  "AirDeskTests/ApplicationLifecycleControllerTests.swift"
  "AirDeskTests/RuntimeRegistryTests.swift"
  "AirDeskTests/PackedMovementFrameTests.swift"
  "AirDeskTests/InputDispatcherTests.swift"
  "AirDeskTests/InputLeaseManagerTests.swift"
)

for file in "${SOURCES[@]}"; do
  cp "$ROOT/$file" "$TMP/Sources/AirDeskWorkspaceCore/"
done

for file in "${TESTS[@]}"; do
  sed 's/@testable import AirDesk$/@testable import AirDeskWorkspaceCore/' "$ROOT/$file" \
    > "$TMP/Tests/AirDeskWorkspaceCoreTests/$(basename "$file")"
done

cat > "$TMP/Package.swift" <<'PACKAGE'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirDeskWorkspaceCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AirDeskWorkspaceCore"),
        .testTarget(
            name: "AirDeskWorkspaceCoreTests",
            dependencies: ["AirDeskWorkspaceCore"]
        )
    ]
)
PACKAGE

swift test --package-path "$TMP" "$@"
