import Foundation
import OSLog
import WebKit

@MainActor
final class RuntimeBridge: NSObject, WKScriptMessageHandler {
    private let logger = Logger(subsystem: "com.airdesk.ios", category: "RuntimeBridge")
    private weak var webView: WKWebView?
    var sessionId: String = ""
    var onMessage: ((BridgeMessage) -> Void)?
    var onDecodeFailure: ((Error) -> Void)?
    var onTransportFailure: ((String) -> Void)?

    static let handlerName = "airdesk"

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func receive(_ body: Any) {
        do {
            let data: Data
            if let dictionary = body as? [String: Any] {
                data = try JSONSerialization.data(withJSONObject: dictionary)
            } else if let string = body as? String {
                data = Data(string.utf8)
            } else {
                throw BridgeError.malformedPayload
            }
            let decoded = try JSONDecoder().decode(BridgeMessage.self, from: data)
            let message = try decoded.validated()
            if let messageSession = message.sessionId, !sessionId.isEmpty, messageSession != sessionId {
                throw BridgeError.invalidSession
            }
            onMessage?(message)
        } catch {
            logger.error("Rejected bridge message: \(String(describing: error), privacy: .public)")
            onDecodeFailure?(error)
        }
    }

    func send(_ event: InputEvent) {
        guard let object = try? event.jsonObject() else {
            onTransportFailure?("encode")
            return
        }
        let script = """
        if (window.AirDeskBridge && typeof window.AirDeskBridge.receive === 'function') {
            window.AirDeskBridge.receive(message);
            return true;
        }
        return false;
        """
        webView?.callAsyncJavaScript(
            script,
            arguments: ["message": object],
            in: nil,
            in: .page
        ) { [weak self] result in
            if case .failure = result {
                self?.onTransportFailure?("bridge")
            }
        }
    }

    func sendControl(type: String, payload: [String: Any] = [:]) {
        var message = payload
        message["version"] = 1
        message["type"] = type
        if !sessionId.isEmpty { message["sessionId"] = sessionId }
        let script = """
        if (window.AirDeskBridge && typeof window.AirDeskBridge.receiveControl === 'function') {
            window.AirDeskBridge.receiveControl(message);
            return true;
        }
        return false;
        """
        webView?.callAsyncJavaScript(
            script,
            arguments: ["message": message],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName else { return }
        receive(message.body)
    }
}
