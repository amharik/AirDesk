import XCTest
@testable import AirDesk

final class OneEuroFilterTests: XCTestCase {
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("protocol/fixtures/input/one-euro-v1.json")

    private struct Fixture: Decodable {
        let version: Int
        let name: String
        let parameters: Parameters
        let cases: [Case]

        struct Parameters: Decodable {
            let minCutoff: Double
            let beta: Double
            let dCutoff: Double

            enum CodingKeys: String, CodingKey {
                case minCutoff = "min_cutoff"
                case beta
                case dCutoff = "d_cutoff"
            }

            var filterParameters: OneEuroFilterParameters {
                OneEuroFilterParameters(
                    minCutoff: minCutoff,
                    beta: beta,
                    dCutoff: dCutoff
                )
            }
        }

        struct Case: Decodable {
            let name: String
            let samples: [Sample]
            let expected: [Sample]
        }

        struct Sample: Decodable {
            let t: Double
            let x: Double
            let y: Double
        }
    }

    func testFixtureMatchesSharedFilterOutputs() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture.version, 1)
        XCTAssertEqual(fixture.name, "one-euro-v1")
        XCTAssertEqual(fixture.parameters.beta, 160)
        XCTAssertFalse(fixture.cases.isEmpty)

        for testCase in fixture.cases {
            XCTAssertEqual(testCase.expected.count, testCase.samples.count)
            var filter = OneEuroFilter(parameters: fixture.parameters.filterParameters)
            for (index, sample) in testCase.samples.enumerated() {
                let output = filter.filter(x: sample.x, y: sample.y, timestamp: sample.t)
                XCTAssertEqual(output.x, testCase.expected[index].x, accuracy: 1e-9, testCase.name)
                XCTAssertEqual(output.y, testCase.expected[index].y, accuracy: 1e-9, testCase.name)
            }
        }
    }

    func testHighSpeedTrackingHasNoMaterialPhaseLag() throws {
        let testCase = try XCTUnwrap(loadFixture().cases.first { $0.name == "high-speed-tracking" })
        var filter = OneEuroFilter()
        var errors: [Double] = []
        for sample in testCase.samples {
            let output = filter.filter(x: sample.x, y: sample.y, timestamp: sample.t)
            errors.append(hypot(output.x - sample.x, output.y - sample.y))
        }
        let warmup = errors.dropFirst(10)
        XCTAssertFalse(warmup.isEmpty)
        XCTAssertLessThan(warmup.max() ?? .infinity, 0.005)
        XCTAssertLessThan(errors.last ?? .infinity, 0.003)
    }

    func testLowSpeedJitterIsAttenuated() throws {
        let testCase = try XCTUnwrap(loadFixture().cases.first { $0.name == "low-speed-jitter" })
        var filter = OneEuroFilter()
        var outputs: [(x: Double, y: Double)] = []
        for sample in testCase.samples {
            outputs.append(filter.filter(x: sample.x, y: sample.y, timestamp: sample.t))
        }
        let filtered = outputs.dropFirst(10).map(\.x)
        let raw = testCase.samples.dropFirst(10).map(\.x)
        let filteredRange = (filtered.max() ?? 0) - (filtered.min() ?? 0)
        let rawRange = (raw.max() ?? 0) - (raw.min() ?? 0)
        XCTAssertGreaterThan(rawRange, 0)
        XCTAssertLessThan(filteredRange, rawRange * 0.2)
    }

    func testResetRestartsAtNextSample() {
        var filter = OneEuroFilter()
        _ = filter.filter(x: 0.2, y: 0.3, timestamp: 0)
        _ = filter.filter(x: 0.8, y: 0.7, timestamp: 1.0 / 120.0)
        filter.reset()
        let output = filter.filter(x: 0.6, y: 0.4, timestamp: 2.0 / 120.0)
        XCTAssertEqual(output.x, 0.6)
        XCTAssertEqual(output.y, 0.4)
    }

    func testInvalidParametersAreRejected() {
        XCTAssertThrowsError(
            try OneEuroFilterParameters(minCutoff: 0, beta: 1, dCutoff: 1).validate()
        ) { error in
            XCTAssertEqual(error as? OneEuroFilterError, .invalidParameters("minCutoff"))
        }
        XCTAssertThrowsError(
            try OneEuroFilterParameters(minCutoff: 1, beta: -1, dCutoff: 1).validate()
        ) { error in
            XCTAssertEqual(error as? OneEuroFilterError, .invalidParameters("beta"))
        }
        XCTAssertThrowsError(
            try OneEuroFilterParameters(minCutoff: 1, beta: 1, dCutoff: 0).validate()
        ) { error in
            XCTAssertEqual(error as? OneEuroFilterError, .invalidParameters("dCutoff"))
        }
    }

    private func loadFixture() throws -> Fixture {
        let data = try Data(contentsOf: Self.fixtureURL)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }
}
