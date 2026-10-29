import SwiftUI
import UIKit

struct KeyboardBar: View {
    let onDone: () -> Void
    let onInsert: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void

    @EnvironmentObject private var session: SessionCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ADTheme.accent)
                        .frame(width: 5, height: 5)
                        .opacity(pulse ? 0.3 : 1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    Text("KEYBOARD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.9)
                        .foregroundStyle(ADTheme.textSecondary)
                }
                Text("→ \(session.runtimeName)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(ADTheme.textTertiary)
                Spacer()
                Button {
                    Haptics.shared.tap()
                    onDone()
                } label: {
                    Text("DONE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color(hex: 0x04131A))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background { Capsule().fill(ADTheme.accentGradient()) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    keyButton("Esc", label: "Escape") { session.sendKey("Escape", code: "Escape") }
                    keyButton("⇥", label: "Tab") { session.sendKey("Tab", code: "Tab") }
                    keyButton("↩", label: "Return", action: onReturn)
                    keyButton("⌫", label: "Backspace", action: onBackspace)
                    keyButton("←", label: "Left arrow") { session.sendKey("ArrowLeft", code: "ArrowLeft") }
                    keyButton("↑", label: "Up arrow") { session.sendKey("ArrowUp", code: "ArrowUp") }
                    keyButton("↓", label: "Down arrow") { session.sendKey("ArrowDown", code: "ArrowDown") }
                    keyButton("→", label: "Right arrow") { session.sendKey("ArrowRight", code: "ArrowRight") }

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 0.8, height: 22)
                        .padding(.horizontal, 2)

                    ForEach(InputModifier.allCases) { modifier in
                        ModifierChip(
                            symbol: modifier.symbol,
                            isOn: session.modifiers.contains(modifier),
                            action: { session.toggleModifier(modifier) }
                        )
                    }

                    if !session.modifiers.isEmpty {
                        Button {
                            session.clearModifiers()
                        } label: {
                            Text("CLEAR")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundStyle(ADTheme.textTertiary)
                                .padding(.horizontal, 8)
                                .frame(height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            KeyCaptureField(
                active: true,
                onText: { text in
                    onInsert(text)
                    if settings.hapticsEnabled { Haptics.shared.tap() }
                },
                onBackspace: onBackspace,
                onReturn: onReturn
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.35), radius: 20, y: -6)
        }
        .onAppear { pulse = true }
    }

    private func keyButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.8))
                .frame(minWidth: 42, minHeight: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
                        }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct KeyCaptureField: UIViewRepresentable {
    var active: Bool
    var onText: (String) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onText: onText, onBackspace: onBackspace, onReturn: onReturn)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = FocusingTextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        field.wantsFocus = active
        field.delegate = context.coordinator
        field.text = ""
        field.tintColor = .clear
        field.textColor = .clear
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.keyboardAppearance = .dark
        field.returnKeyType = .default
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.onText = onText
        context.coordinator.onBackspace = onBackspace
        context.coordinator.onReturn = onReturn
        (uiView as? FocusingTextField)?.wantsFocus = active

        if active {
            focus(uiView)
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private func focus(_ uiView: UITextField) {
        if uiView.window != nil {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
            return
        }
        DispatchQueue.main.async { [weak uiView] in
            guard let uiView, uiView.window != nil, !uiView.isFirstResponder else { return }
            uiView.becomeFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
        (uiView as? FocusingTextField)?.wantsFocus = false
        uiView.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onText: (String) -> Void
        var onBackspace: () -> Void
        var onReturn: () -> Void

        init(onText: @escaping (String) -> Void, onBackspace: @escaping () -> Void, onReturn: @escaping () -> Void) {
            self.onText = onText
            self.onBackspace = onBackspace
            self.onReturn = onReturn
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                for _ in 0..<max(range.length, 1) {
                    onBackspace()
                }
            } else {
                if range.length > 0 {
                    for _ in 0..<min(range.length, 64) {
                        onBackspace()
                    }
                }
                onText(string)
            }
            textField.text = ""
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onReturn()
            return false
        }
    }
}

private final class FocusingTextField: UITextField {
    var wantsFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard wantsFocus, window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsFocus, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }
}
