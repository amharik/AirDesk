import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let environment = AppEnvironment.shared
        environment.bootstrap()

        let root = RootView()
            .environmentObject(environment)
            .environmentObject(environment.session)
            .environmentObject(environment.settings)
            .environmentObject(environment.cast)
            .environmentObject(environment.diagnostics)
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = .black
        hosting.overrideUserInterfaceStyle = .dark

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hosting
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AppEnvironment.shared.session.sceneBecameActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        AppEnvironment.shared.session.sceneWillResignActive()
    }
}

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppEnvironment.shared.display.registerDirectlyIfExternal(windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppEnvironment.shared.display.unregister(scene: windowScene)
    }
}
