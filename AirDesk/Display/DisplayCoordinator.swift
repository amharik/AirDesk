import Foundation
import OSLog
import UIKit

@MainActor
final class DisplayCoordinator: ObservableObject {
    @Published private(set) var isExternalDisplayConnected = false
    @Published private(set) var externalDisplayName = ""
    @Published private(set) var externalDisplaySize: CGSize = .zero

    var onExternalDisplayConnected: ((UIView) -> Void)?
    var onExternalDisplayDisconnected: (() -> Void)?

    private let logger = Logger(subsystem: "com.airdesk.ios", category: "Display")
    private var window: UIWindow?
    private weak var activeScene: UIWindowScene?
    private var controller: ExternalDisplayViewController?
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

    func register(scene: UIWindowScene) {
        guard scene.session.role == .windowExternalDisplay || scene.session.role == .windowExternalDisplayNonInteractive else {
            return
        }
        guard activeScene !== scene else { return }

        if let existing = activeScene, existing !== scene {
            unregister(scene: existing)
        }

        let controller = ExternalDisplayViewController()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.backgroundColor = .black
        window.isHidden = false
        self.controller = controller
        self.window = window
        self.activeScene = scene
        externalDisplaySize = scene.screen.bounds.size
        isExternalDisplayConnected = true
        externalDisplayName = "External display"
        logger.info("External display connected: \(String(describing: scene.screen.bounds.size), privacy: .public)")
        onExternalDisplayConnected?(controller.contentView)
    }

    func unregister(scene: UIWindowScene) {
        guard activeScene === scene else { return }
        controller?.setActive(false)
        window?.isHidden = true
        window = nil
        controller = nil
        activeScene = nil
        isExternalDisplayConnected = false
        externalDisplayName = ""
        externalDisplaySize = .zero
        logger.info("External display disconnected")
        onExternalDisplayDisconnected?()
    }

    func registerDirectlyIfExternal(_ scene: UIWindowScene) {
        register(scene: scene)
    }

    func present(surface: DesktopSurface) {
        guard let container = contentContainer else { return }
        surface.attachExternal(to: container)
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

        detailLabel.text = "Start a session on your iPhone to bring the Wanix desktop here."
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
