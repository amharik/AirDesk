import SwiftUI

private enum MacKeyAction: Equatable {
    case text(text: String, shifted: String?, key: String, code: String?, capsSensitive: Bool)
    case key(name: String, code: String?)
    case modifier(InputModifier)
    case capsLock
    case dragMode
    case none
}

private enum MacKeyKind: Equatable {
    case standard
    case function
    case touchID
    case arrowCluster
}

private struct MacKey: Identifiable {
    let id: String
    var label: String = ""
    var sublabel: String?
    var systemImage: String?
    var width: CGFloat = 1
    var kind: MacKeyKind = .standard
    var action: MacKeyAction = .none
    var accessibilityLabel: String?
}

struct MacInputDeck: View {
    let activeModifiers: Set<InputModifier>
    let onCursor: (CursorAction, CGSize) -> Void
    let onKey: (String, String?, Set<InputModifier>) -> Void
    let onText: (String, Set<InputModifier>) -> Void
    let onModifier: (InputModifier) -> Void
    let onClearModifiers: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var dragMode = false

    private let deckSize = CGSize(width: 1180, height: 620)
    private let keyboardSize = CGSize(width: 1140, height: 290)
    private let trackpadSize = CGSize(width: 500, height: 240)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / deckSize.width,
                proxy.size.height / deckSize.height,
                1.35
            )
            deck
                .frame(width: deckSize.width, height: deckSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: deckSize.width * scale, height: deckSize.height * scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var deck: some View {
        VStack(spacing: 14) {
            MacKeyboardView(
                activeModifiers: activeModifiers,
                dragMode: $dragMode,
                hapticsEnabled: settings.hapticsEnabled,
                onKey: onKey,
                onText: onText,
                onModifier: onModifier,
                onClearModifiers: onClearModifiers
            )
            .frame(width: keyboardSize.width, height: keyboardSize.height)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
                    }
            }

            MacTrackpadView(
                onAction: onCursor,
                showsHints: settings.showInteractionHints,
                dragMode: dragMode
            )
            .frame(width: trackpadSize.width, height: trackpadSize.height)
            .overlay(alignment: .topTrailing) {
                if dragMode {
                    Text("DRAGGING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(ADTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background { Capsule().fill(Color.white.opacity(0.14)) }
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }

            Text("MACBOOK INPUT  ·  DRAG KEY OR DOUBLE-TAP + DRAG OR THREE-FINGER DRAG TO MOVE WINDOWS")
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(ADTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: deckSize.width, height: deckSize.height)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x2D2D30), Color(hex: 0x171719), Color(hex: 0x101012)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 28)
                }
                .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Circle().fill(ADTheme.accent.opacity(0.8)).frame(width: 5, height: 5)
                Text("TRACKPAD + KEYBOARD")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(ADTheme.textTertiary)
            }
            .padding(.leading, 28)
            .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            if !activeModifiers.isEmpty {
                Text(activeModifiers.sorted { $0.rawValue < $1.rawValue }.map(\.symbol).joined())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ADTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(ADTheme.accent.opacity(0.12)) }
                    .padding(.trailing, 28)
                    .padding(.top, 7)
            }
        }
    }
}

private struct MacKeyboardView: View {
    let activeModifiers: Set<InputModifier>
    @Binding var dragMode: Bool
    let hapticsEnabled: Bool
    let onKey: (String, String?, Set<InputModifier>) -> Void
    let onText: (String, Set<InputModifier>) -> Void
    let onModifier: (InputModifier) -> Void
    let onClearModifiers: () -> Void

    @State private var capsLock = false

