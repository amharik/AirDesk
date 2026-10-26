import Foundation

enum InputModifier: String, CaseIterable, Codable, Sendable, Identifiable {
    case command = "Meta"
    case option = "Alt"
    case control = "Control"
    case shift = "Shift"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }
}

struct InputEvent: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case pointerMove
        case pointerDown
        case pointerUp
        case pointerClick
        case pointerCancel
        case scroll
        case keyDown
        case keyUp
        case textInput
        case focusChanged
        case viewportChanged
        case sessionStart
        case sessionEnd
    }

    var version: Int = 1
    var type: Kind
    var sessionId: String
    var seq: Int
    var timestamp: Double
    var x: Double?
    var y: Double?
    var dx: Double?
    var dy: Double?
    var button: Int?
    var clickCount: Int?
    var key: String?
    var code: String?
    var modifiers: [String]?
    var text: String?
    var width: Double?
    var height: Double?
    var target: String?

    static func make(
        _ type: Kind,
        sessionId: String,
        seq: Int,
        x: Double? = nil,
        y: Double? = nil,
        dx: Double? = nil,
        dy: Double? = nil,
        button: Int? = nil,
        clickCount: Int? = nil,
        key: String? = nil,
        code: String? = nil,
        modifiers: [String]? = nil,
        text: String? = nil,
        width: Double? = nil,
        height: Double? = nil,
        target: String? = nil
    ) -> InputEvent {
        InputEvent(
            type: type,
            sessionId: sessionId,
            seq: seq,
            timestamp: Date().timeIntervalSince1970 * 1000,
            x: x,
            y: y,
            dx: dx,
            dy: dy,
            button: button,
            clickCount: clickCount,
            key: key,
            code: code,
            modifiers: modifiers,
            text: text,
            width: width,
            height: height,
            target: target
        )
    }

    private static let allowedModifiers = Set(InputModifier.allCases.map(\.rawValue))

    func validated() throws -> InputEvent {
        guard version == 1 else { throw InputEventError.unsupportedVersion }
        guard !sessionId.isEmpty, sessionId.count <= 64 else { throw InputEventError.invalidSession }
        guard seq >= 0 else { throw InputEventError.invalidSequence }
        guard timestamp.isFinite, timestamp > 0 else { throw InputEventError.invalidTimestamp }

        switch type {
        case .pointerMove, .pointerDown, .pointerUp, .pointerClick:
            guard let x, let y, x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
                throw InputEventError.invalidCoordinates
            }
        case .scroll:
            guard let dx, let dy, dx.isFinite, dy.isFinite, abs(dx) <= 20_000, abs(dy) <= 20_000 else {
                throw InputEventError.invalidDelta
            }
        case .textInput:
            guard let text, !text.isEmpty, text.count <= 4096, !text.contains("\u{0000}") else {
                throw InputEventError.invalidText
            }
        case .keyDown, .keyUp:
            guard let key, !key.isEmpty, key.count <= 64 else { throw InputEventError.invalidKey }
        case .viewportChanged:
            guard let width, let height, width > 0, height > 0, width <= 20_000, height <= 20_000 else {
                throw InputEventError.invalidViewport
            }
        case .pointerCancel, .focusChanged, .sessionStart, .sessionEnd:
            break
        }

        if let button, !(0...4).contains(button) { throw InputEventError.invalidButton }
        if let clickCount, !(1...3).contains(clickCount) { throw InputEventError.invalidClickCount }
        if let modifiers, !Set(modifiers).isSubset(of: Self.allowedModifiers) {
            throw InputEventError.invalidModifiers
        }
        if let target, target.count > 128 { throw InputEventError.invalidTarget }
        return self
    }

    func jsonObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InputEventError.encodingFailed
        }
        return object
    }
}

enum InputEventError: LocalizedError, Equatable {
    case unsupportedVersion
    case invalidSession
    case invalidSequence
    case invalidTimestamp
    case invalidCoordinates
    case invalidDelta
    case invalidText
    case invalidKey
    case invalidViewport
    case invalidButton
    case invalidClickCount
    case invalidModifiers
    case invalidTarget
    case encodingFailed
    case transportUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Unsupported input protocol version."
        case .invalidSession: return "Invalid session identifier."
        case .invalidSequence: return "Invalid input sequence."
        case .invalidTimestamp: return "Invalid input timestamp."
        case .invalidCoordinates: return "Pointer coordinates are outside the desktop bounds."
        case .invalidDelta: return "Scroll delta is outside supported bounds."
        case .invalidText: return "Text input is empty or too large."
        case .invalidKey: return "Invalid key event."
        case .invalidViewport: return "Invalid viewport dimensions."
        case .invalidButton: return "Unsupported pointer button."
        case .invalidClickCount: return "Unsupported click count."
        case .invalidModifiers: return "Unsupported keyboard modifier."
        case .invalidTarget: return "Invalid focus target."
        case .encodingFailed: return "Could not encode the input event."
        case .transportUnavailable: return "The desktop input channel is unavailable."
        }
    }
}
