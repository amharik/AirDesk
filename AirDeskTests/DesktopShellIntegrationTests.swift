import WebKit
import XCTest
@testable import AirDesk

@MainActor
final class DesktopShellIntegrationTests: XCTestCase {
    private var webView: WKWebView!
    private var window: UIWindow!

    override func tearDown() async throws {
        webView = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    func testBridgeDragMovesDesktopWindow() async throws {
        try await loadShell()

        let setup = try await evaluate("""
        (function () {
          var candidates = Array.prototype.slice.call(document.querySelectorAll('.window'));
          var win = null;
          var cx = 0;
          var cy = 0;
          candidates.forEach(function (candidate) {
            if (win) return;
            var titlebar = candidate.querySelector('.titlebar');
            if (!titlebar) return;
            var box = titlebar.getBoundingClientRect();
            var x = box.left + box.width / 2;
            var y = box.top + box.height / 2;
            var hit = document.elementFromPoint(x, y);
            if (hit && hit.closest('.window') === candidate && hit.closest('.titlebar')) {
              win = candidate;
              cx = x;
              cy = y;
            }
          });
          if (!win) return 'missing-window';
          var startX = cx / window.innerWidth;
          var startY = cy / window.innerHeight;
          window.__airDeskDragTest = {
            win: win,
            startX: startX,
            startY: startY,
            endX: Math.min(1, startX + 0.08),
            endY: Math.min(1, startY + 0.05),
            before: { left: win.offsetLeft, top: win.offsetTop }
          };
          return JSON.stringify({
            before: window.__airDeskDragTest.before,
            manager: document.body.getAttribute('data-window-manager'),
            viewport: { width: window.innerWidth, height: window.innerHeight }
          });
        })();
        """)

        let setupData = try XCTUnwrap(setup as? String).data(using: .utf8)
        let setupPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(setupData)) as? [String: Any])
        let before = try XCTUnwrap(setupPayload["before"] as? [String: Any])
        let viewport = try XCTUnwrap(setupPayload["viewport"] as? [String: Any])
        XCTAssertEqual(setupPayload["manager"] as? String, "winbox")
        XCTAssertEqual(viewport["width"] as? Int, 1024)
        XCTAssertEqual(viewport["height"] as? Int, 768)

        _ = try await evaluate("""
        (function () {
          var drag = window.__airDeskDragTest;
          window.AirDeskBridge.receive({ type: 'pointerDown', x: drag.startX, y: drag.startY });
          window.AirDeskBridge.receive({ type: 'pointerMove', x: drag.endX, y: drag.endY });
          return true;
        })();
        """)

        try await Task.sleep(nanoseconds: 250_000_000)

        let moved = try await evaluate("""
        (function () {
          var win = window.__airDeskDragTest.win;
          return JSON.stringify({ left: win.offsetLeft, top: win.offsetTop });
        })();
        """)
        let movedData = try XCTUnwrap(moved as? String).data(using: .utf8)
        let after = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(movedData)) as? [String: Any])
        let beforeLeft = try XCTUnwrap(before["left"] as? Int)
        let beforeTop = try XCTUnwrap(before["top"] as? Int)
        let afterLeft = try XCTUnwrap(after["left"] as? Int)
        let afterTop = try XCTUnwrap(after["top"] as? Int)
        XCTAssertTrue(afterLeft != beforeLeft || afterTop != beforeTop, "window did not move: before=\(before) after=\(after)")

        _ = try await evaluate("""
        (function () {
          var drag = window.__airDeskDragTest;
          window.AirDeskBridge.receive({ type: 'pointerUp', x: drag.endX, y: drag.endY });
          delete window.__airDeskDragTest;
          return true;
        })();
        """)
    }

    func testBridgeClickSelectsDesktopIconAtPointer() async throws {
        try await loadShell()

        let result = try await evaluate("""
        (function () {
          Array.prototype.forEach.call(document.querySelectorAll('.window'), function (win) {
            win.style.pointerEvents = 'none';
          });
          var icons = Array.prototype.slice.call(document.querySelectorAll('.desktop-icon'));
          var icon = null;
          var x = 0;
          var y = 0;
          icons.forEach(function (candidate) {
            if (icon) return;
            var box = candidate.getBoundingClientRect();
            var cx = box.left + box.width / 2;
            var cy = box.top + box.height / 2;
            var hit = document.elementFromPoint(cx, cy);
            if (hit && hit.closest('.desktop-icon') === candidate) {
              icon = candidate;
              x = cx;
              y = cy;
            }
          });
          if (!icon) return JSON.stringify({ error: 'no-visible-icon' });
          var cursor = document.getElementById('cursor');
          var transformBefore = cursor ? cursor.style.transform : '';
          window.AirDeskBridge.receive({ type: 'pointerClick', x: x / window.innerWidth, y: y / window.innerHeight, clickCount: 1 });
          var selected = icon.classList.contains('selected');
          var transformAfter = cursor ? cursor.style.transform : '';
          window.AirDeskBridge.receive({ type: 'pointerClick' });
          var transformAfterMissing = cursor ? cursor.style.transform : '';
          return JSON.stringify({
            selected: selected,
            app: icon.getAttribute('data-desktop-app'),
            transformBefore: transformBefore,
            transformAfter: transformAfter,
            transformAfterMissing: transformAfterMissing,
            point: { x: x, y: y }
          });
        })();
        """)

        let data = try XCTUnwrap(result as? String).data(using: .utf8)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any])
        XCTAssertEqual(payload["selected"] as? Bool, true, "icon click did not select: \(payload)")
        let after = try XCTUnwrap(payload["transformAfter"] as? String)
        XCTAssertTrue(after.contains("translate3d("), "cursor did not move: \(payload)")
        XCTAssertFalse(after.contains("translate3d(0px,0px"), "cursor moved to 0,0: \(payload)")
        XCTAssertEqual(payload["transformAfterMissing"] as? String, after, "click without coordinates moved the cursor: \(payload)")
    }

    private func loadShell() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        let window = UIWindow(frame: webView.frame)
        window.rootViewController = UIViewController()
        window.addSubview(webView)
        window.makeKeyAndVisible()
        self.webView = webView
        self.window = window

        let directory = try XCTUnwrap(Bundle.main.url(forResource: "DesktopShell", withExtension: nil))
        webView.loadFileURL(
            directory.appendingPathComponent("index.html"),
            allowingReadAccessTo: directory
        )

        let ready = try await waitFor("""
        (function () {
          var boot = document.getElementById('boot');
          return !!(document.querySelector('.window') && boot && boot.classList.contains('hidden'));
        })();
        """, timeout: 15)
        XCTAssertTrue(ready as? Bool == true, "desktop shell did not finish booting")
    }

    private func waitFor(_ script: String, timeout: TimeInterval) async throws -> Any? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = try? await webView.evaluateJavaScript(script), (value as? Bool) == true {
                return value
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        return nil
    }

    private func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }
}
