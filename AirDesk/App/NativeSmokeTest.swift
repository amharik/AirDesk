#if DEBUG
import Foundation
import OSLog
import WebKit

@MainActor
enum NativeSmokeTest {
    private static let logger = Logger(subsystem: "com.airdesk.ios", category: "NativeSmokeTest")

    static func runIfRequested(session: SessionCoordinator) {
        guard ProcessInfo.processInfo.arguments.contains("-AirDeskSmokeTest") else { return }
        Task { await run(session: session) }
    }

    private static func run(session: SessionCoordinator) async {
        var output: [String: Any]
        do {
            if session.phase == .idle {
                session.beginConnection(to: .previewDevice)
            }
            guard await waitUntil(timeout: 90, condition: { session.phase == .ready && session.desktopSurface.isReady }) else {
                output = [
                    "ok": false,
                    "error": "Timed out waiting for the desktop session",
                    "phase": session.phase.rawValue,
                    "stage": session.stage.rawValue,
                    "runtimeState": session.runtimeState.rawValue,
                    "surfaceReady": session.desktopSurface.isReady,
                    "lastError": session.lastError ?? "",
                    "diagnostics": "skipped"
                ]
                write(output)
                return
            }

            let environment = try? await evaluate(environmentScript, in: session.desktopSurface.webView)
            let started = try await evaluate(startScript, in: session.desktopSurface.webView)
            guard started as? String == "started" else {
                output = ["ok": false, "error": "Smoke script failed to start", "value": String(describing: started)]
                write(output)
                return
            }

            var json: String?
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                let polled = try await evaluate(pollScript, in: session.desktopSurface.webView)
                if let value = polled as? String {
                    json = value
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            guard let json,
                  let data = json.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                output = [
                    "ok": false,
                    "error": json == nil ? "Smoke script timed out" : "Smoke script returned invalid result",
                    "value": json ?? "nil",
                    "diagnostics": "skipped"
                ]
                write(output)
                return
            }

            let prompt = result["prompt"] as? Bool ?? false
            let failures = result["failures"] as? [String] ?? []
            output = ["ok": prompt && failures.isEmpty, "result": result, "environment": environment ?? "unavailable"]
        } catch {
            output = ["ok": false, "error": String(describing: error)]
        }
        write(output)
    }

    private static func waitUntil(timeout: TimeInterval, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return condition()
    }

    private static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func write(_ result: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("airdesk-native-smoke.json")
            try data.write(to: url, options: .atomic)
            logger.info("Native smoke result written to \(url.path, privacy: .public)")
        } catch {
            logger.error("Native smoke result write failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static let environmentScript = #"""
      return JSON.stringify({
        coi: crossOriginIsolated,
        persistence: window.AirDeskKernel ? window.AirDeskKernel.persistence() : 'missing',
        hasStorage: !!(navigator.storage && navigator.storage.getDirectory),
        opfsBind: !!document.querySelector('#opfs-bind'),
        opfsSrc: document.querySelector('#opfs-bind') ? document.querySelector('#opfs-bind').getAttribute('src') : null
      });
    """#

    private static let startScript = #"""
      window.__airdeskSmokeResult = null;
      (async () => {
      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
      let opfsProbe = 'skipped: createWritable unavailable';
      const supportsOPFSWrites = typeof FileSystemFileHandle !== 'undefined' &&
        FileSystemFileHandle.prototype &&
        typeof FileSystemFileHandle.prototype.createWritable === 'function';
      if (supportsOPFSWrites) {
        try {
          const storageRoot = await navigator.storage.getDirectory();
          const probeHandle = await storageRoot.getFileHandle('airdesk-smoke-probe.txt', { create: true });
          const probeWritable = await probeHandle.createWritable();
          await probeWritable.write('probe');
          await probeWritable.close();
          opfsProbe = 'ok: ' + await (await probeHandle.getFile()).text();
        } catch (error) {
          opfsProbe = 'error: ' + error;
        }
      }
      const deadline = Date.now() + 60000;
      while (Date.now() < deadline) {
        if (window.AirDeskKernel && window.AirDeskKernel.ready) {
          await window.AirDeskKernel.ready;
          break;
        }
        await sleep(100);
      }
      document.querySelector('.dock-item[data-app="terminal"]').click();
      const termDeadline = Date.now() + 30000;
      let term = null;
      while (Date.now() < termDeadline) {
        term = document.querySelector('wanix-term');
        if (term && term._term) break;
        await sleep(100);
      }
      if (!term || !term._term) {
        window.__airdeskSmokeResult = JSON.stringify({ prompt: false, error: 'terminal missing', failures: ['terminal'] });
        return;
      }
      const text = () => {
        const buffer = term._term.buffer.active;
        let out = '';
        for (let i = 0; i < buffer.length; i++) {
          const line = buffer.getLine(i);
          if (line) out += line.translateToString(true) + '\n';
        }
        return out;
      };
      const promptDeadline = Date.now() + 20000;
      let prompt = false;
      while (Date.now() < promptDeadline) {
        if (text().includes('rc%')) { prompt = true; break; }
        await sleep(100);
      }
      const commands = [
        'touch native.txt',
        'echo hello > native.txt',
        'echo more >> native.txt',
        'cat native.txt',
        'cp native.txt native-copy.txt',
        'cat native-copy.txt',
        'mkdir -p nativesub',
        'cp native.txt nativesub/copied.txt',
        'cat nativesub/copied.txt',
        'touch opfs/native.txt',
        'echo opfs > opfs/native.txt',
        'echo more >> opfs/native.txt',
        'cp opfs/native.txt opfs/native-copy.txt',
        'cat opfs/native-copy.txt'
      ];
      for (const command of commands) {
        term._term.input(command + '\n', true);
        await sleep(1000);
      }
      await sleep(500);
      const root = window.AirDeskKernel.root();
      const paths = ['native.txt', 'native-copy.txt', 'nativesub/copied.txt', 'opfs/native.txt', 'opfs/native-copy.txt'];
      const files = {};
      for (const path of paths) {
        try { files[path] = await root.readText(path); }
        catch (error) { files[path] = 'ERROR: ' + error; }
      }
      const expected = {
        'native.txt': 'hello\nmore\n',
        'native-copy.txt': 'hello\nmore\n',
        'nativesub/copied.txt': 'hello\nmore\n',
        'opfs/native.txt': 'opfs\nmore\n',
        'opfs/native-copy.txt': 'opfs\nmore\n'
      };
      const failures = paths.filter((path) => files[path] !== expected[path]);
      window.__airdeskSmokeResult = JSON.stringify({ prompt, files, expected, failures, opfsProbe, text: text() });
      })().catch((error) => {
        window.__airdeskSmokeResult = JSON.stringify({ prompt: false, error: 'script failed: ' + error, failures: ['exception'] });
      });
      return 'started';
    """#

    private static let pollScript = #"""
      return window.__airdeskSmokeResult;
    """#
}
#endif
