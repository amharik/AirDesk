import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppEnvironment.shared.bootstrap()
        CastSessionCoordinator.configureSDKIfNeeded()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let configuration = UISceneConfiguration(
                name: "AirDesk External Display",
                sessionRole: connectingSceneSession.role
            )
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
            configuration.sceneClass = UIWindowScene.self
            return configuration
        }

        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        configuration.sceneClass = UIWindowScene.self
        return configuration
    }
}
