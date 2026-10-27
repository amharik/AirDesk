import WebKit
import XCTest
@testable import AirDesk

@MainActor
final class LocalAssetServerTests: XCTestCase {
    func testLoopbackServerEnablesCrossOriginIsolationAndOPFS() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirDeskLocalAssetServer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let html = """
        <!doctype html>
        <html><body><script>
        window.probe = async function () {
          const coi = window.crossOriginIsolated === true;
          const sab = typeof SharedArrayBuffer !== 'undefined';
          let opfs = false;
          let syncAccess = false;
          let writable = false;
          let workerResult = null;
          let error = null;
          try {
            const root = await navigator.storage.getDirectory();
            const handle = await root.getFileHandle('.airdesk-probe', { create: true });
            syncAccess = typeof handle.createSyncAccessHandle === 'function';
            writable = typeof handle.createWritable === 'function';
            const file = await handle.getFile();
            opfs = file.size === 0;
            await root.removeEntry('.airdesk-probe');
          } catch (caught) {
            error = String(caught);
          }
          try {
            const source = `
              self.onmessage = async function () {
                try {
                  const root = await navigator.storage.getDirectory();
                  const handle = await root.getFileHandle('.airdesk-worker-probe', { create: true });
                  const access = await handle.createSyncAccessHandle();
                  access.write(new Uint8Array([1, 2, 3]), { at: 0 });
                  access.flush();
                  const size = access.getSize();
                  const bytes = new Uint8Array(3);
                  access.read(bytes, { at: 0 });
                  access.close();
                  await root.removeEntry('.airdesk-worker-probe');
                  self.postMessage({ ok: bytes[0] === 1 && bytes[1] === 2 && bytes[2] === 3, size: size });
                } catch (caught) {
                  self.postMessage({ ok: false, error: String(caught) });
                }
              };
            `;
            const worker = new Worker(URL.createObjectURL(new Blob([source], { type: 'text/javascript' })));
            workerResult = await new Promise(function (resolve) {
              worker.onmessage = function (event) { resolve(event.data); };
              worker.postMessage('probe');
            });
            worker.terminate();
          } catch (caught) {
            workerResult = { ok: false, error: String(caught) };
          }
          return { coi: coi, sab: sab, opfs: opfs, syncAccess: syncAccess, writable: writable, worker: workerResult, error: error };
        };
        </script></body></html>
        """
        try Data(html.utf8).write(to: directory.appendingPathComponent("index.html"))

        let server = LocalAssetServer()
        defer { server.stop() }
        let baseURL = try server.start(rootDirectory: directory)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        try await waiter.load(baseURL, in: webView)

        let value = try await webView.callAsyncJavaScript(
            "return await window.probe();",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let result = try XCTUnwrap(value as? [String: Any])
        XCTAssertEqual(result["coi"] as? Bool, true)
        XCTAssertEqual(result["sab"] as? Bool, true)
        XCTAssertEqual(result["opfs"] as? Bool, true, "OPFS error: \(result["error"] ?? "none")")
        let worker = try XCTUnwrap(result["worker"] as? [String: Any])
        XCTAssertEqual(worker["ok"] as? Bool, true, "Worker OPFS error: \(worker["error"] ?? "none")")
        XCTAssertEqual(worker["size"] as? Int, 3)
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
