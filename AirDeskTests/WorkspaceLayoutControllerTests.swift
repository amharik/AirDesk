import XCTest
@testable import AirDesk

final class WorkspaceLayoutControllerTests: XCTestCase {
    func testUpsertDisplayAndWindowPersistAcrossReload() throws {
        let (controller, _, _, directory) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow())

        let reloadedStore = try NativeWorkspaceStore(directory: directory)
        let reloadedHost = try WorkspaceHost(store: reloadedStore, deviceId: "device.test")
        let reloadedController = WorkspaceLayoutController(host: reloadedHost)

        XCTAssertEqual(try reloadedController.layout(), try controller.layout())
        XCTAssertEqual(try reloadedController.layout().windows.first?.id, "window.terminal")
    }

    func testMoveAndResizeUpdatesWindowAndPersists() throws {
        let (controller, _, _, directory) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow())
        let moved = WorkspaceRect(x: 120, y: 220, width: 800, height: 600)

        _ = try controller.moveAndResize(
            windowId: "window.terminal",
            displayId: "display.main",
            bounds: moved,
            isMinimized: true
        )

        let reloadedStore = try NativeWorkspaceStore(directory: directory)
        let reloadedHost = try WorkspaceHost(store: reloadedStore, deviceId: "device.test")
        let window = try WorkspaceLayoutController(host: reloadedHost).layout().windows.first
        XCTAssertEqual(window?.bounds, moved)
        XCTAssertEqual(window?.displayId, "display.main")
        XCTAssertEqual(window?.isMinimized, true)
    }

    func testFocusMovesWindowToEndAndSetsActive() throws {
        let (controller, _, _, _) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow(id: "window.first"))
        _ = try controller.upsertWindow(makeWindow(id: "window.second"))

        var manifest = try controller.focus(windowId: "window.first")
        XCTAssertEqual(manifest.layout.focusOrder, ["window.first"])
        XCTAssertEqual(manifest.layout.activeWindowId, "window.first")

        manifest = try controller.focus(windowId: "window.second")
        XCTAssertEqual(manifest.layout.focusOrder, ["window.first", "window.second"])
        XCTAssertEqual(manifest.layout.activeWindowId, "window.second")

        manifest = try controller.focus(windowId: "window.first")
        XCTAssertEqual(manifest.layout.focusOrder, ["window.second", "window.first"])
        XCTAssertEqual(manifest.layout.activeWindowId, "window.first")
    }

    func testMinimizeWindowUpdatesPersistedValue() throws {
        let (controller, _, _, _) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow())

        let manifest = try controller.setMinimized(windowId: "window.terminal", isMinimized: true)

        XCTAssertEqual(manifest.layout.windows.first?.isMinimized, true)
    }

    func testRemoveWindowClearsFocusAndActiveWindow() throws {
        let (controller, _, _, _) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow())
        _ = try controller.focus(windowId: "window.terminal")

        let manifest = try controller.removeWindow(id: "window.terminal")

        XCTAssertTrue(manifest.layout.windows.isEmpty)
        XCTAssertTrue(manifest.layout.focusOrder.isEmpty)
        XCTAssertNil(manifest.layout.activeWindowId)
    }

    func testRemoveDisplayRejectsDisplayInUse() throws {
        let (controller, _, _, _) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow())

        XCTAssertThrowsError(try controller.removeDisplay(id: "display.main")) { error in
            XCTAssertEqual(
                error as? WorkspaceLayoutError,
                .displayInUse("display.main")
            )
        }
    }

    func testUpsertWindowRequiresExistingInstance() throws {
        let (controller, _, _, _) = try makeFixture()

        XCTAssertThrowsError(try controller.upsertWindow(
            makeWindow(id: "window.unknown", instanceId: "instance.unknown")
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceLayoutError,
                .instanceMissing("instance.unknown")
            )
        }
    }

    func testUpsertWindowRequiresExistingDisplay() throws {
        let (controller, _, _, _) = try makeFixture()

        XCTAssertThrowsError(try controller.upsertWindow(
            makeWindow(displayId: "display.unknown")
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceLayoutError,
                .displayMissing("display.unknown")
            )
        }
    }

    func testUpsertWindowRejectsEmptySurface() throws {
        let (controller, _, _, _) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())

        XCTAssertThrowsError(try controller.upsertWindow(
            makeWindow(surface: "")
        )) { error in
            XCTAssertEqual(
                error as? WorkspaceLayoutError,
                .invalidWindow("window.terminal")
            )
        }
    }

    func testLayoutOperationsIncrementWorkspaceSequence() throws {
        let (controller, host, _, _) = try makeFixture()
        _ = try controller.upsertDisplay(makeDisplay())
        _ = try controller.upsertWindow(makeWindow())
        let before = try XCTUnwrap(host.workspaceSeq)

        let manifest = try controller.focus(windowId: "window.terminal")

        XCTAssertEqual(manifest.workspaceSeq, before + 1)
        XCTAssertEqual(host.workspaceSeq, before + 1)
    }

    func testRemovingMissingDisplayAndWindowIsRejected() throws {
        let (controller, _, _, _) = try makeFixture()

        XCTAssertThrowsError(try controller.removeDisplay(id: "display.unknown")) { error in
            XCTAssertEqual(
                error as? WorkspaceLayoutError,
                .displayMissing("display.unknown")
            )
        }
        XCTAssertThrowsError(try controller.removeWindow(id: "window.unknown")) { error in
            XCTAssertEqual(
                error as? WorkspaceLayoutError,
                .windowMissing("window.unknown")
            )
        }
    }

    private func makeFixture() throws -> (WorkspaceLayoutController, WorkspaceHost, NativeWorkspaceStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskWorkspaceLayoutTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let store = try NativeWorkspaceStore(directory: directory)
        let host = try WorkspaceHost(store: store, deviceId: "device.test")
        let orchestrator = WorkspaceOrchestrator(host: host)
        _ = try orchestrator.open(
            owner: WorkspaceOwner(identityId: "person.test", displayName: "Tester"),
            name: "Layout Test",
            id: "workspace.layout"
        )

        guard let current = try host.load() else {
            throw WorkspaceLayoutError.workspaceMissing
        }
        _ = try host.mutate(expectedWorkspaceSeq: current.workspaceSeq) { manifest in
            manifest.applications = [makeApplication()]
            manifest.instances = [makeInstance()]
        }

        return (WorkspaceLayoutController(host: host), host, store, directory)
    }

    private func makeDisplay() -> WorkspaceDisplay {
        WorkspaceDisplay(
            id: "display.main",
            name: "Main",
            bounds: WorkspaceRect(x: 0, y: 0, width: 1920, height: 1080),
            isPrimary: true
        )
    }

    private func makeWindow(
        id: String = "window.terminal",
        instanceId: String = "instance.terminal",
        displayId: String = "display.main",
        surface: String = "surface.terminal"
    ) -> WorkspaceWindow {
        WorkspaceWindow(
            id: id,
            instanceId: instanceId,
            displayId: displayId,
            bounds: WorkspaceRect(x: 10, y: 20, width: 640, height: 480),
            isMinimized: false,
            surface: surface
        )
    }

    private func makeApplication() -> WorkspaceApplication {
        WorkspaceApplication(
            id: "app.terminal",
            version: "1.0.0",
            name: "Terminal",
            entrypoint: "terminal.wasm",
            runtimeTargets: [
                WorkspaceRuntimeTarget(provider: "wanix", world: "wasip1", architectures: ["wasm32"])
            ],
            requiredCapabilities: [],
            presentation: .foreground,
            permissions: [],
            quotas: nil
        )
    }

    private func makeInstance() -> WorkspaceApplicationInstance {
        WorkspaceApplicationInstance(
            id: "instance.terminal",
            applicationId: "app.terminal",
            desiredState: .running,
            placement: nil,
            configuration: [:]
        )
    }
}
