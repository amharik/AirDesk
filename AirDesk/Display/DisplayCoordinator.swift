import Foundation
import OSLog
import UIKit

@MainActor
final class DisplayCoordinator: ObservableObject {
    @Published private(set) var isExternalDisplayConnected = false
    @Published private(set) var isMirroring = false
    @Published private(set) var presentationMode: DisplayPresentationMode = .extended
    @Published private(set) var externalDisplayName = ""
    @Published private(set) var externalDisplaySize: CGSize = .zero

    var onExternalDisplayConnected: ((UIView) -> Void)?
    var onExternalDisplayDisconnected: (() -> Void)?
    var onMirroringChanged: ((Bool) -> Void)?

    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Display")
    private var window: UIWindow?
    private weak var activeScene: UIWindowScene?
    private var controller: ExternalDisplayViewController?
    private var fallbackMirroredScreen: UIScreen?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let scene = note.object as? UIWindowScene else { return }
            Task { @MainActor in self?.register(scene: scene) }
        })
        observers.append(center.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let scene = note.object as? UIWindowScene else { return }
            Task { @MainActor in self?.unregister(scene: scene) }
        })
        observers.append(center.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshScreenFallback() }
        })
        observers.append(center.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshScreenFallback() }
        })
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshScreenFallback()
                if let scene = self?.activeScene {
                    self?.updateWindowFrame(for: scene)
                }
            }
        })
        refreshScreenFallback()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    var hasExternalDisplay: Bool {
        isExternalDisplayConnected && window != nil
    }

    var contentContainer: UIView? {
        guard isExternalDisplayConnected else { return nil }
        return controller?.contentView
    }

    func setPresentationMode(_ mode: DisplayPresentationMode) {
        guard presentationMode != mode else { return }
        presentationMode = mode
        guard isExternalDisplayConnected else { return }

        if mode == .mirrored {
            teardownWindow()
            setMirroring(true)
            logger.info("External display switched to mirroring")
        } else if let scene = activeScene {
            setMirroring(false)
            makeWindow(for: scene)
            logger.info("External display switched to extended desktop")
            if let contentView = controller?.contentView {
                onExternalDisplayConnected?(contentView)
            }
        } else if fallbackMirroredScreen != nil {
            setMirroring(true)
            logger.info("AirPlay mirroring cannot provide an extended desktop")
        } else {
            setMirroring(false)
        }
    }

    func register(scene: UIWindowScene) {
        guard scene.session.role == .windowExternalDisplayNonInteractive else {
            return
        }
        guard activeScene !== scene else { return }

        if let existing = activeScene, existing !== scene {
            unregister(scene: existing)
        }

        fallbackMirroredScreen = nil
        activeScene = scene
        externalDisplaySize = scene.screen.bounds.size
        externalDisplayName = "External display"
        isExternalDisplayConnected = true

        if presentationMode == .mirrored {
            setMirroring(true)
            logger.info("External display connected in mirroring mode")
        } else {
            setMirroring(false)
            makeWindow(for: scene)
            logger.info("External display connected: \(String(describing: scene.screen.bounds.size), privacy: .public)")
            DispatchQueue.main.async { [weak self] in self?.updateWindowFrame(for: scene) }
            if let contentView = controller?.contentView {
                onExternalDisplayConnected?(contentView)
            }
        }
    }

    func unregister(scene: UIWindowScene) {
        guard activeScene === scene else { return }
        let wasMirroring = isMirroring
        teardownWindow()
        activeScene = nil
        fallbackMirroredScreen = nil
        isExternalDisplayConnected = false
        isMirroring = false
        externalDisplayName = ""
        externalDisplaySize = .zero
        logger.info("External display disconnected")
        refreshScreenFallback()
        if !isMirroring {
            if wasMirroring {
                onMirroringChanged?(false)
            } else {
                onExternalDisplayDisconnected?()
            }
        }
    }

    private func refreshScreenFallback() {
        guard activeScene == nil else { return }
        let mirroredScreen = UIScreen.screens.first { $0.mirrored != nil }

        guard let mirroredScreen else {
            guard fallbackMirroredScreen != nil else { return }
            let wasMirroring = isMirroring
            fallbackMirroredScreen = nil
            isExternalDisplayConnected = false
            isMirroring = false
            externalDisplayName = ""
            externalDisplaySize = .zero
            logger.info("AirPlay mirroring disconnected")
            if wasMirroring {
                onMirroringChanged?(false)
            } else {
                onExternalDisplayDisconnected?()
            }
            return
        }

        fallbackMirroredScreen = mirroredScreen
        isExternalDisplayConnected = true
        externalDisplaySize = mirroredScreen.bounds.size
        externalDisplayName = "AirPlay mirroring"
        if !isMirroring {
            setMirroring(true)
            logger.info("AirPlay mirroring detected without an external display scene")
        }
    }

    private func setMirroring(_ value: Bool) {
        guard isMirroring != value else { return }
        isMirroring = value
        onMirroringChanged?(value)
    }

    func registerDirectlyIfExternal(_ scene: UIWindowScene) {
        register(scene: scene)
    }

    func sceneDidUpdateCoordinateSpace(_ scene: UIWindowScene) {
        updateWindowFrame(for: scene)
    }

    private func makeWindow(for scene: UIWindowScene) {
        let controller = ExternalDisplayViewController()
        scene.screen.overscanCompensation = .none
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = controller
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        self.controller = controller
        self.window = window
        updateWindowFrame(for: scene)
    }

    private func updateWindowFrame(for scene: UIWindowScene) {
        guard scene === activeScene, let window else { return }
        let bounds = scene.screen.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        if externalDisplaySize != bounds.size {
            externalDisplaySize = bounds.size
            logger.info("External display resized: \(String(describing: bounds.size), privacy: .public)")
        }
        if window.frame != bounds {
            window.frame = bounds
        }
        window.rootViewController?.view.frame = bounds
        controller?.view.setNeedsLayout()
        controller?.view.layoutIfNeeded()
    }

    private func teardownWindow() {
        controller?.setActive(false)
        window?.isHidden = true
        window?.windowScene = nil
        window = nil
        controller = nil
    }

    func present(surface: DesktopSurface) {
        if let scene = activeScene {
            updateWindowFrame(for: scene)
        }
        guard let container = contentContainer else { return }
        controller?.view.layoutIfNeeded()
        surface.attachExternal(to: container)
        controller?.view.layoutIfNeeded()
        controller?.setActive(true)
    }

    func detach(surface: DesktopSurface) {
        surface.returnHome()
        controller?.setActive(false)
    }
}

final class ExternalDisplayViewController: UIViewController {
    let contentView = UIView()
    private let placeholder = UIStackView()
    private let logoLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.016, green: 0.024, blue: 0.039, alpha: 1)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .clear
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        logoLabel.text = "AirDesk"
        logoLabel.font = .systemFont(ofSize: 64, weight: .bold)
        logoLabel.textColor = .white
        logoLabel.textAlignment = .center

        titleLabel.text = "External display connected"
        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        titleLabel.textAlignment = .center

        detailLabel.text = "Start a session on your \(DeviceContext.name) to bring the Wanix desktop here."
        detailLabel.font = .systemFont(ofSize: 17, weight: .regular)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        placeholder.axis = .vertical
        placeholder.alignment = .center
        placeholder.spacing = 14
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.addArrangedSubview(logoLabel)
        placeholder.addArrangedSubview(titleLabel)
        placeholder.addArrangedSubview(detailLabel)
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 80),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -80),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420)
        ])
    }

    func setActive(_ active: Bool) {
        placeholder.isHidden = active
    }
}