    private let gap: CGFloat = 6
    private let standardHeight: CGFloat = 46
    private let functionHeight: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 15
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: gap) {
                        ForEach(row) { key in
                            if key.kind == .arrowCluster {
                                MacArrowCluster(
                                    width: key.width * unit - gap,
                                    height: standardHeight,
                                    hapticsEnabled: hapticsEnabled,
                                    onKey: onKey
                                )
                            } else {
                                MacKeycap(
                                    key: key,
                                    width: key.width * unit - gap,
                                    height: key.kind == .function ? functionHeight : standardHeight,
                                    active: isActive(key),
                                    hapticsEnabled: hapticsEnabled
                                ) {
                                    perform(key)
                                }
                            }
                        }
                    }
                    .frame(width: proxy.size.width, height: keyHeight(for: row))
                }
            }
        }
    }

    private func keyHeight(for row: [MacKey]) -> CGFloat {
        row.contains { $0.kind == .function } ? functionHeight : standardHeight
    }

    private func isActive(_ key: MacKey) -> Bool {
        switch key.action {
        case .modifier(let modifier):
            return activeModifiers.contains(modifier)
        case .capsLock:
            return capsLock
        case .dragMode:
            return dragMode
        default:
            return false
        }
    }

    private func perform(_ key: MacKey) {
        let modifiers = activeModifiers
        switch key.action {
        case .modifier(let modifier):
            onModifier(modifier)
        case .capsLock:
            capsLock.toggle()
        case .dragMode:
            dragMode.toggle()
            if dragMode {
                onClearModifiers()
            }
        case .text(let text, let shifted, let shortcutKey, let code, let capsSensitive):
            if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
                onKey(shortcutKey, code, modifiers)
            } else {
                let shift = modifiers.contains(.shift)
                let useShifted = capsSensitive ? shift != capsLock : shift
                onText(useShifted ? (shifted ?? text) : text, [])
            }
            if !modifiers.isEmpty {
                onClearModifiers()
            }
        case .key(let name, let code):
            onKey(name, code, modifiers)
            if !modifiers.isEmpty {
                onClearModifiers()
            }
        case .none:
            break
        }
    }

    private var rows: [[MacKey]] {
        [functionRow, numberRow, tabRow, capsRow, shiftRow, bottomRow]
    }

    private var functionRow: [MacKey] {
        var keys = [
            MacKey(id: "esc", label: "esc", width: 1.5, action: .key(name: "Escape", code: "Escape"), accessibilityLabel: "Escape")
        ]
        let functions: [(String, String)] = [
            ("F1", "sun.max"),
            ("F2", "sun.max.fill"),
            ("F3", "rectangle.3.group"),
            ("F4", "magnifyingglass"),
            ("F5", "mic.fill"),
            ("F6", "moon.zzz.fill"),
            ("F7", "backward.fill"),
            ("F8", "playpause.fill"),
            ("F9", "forward.fill"),
            ("F10", "speaker.slash.fill"),
            ("F11", "speaker.wave.1.fill"),
            ("F12", "speaker.wave.3.fill")
        ]
        for (name, icon) in functions {
            keys.append(MacKey(
                id: "function.\(name)",
                label: name,
                systemImage: icon,
                width: 0.9,
                kind: .function,
                action: .key(name: name, code: name),
                accessibilityLabel: name
            ))
        }
        keys.append(MacKey(
            id: "dragmode",
            label: "drag",
            width: 1.2,
            kind: .function,
            action: .dragMode,
            accessibilityLabel: "Window drag mode"
        ))
        keys.append(MacKey(
            id: "touchid",
            systemImage: "touchid",
            width: 1.5,
            kind: .touchID,
            accessibilityLabel: "Touch ID"
        ))
        return keys
    }

    private var numberRow: [MacKey] {
        [
            textKey("backtick", label: "`", shifted: "~", key: "`", code: "Backquote"),
            textKey("one", label: "1", shifted: "!", key: "1", code: "Digit1"),
            textKey("two", label: "2", shifted: "@", key: "2", code: "Digit2"),
            textKey("three", label: "3", shifted: "#", key: "3", code: "Digit3"),
            textKey("four", label: "4", shifted: "$", key: "4", code: "Digit4"),
            textKey("five", label: "5", shifted: "%", key: "5", code: "Digit5"),
            textKey("six", label: "6", shifted: "^", key: "6", code: "Digit6"),
            textKey("seven", label: "7", shifted: "&", key: "7", code: "Digit7"),
            textKey("eight", label: "8", shifted: "*", key: "8", code: "Digit8"),
            textKey("nine", label: "9", shifted: "(", key: "9", code: "Digit9"),
            textKey("zero", label: "0", shifted: ")", key: "0", code: "Digit0"),
            textKey("minus", label: "-", shifted: "_", key: "-", code: "Minus"),
            textKey("equal", label: "=", shifted: "+", key: "=", code: "Equal"),
            MacKey(id: "delete", label: "delete", width: 2, action: .key(name: "Backspace", code: "Backspace"), accessibilityLabel: "Delete")
        ]
    }

    private var tabRow: [MacKey] {
        [
            MacKey(id: "tab", label: "tab", width: 1.5, action: .key(name: "Tab", code: "Tab"), accessibilityLabel: "Tab")
        ] + letterKeys("QWERTYUIOP") + [
            textKey("leftBracket", label: "[", shifted: "{", key: "[", code: "BracketLeft"),
            textKey("rightBracket", label: "]", shifted: "}", key: "]", code: "BracketRight"),
            textKey("backslash", label: "\\", shifted: "|", key: "\\", code: "Backslash", width: 1.5)
        ]
    }

    private var capsRow: [MacKey] {
        [
            MacKey(id: "caps", label: "caps lock", width: 1.75, action: .capsLock, accessibilityLabel: "Caps Lock")
        ] + letterKeys("ASDFGHJKL") + [
            textKey("semicolon", label: ";", shifted: ":", key: ";", code: "Semicolon"),
            textKey("quote", label: "'", shifted: "\"", key: "'", code: "Quote"),
            MacKey(id: "return", label: "return", width: 2.25, action: .key(name: "Enter", code: "Enter"), accessibilityLabel: "Return")
        ]
    }

    private var shiftRow: [MacKey] {
        [
            MacKey(id: "leftShift", label: "⇧", width: 2.25, action: .modifier(.shift), accessibilityLabel: "Left Shift")
        ] + letterKeys("ZXCVBNM") + [
            textKey("comma", label: ",", shifted: "<", key: ",", code: "Comma"),
            textKey("period", label: ".", shifted: ">", key: ".", code: "Period"),
            textKey("slash", label: "/", shifted: "?", key: "/", code: "Slash"),
            MacKey(id: "rightShift", label: "⇧", width: 2.75, action: .modifier(.shift), accessibilityLabel: "Right Shift")
        ]
    }

    private var bottomRow: [MacKey] {
        [
            MacKey(id: "fn", label: "fn", width: 1, accessibilityLabel: "Function"),
            MacKey(id: "leftControl", label: "⌃", width: 1, action: .modifier(.control), accessibilityLabel: "Left Control"),
            MacKey(id: "leftOption", label: "⌥", width: 1.25, action: .modifier(.option), accessibilityLabel: "Left Option"),
            MacKey(id: "leftCommand", label: "⌘", width: 1.25, action: .modifier(.command), accessibilityLabel: "Left Command"),
            textKey("space", label: "", key: " ", code: "Space", width: 5, accessibilityLabel: "Space"),
            MacKey(id: "rightCommand", label: "⌘", width: 1.25, action: .modifier(.command), accessibilityLabel: "Right Command"),
            MacKey(id: "rightOption", label: "⌥", width: 1, action: .modifier(.option), accessibilityLabel: "Right Option"),
            MacKey(id: "arrows", width: 3.25, kind: .arrowCluster)
        ]
    }

    private func letterKeys(_ letters: String) -> [MacKey] {
        letters.map { character in
            let lower = String(character).lowercased()
            let upper = String(character).uppercased()
            let code = "Key" + upper
            return MacKey(
                id: "letter.\(lower)",
                label: upper,
                action: .text(text: lower, shifted: upper, key: lower, code: code, capsSensitive: true),
                accessibilityLabel: upper
            )
        }
    }

    private func textKey(
        _ id: String,
        label: String,
        shifted: String? = nil,
        key: String,
        code: String,
        width: CGFloat = 1,
        accessibilityLabel: String? = nil
    ) -> MacKey {
        MacKey(
            id: id,
            label: label,
            sublabel: shifted,
            width: width,
            action: .text(text: key, shifted: shifted, key: key, code: code, capsSensitive: false),
            accessibilityLabel: accessibilityLabel ?? (label.isEmpty ? key : label)
        )
    }
}

