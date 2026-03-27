import SwiftUI
import AppKit

struct TemplateTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var activeEnvironment: AppEnvironment?
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = font
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        if activeEnvironment != nil {
            let attributed = buildAttributedString(from: text)
            textField.attributedStringValue = attributed
        } else {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func buildAttributedString(from text: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.textColor
        ])

        let variables = TemplateEngine.findVariables(in: text)
        let envVars = activeEnvironment?.variables ?? [:]

        for variable in variables {
            let nsRange = NSRange(variable.range, in: text)
            let isResolved = envVars[variable.name] != nil
            let bgColor: NSColor = isResolved ? .systemBlue.withAlphaComponent(0.2) : .systemRed.withAlphaComponent(0.2)
            let fgColor: NSColor = isResolved ? .systemBlue : .systemRed

            result.addAttributes([
                .backgroundColor: bgColor,
                .foregroundColor: fgColor,
                .toolTip: isResolved ? (envVars[variable.name] ?? "") : "Undefined variable"
            ], range: nsRange)
        }

        return result
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TemplateTextField
        var isUpdating = false

        init(_ parent: TemplateTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdating, let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}
