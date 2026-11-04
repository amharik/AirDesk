import WebKit
import XCTest

@MainActor
final class WebRTCLoopbackProbeTests: XCTestCase {
    func testLoopbackDataChannelProbe() async throws {
        let defaults = UserDefaults(suiteName: "com.airdesk.webrtcprobe")
        guard defaults?.bool(forKey: "enabled") == true else {
            throw XCTSkip("Run scripts/research/run-webrtc-ios.sh to enable the WebRTC probe.")
        }
        let payloadBytes = defaults?.integer(forKey: "payloadBytes") ?? 1024
        let sampleCount = defaults?.integer(forKey: "samples") ?? 30

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = ProbeNavigationWaiter()
        webView.navigationDelegate = waiter
        try await waiter.loadHTML(Self.html, in: webView)

        let value = try await webView.callAsyncJavaScript(
            "return await window.probe(payloadBytes, sampleCount);",
            arguments: ["payloadBytes": payloadBytes, "sampleCount": sampleCount],
            in: nil,
            contentWorld: .page
        )
        let result = try XCTUnwrap(value as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        print("AIRDESK_WEBRTC_RESULT \(text)")

        let failures = try XCTUnwrap(result["failures"] as? [String])
        let rtts = try XCTUnwrap(result["rtts"] as? [Double])
        XCTAssertTrue(failures.isEmpty, "Failures: \(failures)")
        XCTAssertEqual(rtts.count, sampleCount)
        XCTAssertNotNil(result["reconnectMs"] as? Double)
    }

    private static let html = """
    <!doctype html>
    <html><body><script>
    window.probe = async function (payloadBytes, sampleCount) {
      const result = {
        peerConnection: typeof RTCPeerConnection,
        dataChannel: typeof RTCDataChannel,
        samples: sampleCount,
        payloadBytes: payloadBytes,
        iceGatheringState: null,
        localCandidateTypes: [],
        remoteCandidateTypes: [],
        openMs: null,
        rtts: [],
        reconnectMs: null,
        reconnectEchoMs: null,
        failures: []
      };
      if (typeof RTCPeerConnection === 'undefined') {
        return result;
      }

      const waitForGathering = function (connection) {
        if (connection.iceGatheringState === 'complete') {
          return Promise.resolve();
        }
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('ICE gathering timeout')), 8000);
          connection.onicegatheringstatechange = function () {
            if (connection.iceGatheringState === 'complete') {
              clearTimeout(timer);
              resolve();
            }
          };
        });
      };

      const connectPair = async function () {
        const a = new RTCPeerConnection({ iceServers: [] });
        const b = new RTCPeerConnection({ iceServers: [] });
        const channel = a.createDataChannel('probe', { ordered: true });
        channel.binaryType = 'arraybuffer';
        let localOpened = false;
        let remoteOpened = false;
        const opened = new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('data channel open timeout')), 8000);
          const check = function () {
            if (localOpened && remoteOpened) {
              clearTimeout(timer);
              resolve();
            }
          };
          channel.onopen = function () { localOpened = true; check(); };
          channel.onerror = function () { reject(new Error('local channel error')); };
          b.ondatachannel = function (event) {
            const remote = event.channel;
            remote.binaryType = 'arraybuffer';
            remote.onopen = function () { remoteOpened = true; check(); };
            remote.onerror = function () { reject(new Error('remote channel error')); };
            remote.onmessage = function (message) {
              if (remote.readyState === 'open') {
                remote.send(message.data);
              }
            };
          };
        });

        a.onicecandidate = function (event) {
          if (event.candidate) {
            result.localCandidateTypes.push(event.candidate.type || 'unknown');
          }
        };
        b.onicecandidate = function (event) {
          if (event.candidate) {
            result.remoteCandidateTypes.push(event.candidate.type || 'unknown');
          }
        };

        const started = performance.now();
        await a.setLocalDescription(await a.createOffer());
        await waitForGathering(a);
        result.iceGatheringState = a.iceGatheringState;
        await b.setRemoteDescription(a.localDescription);
        await b.setLocalDescription(await b.createAnswer());
        await waitForGathering(b);
        await a.setRemoteDescription(b.localDescription);
        await opened;
        return { a: a, b: b, channel: channel, openMs: performance.now() - started };
      };

      const roundTrip = function (channel, payload, started) {
        return new Promise((resolve, reject) => {
          const timer = setTimeout(() => reject(new Error('echo timeout')), 5000);
          channel.onmessage = function (message) {
            clearTimeout(timer);
            const bytes = new Uint8Array(message.data);
            if (bytes.length !== payload.length) {
              reject(new Error('echo length mismatch'));
              return;
            }
            resolve(performance.now() - started);
          };
          channel.send(payload);
        });
      };

      let pair = null;
      try {
        pair = await connectPair();
        result.openMs = pair.openMs;
        const payload = new Uint8Array(payloadBytes);
        payload.set([0x41, 0x44, 0x46, 0x50], 0);
        for (let index = 0; index < sampleCount; index += 1) {
          new DataView(payload.buffer).setUint32(4, index, true);
          result.rtts.push(await roundTrip(pair.channel, payload, performance.now()));
        }
      } catch (error) {
        result.failures.push(String(error));
      }

      if (pair !== null) {
        try {
          const reconnectStarted = performance.now();
          pair.a.close();
          pair.b.close();
          await new Promise((resolve) => setTimeout(resolve, 100));
          const replacement = await connectPair();
          result.reconnectMs = performance.now() - reconnectStarted;
          const payload = new Uint8Array(payloadBytes);
          payload.set([0x41, 0x44, 0x46, 0x50], 0);
          result.reconnectEchoMs = await roundTrip(replacement.channel, payload, performance.now());
          replacement.a.close();
          replacement.b.close();
        } catch (error) {
          result.failures.push('reconnect: ' + String(error));
        }
      }

      return result;
    };
    </script></body></html>
    """
}

@MainActor
private final class ProbeNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func loadHTML(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: URL(string: "https://localhost/"))
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
