import SwiftUI
import UIKit

struct PreviewKeyboardCapture: UIViewRepresentable {
    let isActive: Bool
    let focusRequest: Int
    let onText: (String) -> Void
    let onBackspace: () -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.keyboardAppearance = .dark
        field.returnKeyType = .default
        field.textContentType = .none
        field.backgroundColor = .clear
        field.textColor = .clear
        field.tintColor = .clear
        field.isAccessibilityElement = false
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        let focusChanged = context.coordinator.focusRequest != focusRequest
        context.coordinator.focusRequest = focusRequest

        DispatchQueue.main.async {
            guard isActive else {
                if uiView.isFirstResponder {
                    print("[AirDeskDebug] keyboard field resign")
                    uiView.resignFirstResponder()
                }
                return
            }

            if focusChanged || !uiView.isFirstResponder {
                print("[AirDeskDebug] keyboard field focus changed=\(focusChanged)")
                if uiView.isFirstResponder {
                    uiView.resignFirstResponder()
                }
                let focused = uiView.becomeFirstResponder()
                print("[AirDeskDebug] keyboard field becomeFirstResponder=\(focused)")
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PreviewKeyboardCapture
        var focusRequest = -1

        init(_ parent: PreviewKeyboardCapture) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            print("[AirDeskDebug] keyboard input \(string.debugDescription)")
            if string.isEmpty {
                parent.onBackspace()
            } else {
                parent.onText(string)
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            print("[AirDeskDebug] keyboard return")
            parent.onReturn()
            return false
        }
    }
}
