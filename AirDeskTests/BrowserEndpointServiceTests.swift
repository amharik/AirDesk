import Foundation
import XCTest
@testable import AirDesk

@MainActor
final class BrowserEndpointServiceTests: XCTestCase {
    private let origin = "http://127.0.0.1:51234"

    func testStartsLoopbackHostWithShortLivedTokenAndStops() throws {
        let service = BrowserEndpointService()
        defer { service.stop() }

        try service.start(allowedOrigin: origin)

        XCTAssertEqual(service.state, .running)
        XCTAssertNil(service.lastError)
        let endpointURL = try XCTUnwrap(service.endpointURL)
        XCTAssertEqual(endpointURL.scheme, "ws")
        XCTAssertEqual(endpointURL.host, "127.0.0.1")
        XCTAssertEqual(endpointURL.path, "/endpoint")
        let token = try XCTUnwrap(
            URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "token" })?
                .value
        )
        XCTAssertEqual(token.count, 43)
        XCTAssertTrue(BrowserEndpointValidation.isValidToken(token))

        service.stop()

        XCTAssertEqual(service.state, .stopped)
        XCTAssertNil(service.endpointURL)
        XCTAssertNil(service.lastError)
    }

    func testRestartRotatesToken() throws {
        let service = BrowserEndpointService()
        defer { service.stop() }

        try service.start(allowedOrigin: origin)
        let first = try XCTUnwrap(service.endpointURL)
        service.stop()
        try service.start(allowedOrigin: origin)
        let second = try XCTUnwrap(service.endpointURL)

        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(token(in: first), token(in: second))
    }

    func testStartingWhileRunningReusesEndpoint() throws {
        let service = BrowserEndpointService()
        defer { service.stop() }

        try service.start(allowedOrigin: origin)
        let first = service.endpointURL
        try service.start(allowedOrigin: origin)

        XCTAssertEqual(service.state, .running)
        XCTAssertEqual(service.endpointURL, first)
    }

    func testInvalidOriginLeavesServiceFailed() {
        let service = BrowserEndpointService()
        defer { service.stop() }

        XCTAssertThrowsError(try service.start(allowedOrigin: "https://example.com")) { error in
            XCTAssertEqual(
                error as? BrowserEndpointProtocolError,
                .invalidOrigin
            )
        }

        XCTAssertEqual(
            service.state,
            .failed(BrowserEndpointProtocolError.invalidOrigin.localizedDescription)
        )
        XCTAssertNotNil(service.lastError)
        XCTAssertNil(service.endpointURL)
    }

    private func token(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value
    }
}
