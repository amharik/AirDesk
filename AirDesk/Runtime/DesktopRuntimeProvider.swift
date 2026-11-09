import Foundation

@MainActor
protocol DesktopRuntimeProvider: AnyObject {
    var descriptor: RuntimeProviderDescriptor { get }
    var choices: Set<RuntimeChoice> { get }

    func makeRuntime(choice: RuntimeChoice, appearance: String) throws -> any DesktopRuntime
    func prepare(_ runtime: any DesktopRuntime, in host: RuntimeHost) async throws
    func loadWorkspace(_ workspace: Workspace, into runtime: any DesktopRuntime) async throws
    func suspend(_ runtime: any DesktopRuntime) async
    func resume(_ runtime: any DesktopRuntime) async throws
    func shutdown(_ runtime: any DesktopRuntime) async
}

extension DesktopRuntimeProvider {
    func prepare(_ runtime: any DesktopRuntime, in host: RuntimeHost) async throws {
        try await runtime.prepare(in: host)
    }

    func loadWorkspace(_ workspace: Workspace, into runtime: any DesktopRuntime) async throws {
        try await runtime.loadWorkspace(workspace)
    }

    func suspend(_ runtime: any DesktopRuntime) async {
        await runtime.suspend()
    }

    func resume(_ runtime: any DesktopRuntime) async throws {
        try await runtime.resume()
    }

    func shutdown(_ runtime: any DesktopRuntime) async {
        await runtime.shutdown()
    }
}

@MainActor
final class DesktopRuntimeProviderRegistry {
    private var providers: [String: any DesktopRuntimeProvider] = [:]

    func register(_ provider: any DesktopRuntimeProvider) throws {
        guard providers[provider.descriptor.id] == nil else {
            throw RuntimeProviderError.duplicateProvider(provider.descriptor.id)
        }
        providers[provider.descriptor.id] = provider
    }

    func provider(for choice: RuntimeChoice) throws -> any DesktopRuntimeProvider {
        guard let provider = providers.values
            .sorted(by: { $0.descriptor.id < $1.descriptor.id })
            .first(where: { $0.choices.contains(choice) }) else {
            throw RuntimeProviderError.noQualifiedProvider(applicationId: choice.rawValue)
        }
        return provider
    }

    static func standard() -> DesktopRuntimeProviderRegistry {
        let registry = DesktopRuntimeProviderRegistry()
        try? registry.register(WanixDesktopRuntimeProvider())
        return registry
    }
}

@MainActor
final class WanixDesktopRuntimeProvider: DesktopRuntimeProvider {
    let descriptor = RuntimeProviderDescriptor(
        id: "wanix",
        displayName: "Wanix",
        location: .phone,
        version: "1.0",
        supportedWorlds: [.wasip1],
        architectures: ["wasm32"],
        capabilities: .wanixDesktop,
        threadingProfiles: [.singleThreaded],
        enforcedQuotas: Set(WorkspaceQuotaKind.allCases)
    )
    let choices: Set<RuntimeChoice> = [.wanixDesktop, .wanixKernel]

    func makeRuntime(choice: RuntimeChoice, appearance: String) throws -> any DesktopRuntime {
        switch choice {
        case .wanixDesktop:
            return WanixRuntimeAdapter(
                choice: .wanixDesktop,
                appearance: appearance,
                capabilities: .wanixDesktop
            )
        case .wanixKernel:
            return WanixRuntimeAdapter(
                choice: .wanixKernel,
                appearance: appearance,
                capabilities: .wanixKernel
            )
        }
    }
}
