import SwiftUI
import AppKit

struct GraphQLTextEditor: NSViewRepresentable {
    @Binding var text: String

    private static let editorFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let tabReplacement = "  " // 2 spaces

    func makeNSView(context: Context) -> NSView {
        // Use factory for proper scroll view setup, then swap in our subclass
        let scrollView = NSTextView.scrollableTextView()
        guard let factoryTextView = scrollView.documentView as? NSTextView else { return scrollView }

        let textView = GraphQLNSTextView(frame: factoryTextView.frame)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 8
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.font = Self.editorFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        scrollView.documentView = textView

        // Selection change observer for current-line highlight redraw
        let selectionToken = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { _ in
            textView.needsDisplay = true
        }
        context.coordinator.observerTokens.append(selectionToken)

        // Line number gutter — plain NSView beside the scroll view (CotEditor pattern)
        let lineNumberView = LineNumberView()
        lineNumberView.textView = textView
        lineNumberView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        lineNumberView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let stackView = NSStackView(views: [lineNumberView, scrollView])
        stackView.spacing = 0
        stackView.orientation = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .top

        // Start observing after views are in hierarchy
        lineNumberView.startObserving()

        // Set initial text
        textView.string = text

        return stackView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let stackView = nsView as? NSStackView,
              let scrollView = stackView.arrangedSubviews.last as? NSScrollView,
              let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        guard textView.string != text else { return }

        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        let savedRanges = textView.selectedRanges
        let newLength = (text as NSString).length

        textView.undoManager?.disableUndoRegistration()
        textView.string = text
        textView.undoManager?.enableUndoRegistration()

        // Clamp saved selection ranges to new text length
        let clampedRanges = savedRanges.map { rangeValue -> NSValue in
            let range = rangeValue.rangeValue
            let clampedLocation = min(range.location, newLength)
            let clampedLength = min(range.length, newLength - clampedLocation)
            return NSValue(range: NSRange(location: clampedLocation, length: clampedLength))
        }
        if !clampedRanges.isEmpty {
            textView.selectedRanges = clampedRanges
        }

        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GraphQLTextEditor
        var isUpdating = false
        var isHandlingKeyEvent = false
        var observerTokens: [Any] = []

        init(_ parent: GraphQLTextEditor) {
            self.parent = parent
        }

        deinit {
            observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacement = replacementString else { return true }
            guard !isHandlingKeyEvent else { return true }

            // Tab key → insert 2 spaces
            if replacement == "\t" {
                handleTab(textView: textView, affectedRange: affectedCharRange)
                return false
            }

            // Return key → auto-indent
            if replacement == "\n" {
                handleReturn(textView: textView, affectedRange: affectedCharRange)
                return false
            }

            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Shift+Tab (backtab) → block dedent
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                handleBackTab(textView: textView)
                return true
            }
            return false
        }

        // MARK: - Tab Handling

        private func handleTab(textView: NSTextView, affectedRange: NSRange) {
            isHandlingKeyEvent = true
            defer { isHandlingKeyEvent = false }

            let selectedRange = textView.selectedRange()
            let string = textView.string as NSString

            // Multi-line selection → block indent
            if selectedRange.length > 0 {
                let lineRange = string.lineRange(for: selectedRange)
                var offset = 0
                var index = lineRange.location

                textView.undoManager?.beginUndoGrouping()
                while index < NSMaxRange(lineRange) {
                    let insertRange = NSRange(location: index + offset, length: 0)
                    textView.insertText(GraphQLTextEditor.tabReplacement, replacementRange: insertRange)
                    offset += GraphQLTextEditor.tabReplacement.count
                    let currentLineRange = (textView.string as NSString).lineRange(for: NSRange(location: index + offset, length: 0))
                    index = NSMaxRange(currentLineRange) - offset + (index == lineRange.location ? 0 : 0)

                    // Advance to next line
                    let nextLineStart = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
                    if nextLineStart == index { break }
                    index = nextLineStart
                }
                textView.undoManager?.endUndoGrouping()
            } else {
                // Single cursor → insert 2 spaces
                textView.insertText(GraphQLTextEditor.tabReplacement, replacementRange: affectedRange)
            }
        }

        private func handleBackTab(textView: NSTextView) {
            isHandlingKeyEvent = true
            defer { isHandlingKeyEvent = false }

            let selectedRange = textView.selectedRange()
            let string = textView.string as NSString
            let lineRange = string.lineRange(for: selectedRange)
            let tabSize = GraphQLTextEditor.tabReplacement.count

            textView.undoManager?.beginUndoGrouping()
            var index = lineRange.location
            var totalRemoved = 0

            while index < NSMaxRange(lineRange) - totalRemoved {
                let adjustedString = textView.string as NSString
                let currentLineRange = adjustedString.lineRange(for: NSRange(location: index, length: 0))
                let lineText = adjustedString.substring(with: currentLineRange)

                let leadingSpaces = lineText.prefix(while: { $0 == " " }).count
                let toRemove = min(leadingSpaces, tabSize)

                if toRemove > 0 {
                    let removeRange = NSRange(location: currentLineRange.location, length: toRemove)
                    textView.insertText("", replacementRange: removeRange)
                    totalRemoved += toRemove
                }

                let nextStart = NSMaxRange(adjustedString.lineRange(for: NSRange(location: index, length: 0)))
                if nextStart <= index { break }
                index = NSMaxRange((textView.string as NSString).lineRange(for: NSRange(location: currentLineRange.location, length: 0)))
                if index <= currentLineRange.location { break }
            }
            textView.undoManager?.endUndoGrouping()
        }

        // MARK: - Auto-Indent

        private func handleReturn(textView: NSTextView, affectedRange: NSRange) {
            let string = textView.string as NSString
            let cursorPosition = affectedRange.location
            let lineRange = string.lineRange(for: NSRange(location: cursorPosition, length: 0))
            let textBeforeCursor = string.substring(
                with: NSRange(location: lineRange.location, length: cursorPosition - lineRange.location)
            )

            let baseIndent = String(textBeforeCursor.prefix(while: { $0 == " " }))
            let lastNonWS = textBeforeCursor.last(where: { !$0.isWhitespace })

            let newIndent: String
            if lastNonWS == "{" {
                newIndent = baseIndent + GraphQLTextEditor.tabReplacement
            } else if lastNonWS == "}" {
                let reduced = max(0, baseIndent.count - GraphQLTextEditor.tabReplacement.count)
                newIndent = String(repeating: " ", count: reduced)
            } else {
                newIndent = baseIndent
            }

            let insertion = "\n" + newIndent
            isHandlingKeyEvent = true
            defer { isHandlingKeyEvent = false }
            textView.insertText(insertion, replacementRange: affectedRange)
        }
    }
}
