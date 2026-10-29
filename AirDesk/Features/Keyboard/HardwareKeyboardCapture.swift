import SwiftUI
import UIKit

struct HardwareKeyboardCapture: UIViewRepresentable {
    let isActive: Bool
    let onText: (String) -> Void
    let onKey: (String, String?, Set<InputModifier>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onText: onText, onKey: onKey)
    }

    func makeUIView(context: Context) -> HardwareKeyField {
        let field = HardwareKeyField(frame: .zero)
        field.delegate = context.coordinator
        field.wantsFocus = isActive
        field.onKey = context.coordinator.onKey
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
        field.textContentType = .none
        field.keyboardAppearance = .dark
        field.returnKeyType = .default
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.inputView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        field.inputAccessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        return field
    }

    func updateUIView(_ uiView: HardwareKeyField, context: Context) {
        context.coordinator.onText = onText
        context.coordinator.onKey = onKey
        uiView.onKey = context.coordinator.onKey
        uiView.wantsFocus = isActive
        if isActive {
            uiView.focusIfNeeded()
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: HardwareKeyField, coordinator: Coordinator) {
        uiView.wantsFocus = false
        uiView.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onText: (String) -> Void
        var onKey: (String, String?, Set<InputModifier>) -> Void

        init(
            onText: @escaping (String) -> Void,
            onKey: @escaping (String, String?, Set<InputModifier>) -> Void
        ) {
            self.onText = onText
            self.onKey = onKey
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                for _ in 0..<max(range.length, 1) {
                    onKey("Backspace", "Backspace", [])
                }
            } else {
                if range.length > 0 {
                    for _ in 0..<min(range.length, 64) {
                        onKey("Backspace", "Backspace", [])
                    }
                }
                onText(string)
            }
            textField.text = ""
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onKey("Enter", "Enter", [])
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard let field = textField as? HardwareKeyField, field.wantsFocus else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                field.focusIfNeeded()
            }
        }
    }
}

final class HardwareKeyField: UITextField {
    var wantsFocus = false
    var onKey: ((String, String?, Set<InputModifier>) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        focusIfNeeded()
    }

    func focusIfNeeded() {
        guard wantsFocus, window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsFocus, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            let modifiers = Self.modifiers(from: key.modifierFlags)
            if let mapped = Self.specialKey(for: key.keyCode) {
                onKey?(mapped.key, mapped.code, modifiers)
                handled = true
                continue
            }
            if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
                let characters = key.charactersIgnoringModifiers
                guard !characters.isEmpty else { continue }
                onKey?(characters.lowercased(), nil, modifiers)
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    private static func modifiers(from flags: UIKeyModifierFlags) -> Set<InputModifier> {
        var modifiers = Set<InputModifier>()
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    private static func specialKey(for code: UIKeyboardHIDUsage) -> (key: String, code: String)? {
        switch code {
        case .keyboardEscape: return ("Escape", "Escape")
        case .keyboardTab: return ("Tab", "Tab")
        case .keyboardDeleteForward: return ("Delete", "Delete")
        case .keyboardLeftArrow: return ("ArrowLeft", "ArrowLeft")
        case .keyboardRightArrow: return ("ArrowRight", "ArrowRight")
        case .keyboardUpArrow: return ("ArrowUp", "ArrowUp")
        case .keyboardDownArrow: return ("ArrowDown", "ArrowDown")
        case .keyboardHome: return ("Home", "Home")
        case .keyboardEnd: return ("End", "End")
        case .keyboardPageUp: return ("PageUp", "PageUp")
        case .keyboardPageDown: return ("PageDown", "PageDown")
        case .keyboardInsert: return ("Insert", "Insert")
        default: return nil
        }
    }
}
