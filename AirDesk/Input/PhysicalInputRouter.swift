import Combine
import CoreGraphics
import GameController
import UIKit

@MainActor
final class PhysicalInputRouter: ObservableObject {
    @Published private(set) var keyboardAvailable = false
    @Published private(set) var mouseAvailable = false
    @Published private(set) var isCaptured = true

    var viewport: CGSize = .zero
    var keyboardRoutingEnabled = true
    var onCursor: ((CursorAction, CGSize) -> Void)?
    var onText: ((String, Set<InputModifier>) -> Void)?
    var onKey: ((String, String?, Set<InputModifier>) -> Void)?
    var onRoutingChanged: ((Bool) -> Void)?

    var hasPeripherals: Bool { keyboardAvailable || mouseAvailable }
    var isRouting: Bool { isCaptured && hasPeripherals }

    private var observers: [NSObjectProtocol] = []
    private var keyboard: GCKeyboard?
    private var mouse: GCMouse?
    private var capsLock = false
    private var started = false
    private var lastRouting = false
    private var mousePressed = false
    private var mouseDragged = false
    private var mouseTravel: CGFloat = 0

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.attachKeyboard(notification.object as? GCKeyboard ?? GCKeyboard.coalesced)
            }
        })
        observers.append(center.addObserver(
            forName: .GCKeyboardDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let disconnected = notification.object as? GCKeyboard,
                   let keyboard = self.keyboard,
                   disconnected !== keyboard {
                    return
                }
                self.detachKeyboard()
            }
        })
        observers.append(center.addObserver(
            forName: .GCMouseDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.attachMouse(notification.object as? GCMouse ?? GCMouse.current)
            }
        })
        observers.append(center.addObserver(
            forName: Notification.Name("GCMouseDidBecomeCurrentNotification"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.attachMouse(notification.object as? GCMouse ?? GCMouse.current)
            }
        })
        observers.append(center.addObserver(
            forName: .GCMouseDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                if let disconnected = notification.object as? GCMouse,
                   let mouse = self.mouse,
                   disconnected !== mouse {
                    return
                }
                self.detachMouse()
            }
        })

        attachKeyboard(GCKeyboard.coalesced)
        attachMouse(GCMouse.current)
        publishRoutingIfNeeded()
    }

    func stop() {
        guard started else { return }
        started = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        detachKeyboard()
        detachMouse()
        if lastRouting {
            lastRouting = false
            onRoutingChanged?(false)
        }
    }

    func setCaptured(_ captured: Bool) {
        guard captured != isCaptured else { return }
        isCaptured = captured
        if !captured {
            mousePressed = false
            mouseDragged = false
            mouseTravel = 0
            onCursor?(.cancel, effectiveViewport)
        }
        publishRoutingIfNeeded()
    }

    private var effectiveViewport: CGSize {
        if viewport.width > 0, viewport.height > 0 {
            return viewport
        }
        let size = UIScreen.main.bounds.size
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 1024, height: 768)
    }

    private func publishRoutingIfNeeded() {
        let routing = isRouting
        guard routing != lastRouting else { return }
        lastRouting = routing
        onRoutingChanged?(routing)
    }

    private func attachKeyboard(_ keyboard: GCKeyboard?) {
        keyboard?.keyboardInput?.keyChangedHandler = nil
        self.keyboard = nil
        guard let keyboard else {
            keyboardAvailable = false
            publishRoutingIfNeeded()
            return
        }
        self.keyboard = keyboard
        keyboardAvailable = true
        isCaptured = true
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] input, _, keyCode, pressed in
            Task { @MainActor in
                self?.handleKey(keyCode, pressed: pressed, input: input)
            }
        }
        print("[AirDeskDebug] keyboard connected")
        publishRoutingIfNeeded()
    }

    private func detachKeyboard() {
        keyboard?.keyboardInput?.keyChangedHandler = nil
        keyboard = nil
        keyboardAvailable = false
        capsLock = false
        print("[AirDeskDebug] keyboard disconnected")
        publishRoutingIfNeeded()
    }

    private func attachMouse(_ mouse: GCMouse?) {
        mouse?.mouseInput?.mouseMovedHandler = nil
        mouse?.mouseInput?.leftButton.pressedChangedHandler = nil
        mouse?.mouseInput?.rightButton?.pressedChangedHandler = nil
        mouse?.mouseInput?.scroll.valueChangedHandler = nil
        self.mouse = nil
        mousePressed = false
        mouseDragged = false
        mouseTravel = 0

        guard let mouse, let input = mouse.mouseInput else {
            mouseAvailable = false
            publishRoutingIfNeeded()
            return
        }

        self.mouse = mouse
        mouseAvailable = true
        isCaptured = true

        input.mouseMovedHandler = { [weak self] _, dx, dy in
            Task { @MainActor in
                self?.handleMouseMove(dx: CGFloat(dx), dy: CGFloat(-dy))
            }
        }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                self?.handleMouseButton(pressed: pressed)
            }
        }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            Task { @MainActor in
                guard let self, self.isRouting, pressed else { return }
                self.onCursor?(.rightClick, self.effectiveViewport)
            }
        }
        input.scroll.valueChangedHandler = { [weak self] _, xValue, yValue in
            Task { @MainActor in
                guard let self, self.isRouting else { return }
                let dx = CGFloat(xValue) * 24
                let dy = CGFloat(yValue) * 24
                guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
                self.onCursor?(.scroll(dx: dx, dy: dy), self.effectiveViewport)
            }
        }
        print("[AirDeskDebug] mouse connected")
        publishRoutingIfNeeded()
    }

    private func detachMouse() {
        mouse?.mouseInput?.mouseMovedHandler = nil
        mouse?.mouseInput?.leftButton.pressedChangedHandler = nil
        mouse?.mouseInput?.rightButton?.pressedChangedHandler = nil
        mouse?.mouseInput?.scroll.valueChangedHandler = nil
        mouse = nil
        mouseAvailable = false
        mousePressed = false
        mouseDragged = false
        mouseTravel = 0
        print("[AirDeskDebug] mouse disconnected")
        publishRoutingIfNeeded()
    }

    private func handleMouseMove(dx: CGFloat, dy: CGFloat) {
        guard isRouting else { return }
        let viewport = effectiveViewport
        guard viewport.width > 0, viewport.height > 0 else { return }
        if mousePressed {
            mouseTravel += hypot(dx, dy)
            if mouseTravel > 3 {
                mouseDragged = true
            }
        }
        onCursor?(.move(dx: dx, dy: dy), viewport)
    }

    private func handleMouseButton(pressed: Bool) {
        guard isRouting else { return }
        let viewport = effectiveViewport
        if pressed {
            mousePressed = true
            mouseDragged = false
            mouseTravel = 0
            onCursor?(.dragBegan, viewport)
            return
        }
        guard mousePressed else { return }
        mousePressed = false
        onCursor?(.dragEnded, viewport)
        if !mouseDragged {
            onCursor?(.click(count: 1), viewport)
        }
        mouseDragged = false
        mouseTravel = 0
    }

    private func handleKey(_ keyCode: GCKeyCode, pressed: Bool, input: GCKeyboardInput) {
        guard isRouting, keyboardRoutingEnabled else { return }
        if keyCode == .capsLock {
            if pressed { capsLock.toggle() }
            return
        }
        guard pressed, !isModifier(keyCode) else { return }

        let modifiers = activeModifiers(input)
        if let special = specialKey(keyCode) {
            onKey?(special.key, special.code, modifiers)
            return
        }
        guard let text = text(for: keyCode, shift: modifiers.contains(.shift), caps: capsLock) else {
            return
        }
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            onKey?(text.lowercased(), nil, modifiers)
        } else {
            onText?(text, [])
        }
    }

    private func activeModifiers(_ input: GCKeyboardInput) -> Set<InputModifier> {
        var modifiers = Set<InputModifier>()
        if isPressed(.leftShift, in: input) || isPressed(.rightShift, in: input) {
            modifiers.insert(.shift)
        }
        if isPressed(.leftControl, in: input) || isPressed(.rightControl, in: input) {
            modifiers.insert(.control)
        }
        if isPressed(.leftAlt, in: input) || isPressed(.rightAlt, in: input) {
            modifiers.insert(.option)
        }
        if isPressed(.leftGUI, in: input) || isPressed(.rightGUI, in: input) {
            modifiers.insert(.command)
        }
        return modifiers
    }

    private func isPressed(_ keyCode: GCKeyCode, in input: GCKeyboardInput) -> Bool {
        input.button(forKeyCode: keyCode)?.isPressed == true
    }

    private func isModifier(_ keyCode: GCKeyCode) -> Bool {
        keyCode == .leftShift || keyCode == .rightShift
            || keyCode == .leftControl || keyCode == .rightControl
            || keyCode == .leftAlt || keyCode == .rightAlt
            || keyCode == .leftGUI || keyCode == .rightGUI
    }

    private func specialKey(_ keyCode: GCKeyCode) -> (key: String, code: String)? {
        switch keyCode {
        case .returnOrEnter, .keypadEnter: return ("Enter", "Enter")
        case .escape: return ("Escape", "Escape")
        case .deleteOrBackspace: return ("Backspace", "Backspace")
        case .deleteForward: return ("Delete", "Delete")
        case .tab: return ("Tab", "Tab")
        case .spacebar: return (" ", "Space")
        case .leftArrow: return ("ArrowLeft", "ArrowLeft")
        case .rightArrow: return ("ArrowRight", "ArrowRight")
        case .upArrow: return ("ArrowUp", "ArrowUp")
        case .downArrow: return ("ArrowDown", "ArrowDown")
        case .home: return ("Home", "Home")
        case .end: return ("End", "End")
        case .pageUp: return ("PageUp", "PageUp")
        case .pageDown: return ("PageDown", "PageDown")
        case .insert: return ("Insert", "Insert")
        case .F1: return ("F1", "F1")
        case .F2: return ("F2", "F2")
        case .F3: return ("F3", "F3")
        case .F4: return ("F4", "F4")
        case .F5: return ("F5", "F5")
        case .F6: return ("F6", "F6")
        case .F7: return ("F7", "F7")
        case .F8: return ("F8", "F8")
        case .F9: return ("F9", "F9")
        case .F10: return ("F10", "F10")
        case .F11: return ("F11", "F11")
        case .F12: return ("F12", "F12")
        default: return nil
        }
    }

    private func text(for keyCode: GCKeyCode, shift: Bool, caps: Bool) -> String? {
        switch keyCode {
        case .keyA: return letter("a", shift: shift, caps: caps)
        case .keyB: return letter("b", shift: shift, caps: caps)
        case .keyC: return letter("c", shift: shift, caps: caps)
        case .keyD: return letter("d", shift: shift, caps: caps)
        case .keyE: return letter("e", shift: shift, caps: caps)
        case .keyF: return letter("f", shift: shift, caps: caps)
        case .keyG: return letter("g", shift: shift, caps: caps)
        case .keyH: return letter("h", shift: shift, caps: caps)
        case .keyI: return letter("i", shift: shift, caps: caps)
        case .keyJ: return letter("j", shift: shift, caps: caps)
        case .keyK: return letter("k", shift: shift, caps: caps)
        case .keyL: return letter("l", shift: shift, caps: caps)
        case .keyM: return letter("m", shift: shift, caps: caps)
        case .keyN: return letter("n", shift: shift, caps: caps)
        case .keyO: return letter("o", shift: shift, caps: caps)
        case .keyP: return letter("p", shift: shift, caps: caps)
        case .keyQ: return letter("q", shift: shift, caps: caps)
        case .keyR: return letter("r", shift: shift, caps: caps)
        case .keyS: return letter("s", shift: shift, caps: caps)
        case .keyT: return letter("t", shift: shift, caps: caps)
        case .keyU: return letter("u", shift: shift, caps: caps)
        case .keyV: return letter("v", shift: shift, caps: caps)
        case .keyW: return letter("w", shift: shift, caps: caps)
        case .keyX: return letter("x", shift: shift, caps: caps)
        case .keyY: return letter("y", shift: shift, caps: caps)
        case .keyZ: return letter("z", shift: shift, caps: caps)
        case .one: return symbol("1", "!", shift: shift)
        case .two: return symbol("2", "@", shift: shift)
        case .three: return symbol("3", "#", shift: shift)
        case .four: return symbol("4", "$", shift: shift)
        case .five: return symbol("5", "%", shift: shift)
        case .six: return symbol("6", "^", shift: shift)
        case .seven: return symbol("7", "&", shift: shift)
        case .eight: return symbol("8", "*", shift: shift)
        case .nine: return symbol("9", "(", shift: shift)
        case .zero: return symbol("0", ")", shift: shift)
        case .hyphen: return symbol("-", "_", shift: shift)
        case .equalSign: return symbol("=", "+", shift: shift)
        case .openBracket: return symbol("[", "{", shift: shift)
        case .closeBracket: return symbol("]", "}", shift: shift)
        case .backslash: return symbol("\\", "|", shift: shift)
        case .semicolon: return symbol(";", ":", shift: shift)
        case .quote: return symbol("'", "\"", shift: shift)
        case .graveAccentAndTilde: return symbol("`", "~", shift: shift)
        case .comma: return symbol(",", "<", shift: shift)
        case .period: return symbol(".", ">", shift: shift)
        case .slash: return symbol("/", "?", shift: shift)
        case .keypadSlash: return "/"
        case .keypadAsterisk: return "*"
        case .keypadHyphen: return "-"
        case .keypadPlus: return "+"
        case .keypad1: return "1"
        case .keypad2: return "2"
        case .keypad3: return "3"
        case .keypad4: return "4"
        case .keypad5: return "5"
        case .keypad6: return "6"
        case .keypad7: return "7"
        case .keypad8: return "8"
        case .keypad9: return "9"
        case .keypad0: return "0"
        case .keypadPeriod: return "."
        case .keypadEqualSign: return "="
        default: return nil
        }
    }

    private func letter(_ value: String, shift: Bool, caps: Bool) -> String {
        (shift != caps) ? value.uppercased() : value
    }

    private func symbol(_ normal: String, _ shifted: String, shift: Bool) -> String {
        shift ? shifted : normal
    }
}
