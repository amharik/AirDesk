import Foundation

enum SemanticContextMode: String, CaseIterable, Identifiable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .a: return "Extended desktop"
        case .b: return "Mirrored presentation"
        case .c: return "Cast desktop"
        case .d: return "Controller"
        }
    }

    static func resolve(sessionMode: SessionMode, isSessionReady: Bool) -> SemanticContextMode {
        guard isSessionReady else { return .d }
        switch sessionMode {
        case .extended: return .a
        case .mirrored: return .b
        case .cast: return .c
        case .preview: return .d
        }
    }
}

enum TerminalCommandPhase: String, Equatable, Sendable {
    case unknown
    case prompt
    case input
    case running
    case finished

    var label: String {
        switch self {
        case .unknown: return "TERM"
        case .prompt: return "PROMPT"
        case .input: return "TYPING"
        case .running: return "RUNNING"
        case .finished: return "DONE"
        }
    }
}

enum OSC133Event: Equatable, Sendable {
    case prompt
    case input
    case running
    case finished(exitCode: Int?)

    var phase: TerminalCommandPhase {
        switch self {
        case .prompt: return .prompt
        case .input: return .input
        case .running: return .running
        case .finished: return .finished
        }
    }
}

struct OSC133Parser: Sendable {
    static let maximumPayloadBytes = 512

    private enum ParseState: Sendable {
        case ground
        case escape
        case osc
        case oscEscape
    }

    private var state: ParseState = .ground
    private var payload: [UInt8] = []
    private(set) var phase: TerminalCommandPhase = .unknown

    mutating func reset() {
        state = .ground
        payload.removeAll(keepingCapacity: true)
        phase = .unknown
    }

    mutating func consume(_ data: Data) -> [OSC133Event] {
        var events: [OSC133Event] = []
        for byte in data {
            switch state {
            case .ground:
                if byte == 0x1B {
                    state = .escape
                }
            case .escape:
                if byte == 0x5D {
                    payload.removeAll(keepingCapacity: true)
                    state = .osc
                } else if byte != 0x1B {
                    state = .ground
                }
            case .osc:
                if byte == 0x07 {
                    if let event = finishOSC() {
                        events.append(event)
                    }
                } else if byte == 0x1B {
                    state = .oscEscape
                } else if payload.count < Self.maximumPayloadBytes {
                    payload.append(byte)
                }
            case .oscEscape:
                if byte == 0x5C {
                    if let event = finishOSC() {
                        events.append(event)
                    }
                } else if byte != 0x1B {
                    payload.removeAll(keepingCapacity: true)
                    state = .ground
                }
            }
        }
        return events
    }

    private mutating func finishOSC() -> OSC133Event? {
        let text = String(decoding: payload, as: UTF8.self)
        payload.removeAll(keepingCapacity: true)
        state = .ground

        let fields = text.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 2, fields[0] == "133" else { return nil }

        let event: OSC133Event
        switch fields[1] {
        case "A":
            event = .prompt
        case "B":
            event = .input
        case "C":
            event = .running
        case "D":
            let exitCode = fields.count > 2 ? Int(fields[2]) : nil
            event = .finished(exitCode: exitCode)
        default:
            return nil
        }
        phase = event.phase
        return event
    }
}

enum SemanticInputCapability: String, Hashable, Sendable {
    case sessionRecovery
    case desktopControl
    case keyboard
    case pointer
    case windowManagement
}

enum SemanticInputAction: String, CaseIterable, Identifiable, Sendable {
    case escape
    case tab
    case returnKey
    case backspace
    case arrowLeft
    case arrowUp
    case arrowDown
    case arrowRight
    case interrupt
    case clearScreen
    case previousCommand
    case dock
    case reconnect
    case diagnostics
    case endSession

    var id: String { rawValue }

    var label: String {
        switch self {
        case .escape: return "Esc"
        case .tab: return "Tab"
        case .returnKey: return "Return"
        case .backspace: return "Delete"
        case .arrowLeft: return "Left"
        case .arrowUp: return "Up"
        case .arrowDown: return "Down"
        case .arrowRight: return "Right"
        case .interrupt: return "Stop"
        case .clearScreen: return "Clear"
        case .previousCommand: return "History"
        case .dock: return "Dock"
        case .reconnect: return "Reconnect"
        case .diagnostics: return "Diagnostics"
        case .endSession: return "End"
        }
    }

    var systemImage: String {
        switch self {
        case .escape: return "escape"
        case .tab: return "arrow.right.to.line"
        case .returnKey: return "return"
        case .backspace: return "delete.left"
        case .arrowLeft: return "arrow.left"
        case .arrowUp: return "arrow.up"
        case .arrowDown: return "arrow.down"
        case .arrowRight: return "arrow.right"
        case .interrupt: return "stop.fill"
        case .clearScreen: return "rectangle.slash"
        case .previousCommand: return "clock.arrow.circlepath"
        case .dock: return "house"
        case .reconnect: return "arrow.clockwise"
        case .diagnostics: return "waveform.path.ecg"
        case .endSession: return "xmark.circle"
        }
    }

