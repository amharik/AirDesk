import Foundation

struct OneEuroFilterParameters: Equatable, Sendable {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    static let pointer = OneEuroFilterParameters(
        minCutoff: 1.0,
        beta: 160.0,
        dCutoff: 1.0
    )

    func validate() throws {
        guard minCutoff.isFinite, minCutoff > 0 else {
            throw OneEuroFilterError.invalidParameters("minCutoff")
        }
        guard beta.isFinite, beta >= 0 else {
            throw OneEuroFilterError.invalidParameters("beta")
        }
        guard dCutoff.isFinite, dCutoff > 0 else {
            throw OneEuroFilterError.invalidParameters("dCutoff")
        }
    }
}

enum OneEuroFilterError: Error, Equatable, LocalizedError {
    case invalidParameters(String)

    var errorDescription: String? {
        switch self {
        case .invalidParameters(let name):
            return "OneEuroFilter: invalid \(name)."
        }
    }
}

struct OneEuroFilter: Equatable, Sendable {
    static let minimumDeltaTime = 1.0 / 240.0

    private struct Axis: Equatable, Sendable {
        var previous = 0.0
        var filtered = 0.0
        var derivative = 0.0

        mutating func reset() {
            previous = 0
            filtered = 0
            derivative = 0
        }

        mutating func filter(
            _ value: Double,
            deltaTime: Double,
            parameters: OneEuroFilterParameters
        ) -> Double {
            let rawDerivative = (value - previous) / deltaTime
            let derivativeAlpha = Self.alpha(
                cutoff: parameters.dCutoff,
                deltaTime: deltaTime
            )
            derivative = Self.lowPass(
                input: rawDerivative,
                previous: derivative,
                alpha: derivativeAlpha
            )
            let cutoff = parameters.minCutoff + parameters.beta * abs(derivative)
            let valueAlpha = Self.alpha(cutoff: cutoff, deltaTime: deltaTime)
            let output = Self.lowPass(
                input: value,
                previous: filtered,
                alpha: valueAlpha
            )
            previous = value
            filtered = output
            return output
        }

        private static func alpha(cutoff: Double, deltaTime: Double) -> Double {
            guard cutoff.isFinite, cutoff > 0, deltaTime.isFinite, deltaTime > 0 else {
                return 1
            }
            let timeConstant = 1.0 / (2.0 * .pi * cutoff)
            return 1.0 / (1.0 + timeConstant / deltaTime)
        }

        private static func lowPass(input: Double, previous: Double, alpha: Double) -> Double {
            alpha * input + (1.0 - alpha) * previous
        }
    }

    private var xAxis = Axis()
    private var yAxis = Axis()
    private var lastTimestamp: Double?
    let parameters: OneEuroFilterParameters

    init(parameters: OneEuroFilterParameters = .pointer) {
        self.parameters = parameters
    }

    mutating func reset() {
        xAxis.reset()
        yAxis.reset()
        lastTimestamp = nil
    }

    mutating func filter(x: Double, y: Double, timestamp: Double) -> (x: Double, y: Double) {
        guard let previousTimestamp = lastTimestamp else {
            xAxis.previous = x
            xAxis.filtered = x
            yAxis.previous = y
            yAxis.filtered = y
            lastTimestamp = timestamp
            return (x, y)
        }
        let deltaTime = max(timestamp - previousTimestamp, Self.minimumDeltaTime)
        lastTimestamp = timestamp
        return (
            xAxis.filter(x, deltaTime: deltaTime, parameters: parameters),
            yAxis.filter(y, deltaTime: deltaTime, parameters: parameters)
        )
    }
}
