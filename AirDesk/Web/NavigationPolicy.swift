import Foundation
import WebKit

@MainActor
final class NavigationPolicy: NSObject, WKNavigationDelegate, WKUIDelegate {
    var policy: OriginPolicy
    var onFailure: ((Error) -> Void)?
    var onProcessTermination: (() -> Void)?
    var onBlockedNavigation: ((URL) -> Void)?

    init(policy: OriginPolicy) {
        self.policy = policy
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        if policy.isAllowedNavigation(url) {
            decisionHandler(.allow)
            return
        }

        if navigationAction.navigationType == .linkActivated {
            onBlockedNavigation?(url)
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, !policy.isAllowedNavigation(url) {
            onBlockedNavigation?(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFailure?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        onFailure?(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onProcessTermination?()
    }
}
