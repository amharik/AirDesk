import CoreGraphics
import Foundation

@MainActor
protocol InputTransport: AnyObject {
    var isAvailable: Bool { get }
    func send(_ event: InputEvent)
}

@MainActor
final class ClosureInputTransport: InputTransport {
    var isAvailable = true
    private let handler: (InputEvent) -> Void

    init(handler: @escaping (InputEvent) -> Void) {
        self.handler = handler
    }

    func send(_ event: InputEvent) {
        guard isAvailable else { return }
        handler(event)
    }
}

@MainActor
final class InputDispatcher {
    private(set) var sessionId: String = ""
    private(set) var currentPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var sequence: Int = 0
    var transport: (any InputTransport)?
    var onEventSent: ((InputEvent) -> Void)?

    private var pendingPoint: CGPoint?
    private var flushTask: Task<Void, Never>?
    private var pressedKeys: Set<String> = []
    private var activeButtons: Set<Int> = []
    private var isSessionActive = false

    private let autoFlush: Bool
    private let flushInterval: TimeInterval

    init(autoFlush: Bool = true, flushInterval: TimeInterval = 0.008) {
        self.autoFlush = autoFlush
        self.flushInterval = flushInterval
    }

    func startSession(id: String, viewport: CGSize = .zero) {
        sessionId = id
        sequence = 0
        currentPoint = CGPoint(x: 0.5, y: 0.5)
        pressedKeys.removeAll()
        activeButtons.removeAll()
        pendingPoint = nil
        isSessionActive = true
        send(.make(
            .sessionStart,
            sessionId: id,
            seq: nextSequence(),
            x: currentPoint.x,
            y: currentPoint.y,
            width: viewport.width > 0 ? Double(viewport.width) : nil,
            height: viewport.height > 0 ? Double(viewport.height) : nil
        ))
    }

    func updateViewport(_ size: CGSize) {
        guard isSessionActive, size.width > 0, size.height > 0 else { return }
        flushPendingMove()
        send(.make(
            .viewportChanged,
            sessionId: sessionId,
            seq: nextSequence(),
            width: Double(size.width),
            height: Double(size.height)
        ))
    }

    func move(to point: CGPoint) {
        guard isSessionActive else { return }
        currentPoint = CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
        pendingPoint = currentPoint
        guard autoFlush else { return }
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            let nanos = UInt64(max(self?.flushInterval ?? 0.008, 0.001) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.flushTask = nil
            self?.flushPendingMove()
        }
    }

    func click(button: Int = 0, count: Int = 1) {
        guard isSessionActive else { return }
        flushPendingMove()
        send(.make(
            .pointerClick,
            sessionId: sessionId,
            seq: nextSequence(),
            x: currentPoint.x,
            y: currentPoint.y,
            button: button,
            clickCount: min(max(count, 1), 3)
        ))
    }

    func pointerDown(button: Int = 0) {
        guard isSessionActive else { return }
        flushPendingMove()
        activeButtons.insert(button)
        send(.make(
            .pointerDown,
            sessionId: sessionId,
            seq: nextSequence(),
            x: currentPoint.x,
            y: currentPoint.y,
            button: button
        ))
    }

    func pointerUp(button: Int = 0) {
        guard isSessionActive else { return }
        flushPendingMove()
        activeButtons.remove(button)
        send(.make(
            .pointerUp,
            sessionId: sessionId,
            seq: nextSequence(),
            x: currentPoint.x,
            y: currentPoint.y,
            button: button
        ))
    }

    func scroll(dx: Double, dy: Double) {
        guard isSessionActive, dx != 0 || dy != 0 else { return }
        flushPendingMove()
        send(.make(
            .scroll,
            sessionId: sessionId,
            seq: nextSequence(),
            dx: dx,
            dy: dy
        ))
    }

    func textInput(_ text: String) {
        guard isSessionActive, !text.isEmpty else { return }
        flushPendingMove()
        send(.make(
            .textInput,
            sessionId: sessionId,
            seq: nextSequence(),
            text: String(text.prefix(4096))
        ))
    }

    func keyDown(_ key: String, code: String? = nil, modifiers: Set<InputModifier> = []) {
        guard isSessionActive, !key.isEmpty else { return }
        flushPendingMove()
        pressedKeys.insert(key)
        send(.make(
            .keyDown,
            sessionId: sessionId,
            seq: nextSequence(),
            key: String(key.prefix(64)),
            code: code,
            modifiers: modifiers.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue)
        ))
    }

    func keyUp(_ key: String, code: String? = nil, modifiers: Set<InputModifier> = []) {
        guard isSessionActive, !key.isEmpty else { return }
        flushPendingMove()
        pressedKeys.remove(key)
        send(.make(
            .keyUp,
            sessionId: sessionId,
            seq: nextSequence(),
            key: String(key.prefix(64)),
            code: code,
            modifiers: modifiers.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue)
        ))
    }

    func tapKey(_ key: String, code: String? = nil, modifiers: Set<InputModifier> = []) {
        keyDown(key, code: code, modifiers: modifiers)
        keyUp(key, code: code, modifiers: modifiers)
    }

    func focusChanged(_ target: String) {
        guard isSessionActive else { return }
        flushPendingMove()
        send(.make(
            .focusChanged,
            sessionId: sessionId,
            seq: nextSequence(),
            target: String(target.prefix(128))
        ))
    }

    func cancelAllInput() {
        guard isSessionActive else { return }
        flushTask?.cancel()
        flushTask = nil
        pendingPoint = nil
        send(.make(
            .pointerCancel,
            sessionId: sessionId,
            seq: nextSequence(),
            x: currentPoint.x,
            y: currentPoint.y
        ))
        for button in activeButtons.sorted() {
            send(.make(
                .pointerUp,
                sessionId: sessionId,
                seq: nextSequence(),
                x: currentPoint.x,
                y: currentPoint.y,
                button: button
            ))
        }
        for key in pressedKeys.sorted() {
            send(.make(
                .keyUp,
                sessionId: sessionId,
                seq: nextSequence(),
                key: key
            ))
        }
        activeButtons.removeAll()
        pressedKeys.removeAll()
    }

    func endSession() {
        guard isSessionActive else { return }
        cancelAllInput()
        send(.make(
            .sessionEnd,
            sessionId: sessionId,
            seq: nextSequence()
        ))
        flushTask?.cancel()
        flushTask = nil
        pendingPoint = nil
        isSessionActive = false
    }

    func flushPendingMove() {
        flushTask?.cancel()
        flushTask = nil
        guard let point = pendingPoint else { return }
        pendingPoint = nil
        send(.make(
            .pointerMove,
            sessionId: sessionId,
            seq: nextSequence(),
            x: point.x,
            y: point.y
        ))
    }

    private func nextSequence() -> Int {
        defer { sequence += 1 }
        return sequence
    }

    private func send(_ event: InputEvent) {
        guard let transport, transport.isAvailable else { return }
        guard let validated = try? event.validated() else { return }
        transport.send(validated)
        onEventSent?(validated)
    }
}
