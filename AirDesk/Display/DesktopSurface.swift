import Foundation
import OSLog
import SwiftUI
import UIKit
import WebKit

enum DesktopSurfaceError: LocalizedError, Equatable {
    case missingResource(String)
    case navigationFailed(String)
    case readyTimeout
    case processTerminated
    case remoteRuntimeNotConfigured

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): return "The desktop resource \(name) is missing from the app bundle."
        case .navigationFailed(let reason): return "The desktop failed to load: \(reason)"
        case .readyTimeout: return "The desktop runtime did not report readiness."
        case .processTerminated: return "The desktop web process terminated unexpectedly."
        case .remoteRuntimeNotConfigured: return "The remote runtime URL is not configured."
        }
    }
}

@MainActor
final class DesktopSurface {
    enum Destination: Equatable {
        case detached
        case home
        case external
        case preview
    }

    private let logger = Logger(subsystem: "com.airdesk.ios", category: "DesktopSurface")
    let webView: WKWebView
    private let bridge: RuntimeBridge
    private let navigationPolicy: NavigationPolicy

    private(set) var isReady = false
    private(set) var destination: Destination = .detached
    private(set) var lastViewport: CGSize = .zero
    private var lastLoad: LoadRequest?
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    weak var homeContainer: UIView?
    var onReady: (() -> Void)?
    var onMessage: ((BridgeMessage) -> Void)?
    var onStateChange: ((String) -> Void)?
    var onFailure: ((Error) -> Void)?

    private struct LoadRequest {
        let choice: RuntimeChoice
        let sessionId: String
        let generation: Int
        let appearance: String
    }

