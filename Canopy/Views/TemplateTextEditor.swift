import SwiftUI
import AppKit

struct TemplateTextEditor: NSViewRepresentable {
    @Binding var text: String
    var environmentVariables: [String: String] = [:]
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        let currentText = textView.string
        if currentText != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        applyBadgeHighlighting(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyBadgeHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Reset to default styling
        textStorage.addAttributes([
            .font: font,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: NSColor.clear
        ], range: fullRange)

        guard !environmentVariables.isEmpty else { return }

        let text = textView.string
        let variables = TemplateEngine.findVariables(in: text)

        for variable in variables {
            let nsRange = NSRange(variable.range, in: text)
            let isResolved = environmentVariables[variable.name] != nil
            let bgColor: NSColor = isResolved ? .systemBlue.withAlphaComponent(0.2) : .systemRed.withAlphaComponent(0.2)
            let fgColor: NSColor = isResolved ? .systemBlue : .systemRed

            textStorage.addAttributes([
                .backgroundColor: bgColor,
                .foregroundColor: fgColor,
                .toolTip: isResolved ? (environmentVariables[variable.name] ?? "") : "Undefined variable"
            ], range: nsRange)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TemplateTextEditor
        var isUpdating = false

        init(_ parent: TemplateTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
