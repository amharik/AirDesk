import XCTest
@testable import AirDesk

@MainActor
final class DesktopRuntimeProviderTests: XCTestCase {
    func testStandardRegistrySelectsProviderForEveryRuntimeChoice() throws {
        let registry = DesktopRuntimeProviderRegistry.standard()

        XCTAssertEqual(try registry.provider(for: .wanixDesktop).descriptor.id, "wanix")
        XCTAssertEqual(try registry.provider(for: .wanixKernel).descriptor.id, "wanix")
        XCTAssertEqual(try registry.provider(for: .puter).descriptor.id, "puter")
    }

    func testRegistryRejectsDuplicateAndMissingProviders() throws {
        let registry = DesktopRuntimeProviderRegistry()
        XCTAssertThrowsError(try registry.provider(for: .wanixDesktop))

        let provider = StubDesktopRuntimeProvider()
        try registry.register(provider)
        XCTAssertThrowsError(try registry.register(provider)) { error in
            XCTAssertEqual(error as? RuntimeProviderError, .duplicateProvider("stub"))
        }
    }

    func testWanixProviderCreatesRuntimeForEachWanixChoice() throws {
        let provider = WanixDesktopRuntimeProvider()

        let desktop = try provider.makeRuntime(choice: .wanixDesktop, appearance: "dark")
        XCTAssertEqual(desktop.capabilities, .wanixDesktop)

        let kernel = try provider.makeRuntime(choice: .wanixKernel, appearance: "light")
        XCTAssertEqual(kernel.capabilities, .wanixKernel)

        XCTAssertThrowsError(try provider.makeRuntime(choice: .puter, appearance: "dark"))
    }
}

@MainActor
private final class StubDesktopRuntimeProvider: DesktopRuntimeProvider {
    let descriptor = RuntimeProviderDescriptor(
        id: "stub",
        displayName: "Stub",
        location: .phone,
        version: "1",
        supportedWorlds: [.wasip1],
        architectures: ["wasm32"],
        capabilities: .wanixDesktop
    )
    let choices: Set<RuntimeChoice> = [.wanixDesktop]

    func makeRuntime(choice: RuntimeChoice, appearance: String) throws -> any DesktopRuntime {
        throw RuntimeProviderError.providerFailure("not implemented")
    }
}