    init() {
        bridge = RuntimeBridge()
        navigationPolicy = NavigationPolicy(policy: OriginPolicy())

        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = false

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = navigationPolicy
        webView.uiDelegate = navigationPolicy

        contentController.add(bridge, name: RuntimeBridge.handlerName)
        bridge.attach(webView)
        navigationPolicy.onFailure = { [weak self] error in
            self?.handleLoadFailure(error)
        }
        navigationPolicy.onProcessTermination = { [weak self] in
            self?.handleProcessTermination()
        }
        navigationPolicy.onBlockedNavigation = { [weak self] url in
            self?.logger.info("Blocked navigation to \(url.host ?? "unknown", privacy: .public)")
        }
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RuntimeBridge.handlerName)
    }

    func load(choice: RuntimeChoice, sessionId: String, generation: Int = 0, appearance: String = "dark") throws {
        let request = LoadRequest(choice: choice, sessionId: sessionId, generation: generation, appearance: appearance)
        lastLoad = request
        isReady = false
        bridge.sessionId = sessionId
        bridge.onMessage = { [weak self] message in
            self?.handle(message)
        }
        bridge.onDecodeFailure = { [weak self] error in
            self?.logger.debug("Bridge decode failure: \(String(describing: error), privacy: .public)")
        }
        bridge.onTransportFailure = { [weak self] reason in
            self?.logger.debug("Bridge transport failure: \(reason, privacy: .public)")
        }

        installBootstrap(request)
        webView.stopLoading()

        switch choice {
        case .wanixDesktop:
            let page = usesWinBoxPreview ? "winbox-preview" : "index"
            let url = try localAssetURL(name: page, extension: "html", request: request)
            configurePolicy(for: url, origins: [Self.origin(of: url)].compactMap { $0 })
            webView.load(URLRequest(url: url))
        case .wanixKernel:
            let url = try localAssetURL(name: "wanix-live", extension: "html", request: request)
            configurePolicy(for: url, origins: [Self.origin(of: url)].compactMap { $0 })
            webView.load(URLRequest(url: url))
        case .puter:
            let raw = Bundle.main.object(forInfoDictionaryKey: "AirDeskRuntimeBaseURL") as? String ?? ""
            guard let url = URL(string: raw), url.scheme == "https" else {
                throw DesktopSurfaceError.remoteRuntimeNotConfigured
            }
            configurePolicy(for: url, origins: [url.host ?? ""])
            webView.load(URLRequest(url: url))
        }
    }

    func reloadForRecovery() {
        guard let lastLoad else { return }
        isReady = false
        onStateChange?("recovering")
        do {
            try load(choice: lastLoad.choice, sessionId: lastLoad.sessionId, generation: lastLoad.generation, appearance: lastLoad.appearance)
        } catch {
            failReady(error)
        }
    }

    func waitUntilReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }

    func send(_ event: InputEvent) {
        bridge.send(event)
    }

    func sendControl(type: String, payload: [String: Any] = [:]) {
        bridge.sendControl(type: type, payload: payload)
    }

    func attach(to container: UIView, destination: Destination) {
        if webView.superview === container, self.destination == destination {
            return
        }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.destination = destination
    }

    func setHomeContainer(_ container: UIView?) {
        homeContainer = container
        attachHomeIfNeeded()
    }

    func clearHomeContainer(_ container: UIView) {
        if homeContainer === container {
            homeContainer = nil
        }
    }

    func attachHomeIfNeeded() {
        guard destination != .preview, destination != .external else { return }
        guard let homeContainer else { return }
        attach(to: homeContainer, destination: .home)
    }

    func attachExternal(to container: UIView) {
        attach(to: container, destination: .external)
    }

    func attachPreview(to container: UIView) {
        attach(to: container, destination: .preview)
    }

    func returnHome() {
        destination = .detached
        attachHomeIfNeeded()
    }

    var isOnExternalDisplay: Bool { destination == .external }

    private func installBootstrap(_ request: LoadRequest) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let session = Self.jsString(request.sessionId)
        let runtime = Self.jsString(request.choice.rawValue)
        let appearance = Self.jsString(request.appearance)
        let device = Self.jsString(DeviceContext.name)
        let source = """
        window.AIRDESK_SESSION_ID = \(session);
        window.AIRDESK_RUNTIME = \(runtime);
        window.AIRDESK_GENERATION = \(request.generation);
        window.AIRDESK_APPEARANCE = \(appearance);
        window.AIRDESK_DEVICE_NAME = \(device);
        window.AIRDESK_NATIVE = true;
        """
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
    }

    private func configurePolicy(for url: URL, origins: [String]) {
        let directory = url.isFileURL ? url.deletingLastPathComponent() : nil
        navigationPolicy.policy = OriginPolicy(
            allowedFileDirectory: directory,
            allowedOrigins: Set(origins.filter { !$0.isEmpty })
        )
    }

    private func localAssetURL(name: String, extension ext: String, request: LoadRequest) throws -> URL {
        let directory = try bundledDirectory()
        let baseURL = try LocalAssetServer.shared.start(rootDirectory: directory)
        var components = URLComponents(
            url: baseURL.appendingPathComponent("\(name).\(ext)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "session", value: request.sessionId),
            URLQueryItem(name: "runtime", value: request.choice.rawValue),
            URLQueryItem(name: "generation", value: String(request.generation)),
            URLQueryItem(name: "appearance", value: request.appearance),
            URLQueryItem(name: "device", value: DeviceContext.name)
        ]
        guard let url = components?.url else {
            throw DesktopSurfaceError.missingResource("\(name).\(ext)")
        }
        return url
    }

    private func bundledDirectory() throws -> URL {
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "DesktopShell") {
            return url.deletingLastPathComponent()
        }
        if let url = Bundle.main.url(forResource: "DesktopShell", withExtension: nil) {
            return url
        }
        throw DesktopSurfaceError.missingResource("DesktopShell")
    }

    private static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return nil
        }
        return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    private func handle(_ message: BridgeMessage) {
        switch message.type {
        case "ready":
            if let width = message.width, let height = message.height, width > 0, height > 0 {
                lastViewport = CGSize(width: width, height: height)
            }
            isReady = true
            let waiters = readyWaiters
            readyWaiters.removeAll()
            waiters.forEach { $0.resume() }
            onStateChange?("ready")
            onReady?()
        case "error":
            let error = DesktopSurfaceError.navigationFailed(message.message ?? "Runtime error")
            if !isReady { failReady(error) }
            onFailure?(error)
        case "viewport":
            if let width = message.width, let height = message.height, width > 0, height > 0 {
                lastViewport = CGSize(width: width, height: height)
            }
        default:
            break
        }
        onMessage?(message)
    }

    private func handleLoadFailure(_ error: Error) {
        logger.error("Desktop navigation failed: \(String(describing: error), privacy: .public)")
        if !isReady {
            failReady(DesktopSurfaceError.navigationFailed(error.localizedDescription))
        }
        onFailure?(error)
    }

    private func handleProcessTermination() {
        logger.error("Desktop web process terminated")
        isReady = false
        onStateChange?("recovering")
        onFailure?(DesktopSurfaceError.processTerminated)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.reloadForRecovery()
        }
    }

    private func failReady(_ error: Error) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
        onStateChange?("failed")
    }

    private var usesWinBoxPreview: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-AirDeskWinBoxPreview")
#else
        false
#endif
    }

    private static func jsString(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

struct DesktopSurfaceAnchor: UIViewRepresentable {
    let surface: DesktopSurface

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false
        surface.setHomeContainer(container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        surface.setHomeContainer(uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // The surface falls back to the next available host.
    }
}

struct DesktopPreviewSurface: UIViewRepresentable {
    let surface: DesktopSurface

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        surface.attachPreview(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        surface.attachPreview(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Handled by the preview sheet dismissal path so external displays keep ownership.
    }
}