    var allowedModes: Set<SemanticContextMode> {
        switch self {
        case .dock:
            return [.a, .c]
        case .reconnect:
            return [.d]
        case .escape, .tab, .returnKey, .backspace,
             .arrowLeft, .arrowUp, .arrowDown, .arrowRight,
             .interrupt, .clearScreen, .previousCommand,
             .diagnostics, .endSession:
            return Set(SemanticContextMode.allCases)
        }
    }

    var requiredCapabilities: Set<SemanticInputCapability> {
        switch self {
        case .escape, .tab, .returnKey, .backspace,
             .arrowLeft, .arrowUp, .arrowDown, .arrowRight,
             .interrupt, .clearScreen, .previousCommand:
            return [.desktopControl, .keyboard]
        case .dock:
            return [.desktopControl, .keyboard, .windowManagement]
        case .reconnect, .diagnostics, .endSession:
            return [.sessionRecovery]
        }
    }

    var requiresReadySession: Bool {
        switch self {
        case .reconnect, .diagnostics, .endSession: return false
        default: return true
        }
    }

    var requiresInputLease: Bool {
        switch self {
        case .reconnect, .diagnostics, .endSession: return false
        default: return true
        }
    }
}

enum SemanticInputDenial: Error, Equatable, LocalizedError {
    case sessionNotReady
    case modeNotSupported(SemanticContextMode)
    case capabilityMissing(SemanticInputCapability)
    case inputLeaseMissing

    var errorDescription: String? {
        switch self {
        case .sessionNotReady:
            return "The desktop session is not ready."
        case .modeNotSupported(let mode):
            return "This action is not available in context mode \(mode.rawValue)."
        case .capabilityMissing(let capability):
            return "This action requires the \(capability.rawValue) capability."
        case .inputLeaseMissing:
            return "This action requires an active local input lease."
        }
    }
}

struct SemanticInputAuthorizationContext: Equatable, Sendable {
    var mode: SemanticContextMode
    var terminalPhase: TerminalCommandPhase
    var availableCapabilities: Set<SemanticInputCapability>
    var activeControllerId: String?
    var localControllerId: String
    var leaseEpoch: UInt64
    var isSessionReady: Bool

    func denial(for action: SemanticInputAction) -> SemanticInputDenial? {
        if action.requiresReadySession, !isSessionReady {
            return .sessionNotReady
        }
        if !action.allowedModes.contains(mode) {
            return .modeNotSupported(mode)
        }
        if let missing = action.requiredCapabilities.subtracting(availableCapabilities).sorted(by: { $0.rawValue < $1.rawValue }).first {
            return .capabilityMissing(missing)
        }
        if action.requiresInputLease,
           activeControllerId != localControllerId || leaseEpoch == 0 {
            return .inputLeaseMissing
        }
        return nil
    }

    func allows(_ action: SemanticInputAction) -> Bool {
        denial(for: action) == nil
    }
}

struct SemanticInputDeckLayout: Equatable, Sendable {
    var mode: SemanticContextMode
    var terminalPhase: TerminalCommandPhase
    var actions: [SemanticInputAction]
    var gestureHint: String
    var statusText: String
    var showsKeyboard: Bool
    var showsTrackpad: Bool

    static func resolve(context: SemanticInputAuthorizationContext) -> SemanticInputDeckLayout {
        let terminalActions: [SemanticInputAction]
        if context.isSessionReady {
            switch context.terminalPhase {
            case .running:
                terminalActions = [.interrupt]
            case .prompt, .input, .finished:
                terminalActions = [.clearScreen, .previousCommand]
            case .unknown:
                terminalActions = []
            }
        } else {
            terminalActions = []
        }

        let modeActions: [SemanticInputAction]
        switch context.mode {
        case .a:
            modeActions = [.dock, .diagnostics]
        case .b:
            modeActions = [.diagnostics]
        case .c:
            modeActions = [.dock, .diagnostics]
        case .d:
            modeActions = context.isSessionReady
                ? [.diagnostics]
                : [.reconnect, .diagnostics, .endSession]
        }

        return SemanticInputDeckLayout(
            mode: context.mode,
            terminalPhase: context.terminalPhase,
            actions: terminalActions + modeActions,
            gestureHint: gestureHint(for: context),
            statusText: "MODE \(context.mode.rawValue) · \(context.isSessionReady ? context.terminalPhase.label : "DISCONNECTED")",
            showsKeyboard: context.isSessionReady,
            showsTrackpad: context.isSessionReady
        )
    }

    private static func gestureHint(for context: SemanticInputAuthorizationContext) -> String {
        guard context.isSessionReady else {
            return "NO DISPLAY PATH · RECONNECT OR OPEN DIAGNOSTICS"
        }
        switch context.mode {
        case .a:
            return "DRAG KEY OR DOUBLE-TAP + DRAG OR THREE-FINGER DRAG TO MOVE WINDOWS"
        case .b:
            return "TAP TO CLICK · TWO-FINGER SCROLL · DRAG TO SELECT"
        case .c:
            return "TAP TO CLICK · DRAG TO SELECT · DOCK FROM THE ACTION BAR"
        case .d:
            return "PREVIEW CONTROLLER · TAP TO CLICK · TWO-FINGER SCROLL"
        }
    }
}
