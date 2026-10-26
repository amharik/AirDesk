import XCTest
@testable import AirDesk

final class OriginPolicyTests: XCTestCase {
    private let baseURL = URL(fileURLWithPath: "/tmp/AirDeskShell")

    func testFileURLInsideAllowedDirectoryIsAllowed() {
        let policy = OriginPolicy(allowedFileDirectory: baseURL)
        XCTAssertTrue(policy.isAllowedNavigation(baseURL.appendingPathComponent("index.html")))
        XCTAssertTrue(policy.isAllowedNavigation(baseURL))
    }

    func testSiblingPathWithSharedPrefixIsRejected() {
        let policy = OriginPolicy(allowedFileDirectory: baseURL)
        XCTAssertFalse(policy.isAllowedNavigation(URL(fileURLWithPath: "/tmp/AirDeskShellEvil/index.html")))
    }

    func testParentTraversalIsRejected() {
        let policy = OriginPolicy(allowedFileDirectory: baseURL)
        XCTAssertFalse(policy.isAllowedNavigation(URL(fileURLWithPath: "/tmp/secret.txt")))
    }

    func testHTTPSOriginIsAllowed() {
        let policy = OriginPolicy(allowedOrigins: ["https://desk.example.com"])
        XCTAssertTrue(policy.isAllowedNavigation(URL(string: "https://desk.example.com/shell/index.html")!))
    }

    func testPlainHTTPIsRejected() {
        let policy = OriginPolicy(allowedOrigins: ["desk.example.com"])
        XCTAssertFalse(policy.isAllowedNavigation(URL(string: "http://desk.example.com/shell")!))
    }

    func testRemoteRuntimeRequiresConfiguredHost() {
        let url = URL(string: "https://runtime.example.com/app")!
        XCTAssertTrue(OriginPolicy.isAllowedRemoteRuntime(url, configuredOrigin: "runtime.example.com"))
        XCTAssertTrue(OriginPolicy.isAllowedRemoteRuntime(url, configuredOrigin: "https://runtime.example.com"))
        XCTAssertFalse(OriginPolicy.isAllowedRemoteRuntime(url, configuredOrigin: nil))
        XCTAssertFalse(OriginPolicy.isAllowedRemoteRuntime(url, configuredOrigin: "other.example.com"))
    }

    func testBridgeTypeValidation() {
        let policy = OriginPolicy()
        XCTAssertTrue(policy.isAllowedBridgeType("ready"))
        XCTAssertTrue(policy.isAllowedBridgeType("ack"))
        XCTAssertFalse(policy.isAllowedBridgeType("execute"))
    }
}