private struct MacKeycap: View {
    let key: MacKey
    let width: CGFloat
    let height: CGFloat
    let active: Bool
    let hapticsEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if hapticsEnabled {
                Haptics.shared.keyPress()
            }
            action()
        } label: {
            keyContent
        }
        .buttonStyle(MacKeyButtonStyle(active: active, isFunction: key.kind == .function))
        .frame(width: width, height: height)
        .accessibilityLabel(key.accessibilityLabel ?? key.label)
        .accessibilityValue(active ? "on" : "off")
    }

    @ViewBuilder
    private var keyContent: some View {
        if let systemImage = key.systemImage {
            VStack(spacing: key.kind == .function ? 1 : 2) {
                Image(systemName: systemImage)
                    .font(.system(size: key.kind == .function ? 12 : 17, weight: .medium))
                if !key.label.isEmpty {
                    Text(key.label)
                        .font(.system(size: key.kind == .function ? 7.5 : 8, weight: .semibold, design: .monospaced))
                        .opacity(0.62)
                }
            }
        } else {
            Text(key.label)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var font: Font {
        switch key.id {
        case "delete", "return", "tab", "caps":
            return .system(size: 9, weight: .semibold, design: .rounded)
        case "leftShift", "rightShift", "leftControl", "leftOption", "leftCommand", "rightCommand", "rightOption", "fn", "esc":
            return .system(size: key.id == "fn" || key.id == "esc" ? 10 : 15, weight: .semibold, design: .rounded)
        default:
            return .system(size: 15, weight: .medium, design: .rounded)
        }
    }
}

private struct MacKeyButtonStyle: ButtonStyle {
    let active: Bool
    let isFunction: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: isFunction ? 5 : 6, style: .continuous)
        configuration.label
            .foregroundStyle(active ? Color(hex: 0x04131A) : Color.white.opacity(0.90))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    shape
                        .fill(Color.black.opacity(0.70))
                        .offset(y: pressed ? 0 : 2)
                    shape
                        .fill(fill(pressed: pressed))
                        .offset(y: pressed ? 2 : 0)
                    shape
                        .strokeBorder(
                            active ? ADTheme.accent.opacity(0.85) : Color.white.opacity(0.10),
                            lineWidth: 0.7
                        )
                        .offset(y: pressed ? 2 : 0)
                }
            }
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private func fill(pressed: Bool) -> LinearGradient {
        if active {
            return LinearGradient(
                colors: [ADTheme.accent, ADTheme.accentDeep],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if pressed {
            return LinearGradient(
                colors: [Color(hex: 0x0B0B0C), Color(hex: 0x050506)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: isFunction
                ? [Color(hex: 0x252528), Color(hex: 0x121214)]
                : [Color(hex: 0x333336), Color(hex: 0x161618)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct MacArrowCluster: View {
    let width: CGFloat
    let height: CGFloat
    let hapticsEnabled: Bool
    let onKey: (String, String?, Set<InputModifier>) -> Void

    var body: some View {
        HStack(spacing: 3) {
            arrow("arrow.left", key: "ArrowLeft", code: "ArrowLeft")
            VStack(spacing: 3) {
                arrow("arrow.up", key: "ArrowUp", code: "ArrowUp")
                    .frame(height: (height - 3) / 2)
                arrow("arrow.down", key: "ArrowDown", code: "ArrowDown")
                    .frame(height: (height - 3) / 2)
            }
            arrow("arrow.right", key: "ArrowRight", code: "ArrowRight")
        }
        .frame(width: width, height: height)
    }

    private func arrow(_ icon: String, key: String, code: String) -> some View {
        Button {
            if hapticsEnabled {
                Haptics.shared.keyPress()
            }
            onKey(key, code, [])
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(MacKeyButtonStyle(active: false, isFunction: false))
        .accessibilityLabel(key)
    }
}
