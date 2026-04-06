import SwiftUI
import AppKit
import GraphQL

struct GraphQLTextEditor: NSViewRepresentable {
    @Binding var text: String
    var schema: GraphQLSchema?

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

        // Wire up Ctrl+Space trigger
        textView.completionTrigger = { [weak coordinator = context.coordinator] in
            coordinator?.triggerCompletion(textView: textView, manual: true)
        }

        // Wire up error hover support
        textView.errorProvider = { [weak coordinator = context.coordinator] in
            coordinator?.currentErrors ?? []
        }
        textView.isCompletionVisible = { [weak coordinator = context.coordinator] in
            coordinator?.completionPanel?.isVisible ?? false
        }

        // Selection change observer for current-line highlight redraw
        let selectionToken = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            textView.needsDisplay = true
            // Dismiss completion on cursor movement (unless we're accepting a completion)
            coordinator?.handleSelectionChange(textView: textView)
        }
        context.coordinator.observerTokens.append(selectionToken)

        // Dismiss completion and error tooltip on scroll
        if let clipView = scrollView.contentView as? NSClipView {
            let scrollToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak coordinator = context.coordinator, weak textView] _ in
                coordinator?.completionPanel?.dismiss()
                (textView as? GraphQLNSTextView)?.dismissErrorPopoverOnScroll()
            }
            context.coordinator.observerTokens.append(scrollToken)
        }

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

        // Set initial text and apply syntax highlighting
        textView.string = text
        GraphQLSyntaxHighlighter.highlight(textView)
        context.coordinator.runValidation(textView: textView)

        return stackView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let stackView = nsView as? NSStackView,
              let scrollView = stackView.arrangedSubviews.last as? NSScrollView,
              let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        // Detect schema changes — re-validate even if text is the same
        let currentEndpoint = schema.map { _ in
            // Use the schema's query type name as a lightweight identity
            schema?.queryTypeName ?? ""
        }
        let schemaChanged = currentEndpoint != context.coordinator.lastSchemaEndpoint
        if schemaChanged {
            context.coordinator.lastSchemaEndpoint = currentEndpoint
        }

        let textChanged = textView.string != text

        guard textChanged || schemaChanged else { return }

        if textChanged {
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

            GraphQLSyntaxHighlighter.highlight(textView)
        }

        // Clear and re-run validation on text or schema change
        GraphQLSyntaxHighlighter.clearErrors(textView)
        context.coordinator.runValidation(textView: textView)
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
        var isAcceptingCompletion = false
        var observerTokens: [Any] = []

        // Completion state
        var completionPanel: CompletionPanel?
        private var completionDebouncer: DispatchWorkItem?
        private var lastInsertionWasSingleChar = false
        private var lastCursorPosition: Int = 0

        // Validation state
        private var validationDebouncer: DispatchWorkItem?
        var currentErrors: [QueryValidator.ValidationError] = []
        var lastSchemaEndpoint: String?

        init(_ parent: GraphQLTextEditor) {
            self.parent = parent
        }

        deinit {
            observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
            completionPanel?.dismiss()
            completionDebouncer?.cancel()
            validationDebouncer?.cancel()
        }

        // MARK: - Text Change

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            GraphQLSyntaxHighlighter.highlight(textView)

            // Clear error underlines immediately, re-validate after debounce
            GraphQLSyntaxHighlighter.clearErrors(textView)
            scheduleValidation(textView: textView)

            guard lastInsertionWasSingleChar, parent.schema != nil else {
                // Paste or programmatic change — dismiss panel
                completionPanel?.dismiss()
                return
            }

            let cursorOffset = textView.selectedRange().location
            let prefix = CompletionEngine.extractPrefix(text: textView.string, cursorOffset: cursorOffset)

            if let panel = completionPanel, panel.isVisible {
                // Panel already showing — re-filter with new prefix
                if prefix.isEmpty {
                    panel.dismiss()
                } else {
                    scheduleCompletion(textView: textView)
                }
            } else if prefix.count >= 1 {
                // Panel not showing — only auto-trigger after typing at least 1 character
                scheduleCompletion(textView: textView)
            }
        }

        // MARK: - Key Interception

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacement = replacementString else { return true }
            guard !isHandlingKeyEvent else { return true }

            // Track whether this is a single-character insertion (typing, not paste)
            lastInsertionWasSingleChar = (replacement.count == 1)

            // When completion panel is visible, intercept Tab and Enter
            if let panel = completionPanel, panel.isVisible {
                if replacement == "\t" {
                    acceptCompletion(textView: textView)
                    return false
                }
                if replacement == "\n" {
                    acceptCompletion(textView: textView)
                    return false
                }
            }

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

            // Auto-close braces and parens
            if (replacement == "{" || replacement == "(") && !isAcceptingCompletion {
                if !CompletionEngine.isInsideCommentOrString(text: textView.string, cursorOffset: affectedCharRange.location) {
                    handleAutoClose(textView: textView, opening: replacement, affectedRange: affectedCharRange)
                    return false
                }
            }

            // Closing characters: skip-over and auto-dedent (only with no selection)
            if (replacement == "}" || replacement == ")") && affectedCharRange.length == 0 {
                if !CompletionEngine.isInsideCommentOrString(text: textView.string, cursorOffset: affectedCharRange.location) {
                    let string = textView.string as NSString

                    // Skip-over: if next char matches, just move cursor past it
                    if affectedCharRange.location < string.length {
                        let nextChar = Character(UnicodeScalar(string.character(at: affectedCharRange.location))!)
                        if String(nextChar) == replacement {
                            completionPanel?.dismiss()
                            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                            return false
                        }
                    }

                    // Auto-dedent: } on whitespace-only line
                    if replacement == "}" {
                        let lineRange = string.lineRange(for: NSRange(location: affectedCharRange.location, length: 0))
                        let textBeforeCursor = string.substring(
                            with: NSRange(location: lineRange.location, length: affectedCharRange.location - lineRange.location)
                        )
                        if !textBeforeCursor.isEmpty && textBeforeCursor.allSatisfy({ $0 == " " }) {
                            handleAutoDedent(textView: textView, affectedRange: affectedCharRange, lineStart: lineRange.location, currentIndent: textBeforeCursor)
                            return false
                        }
                    }
                }
            }

            // Dismiss panel on non-identifier characters when panel is visible
            if let panel = completionPanel, panel.isVisible {
                let isIdentifierChar = replacement.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
                if !isIdentifierChar {
                    panel.dismiss()
                }
            }

            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // When completion panel is visible
            if let panel = completionPanel, panel.isVisible {
                // Esc → dismiss
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    panel.dismiss()
                    return true
                }
                // Up arrow → move selection up
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    panel.moveSelectionUp()
                    return true
                }
                // Down arrow → move selection down
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    panel.moveSelectionDown()
                    return true
                }
            } else {
                // Panel not visible — Esc triggers manual completion
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    triggerCompletion(textView: textView, manual: true)
                    return true
                }
            }

            // Shift+Tab (backtab) → block dedent
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                handleBackTab(textView: textView)
                return true
            }

            // Backspace → pair-delete
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if handlePairDelete(textView: textView) {
                    return true
                }
            }

            return false
        }

        // MARK: - Selection Change

        func handleSelectionChange(textView: NSTextView) {
            guard !isAcceptingCompletion, !isHandlingKeyEvent else { return }

            let newPos = textView.selectedRange().location
            defer { lastCursorPosition = newPos }

            guard let panel = completionPanel, panel.isVisible else { return }

            // If cursor jumped (click, arrow keys outside typing flow) — dismiss
            let moved = abs(newPos - lastCursorPosition)
            if moved > 1 {
                panel.dismiss()
                return
            }

            // Cursor moved by 0-1 (normal typing) — re-filter
            let prefix = CompletionEngine.extractPrefix(text: textView.string, cursorOffset: newPos)
            if prefix.isEmpty {
                panel.dismiss()
            }
        }

        // MARK: - Completion Trigger

        func triggerCompletion(textView: NSTextView, manual: Bool = false) {
            completionDebouncer?.cancel()

            guard let schema = parent.schema else { return }

            let cursorOffset = textView.selectedRange().location
            let text = textView.string
            lastCursorPosition = cursorOffset

            // Don't auto-show when there's no prefix (unless manual trigger)
            if !manual {
                let prefix = CompletionEngine.extractPrefix(text: text, cursorOffset: cursorOffset)
                if prefix.isEmpty {
                    completionPanel?.dismiss()
                    return
                }
            }

            let items = CompletionEngine.completions(
                text: text,
                cursorOffset: cursorOffset,
                schema: schema
            )

            guard !items.isEmpty else {
                completionPanel?.dismiss()
                return
            }

            // Get cursor screen position
            guard let screenPoint = cursorScreenPoint(textView: textView) else { return }
            guard let window = textView.window else { return }

            if let panel = completionPanel, panel.isVisible {
                panel.updateItems(items)
            } else {
                let panel = completionPanel ?? CompletionPanel()
                self.completionPanel = panel
                panel.show(items: items, at: screenPoint, parentWindow: window)
            }
        }

        private func scheduleCompletion(textView: NSTextView) {
            completionDebouncer?.cancel()

            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.triggerCompletion(textView: textView)
            }
            completionDebouncer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
        }

        // MARK: - Validation

        private func scheduleValidation(textView: NSTextView) {
            validationDebouncer?.cancel()

            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.runValidation(textView: textView)
            }
            validationDebouncer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
        }

        func runValidation(textView: NSTextView) {
            guard let schema = parent.schema else {
                currentErrors = []
                return
            }

            let source = textView.string
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                currentErrors = []
                return
            }

            // Size guard — skip validation for very large queries
            guard (source as NSString).length <= 50_000 else {
                currentErrors = []
                return
            }

            guard let document = try? GraphQL.parse(source: source) else {
                // Parse failed — syntax error. Clear errors (already cleared on keystroke).
                currentErrors = []
                return
            }

            let errors = QueryValidator.validate(document: document, schema: schema, source: source)
            currentErrors = errors
            GraphQLSyntaxHighlighter.applyErrors(errors, to: textView)
        }

        // MARK: - Completion Acceptance

        private func acceptCompletion(textView: NSTextView) {
            guard let panel = completionPanel, let item = panel.selectedItem() else { return }

            isAcceptingCompletion = true
            lastInsertionWasSingleChar = false
            completionDebouncer?.cancel()
            defer { isAcceptingCompletion = false }

            let cursorOffset = textView.selectedRange().location
            let prefix = CompletionEngine.extractPrefix(text: textView.string, cursorOffset: cursorOffset)
            let replaceRange = NSRange(location: cursorOffset - prefix.count, length: prefix.count)

            // Determine if we need to auto-insert { } for object-type fields
            var fullInsertText = item.insertText
            var cursorInsideBraces = false

            if item.kind == .field, let schema = parent.schema {
                let text = textView.string
                let context = CompletionEngine.resolveContext(
                    text: text,
                    cursorOffset: cursorOffset,
                    schema: schema
                )

                if case .field(let parentType) = context {
                    // Check if the accepted field returns an object type needing sub-selection
                    if let field = parentType.fields?.first(where: { $0.name == item.insertText }) {
                        let returnTypeName = field.type.toTypeRef().namedType
                        if let returnType = schema.type(named: returnTypeName),
                           returnType.kind == .object || returnType.kind == .interface || returnType.kind == .union {
                            fullInsertText = "\(item.insertText) { }"
                            cursorInsideBraces = true
                        }
                    }
                }
            }

            isHandlingKeyEvent = true
            textView.undoManager?.beginUndoGrouping()
            textView.insertText(fullInsertText, replacementRange: replaceRange)
            textView.undoManager?.endUndoGrouping()
            isHandlingKeyEvent = false

            // Place cursor inside braces if we auto-inserted them
            if cursorInsideBraces {
                let newCursorPos = replaceRange.location + fullInsertText.count - 2 // before " }"
                textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))

                // Auto-trigger completion inside the new braces after a short delay
                scheduleCompletion(textView: textView)
            }

            panel.dismiss()
        }

        // MARK: - Helpers

        private func cursorScreenPoint(textView: NSTextView) -> NSPoint? {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return nil }

            let cursorOffset = textView.selectedRange().location
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(cursorOffset, max(0, (textView.string as NSString).length - 1)))
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            // Position below the current line
            var point = NSPoint(x: lineRect.origin.x + textContainer.lineFragmentPadding,
                               y: lineRect.maxY + textView.textContainerOrigin.y)

            // Convert to window coordinates, then to screen
            point = textView.convert(point, to: nil)
            guard let window = textView.window else { return nil }
            let screenPoint = window.convertPoint(toScreen: point)
            return screenPoint
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

            // Split-brace/paren expansion: cursor between matched pair on the same line
            if let charBefore = lastNonWS, charBefore == "{" || charBefore == "(" {
                let expectedClosing: Character = charBefore == "{" ? "}" : ")"

                // Scan forward past whitespace (but not newline) to find closing char
                var closingOffset = cursorPosition
                while closingOffset < string.length {
                    let ch = Character(UnicodeScalar(string.character(at: closingOffset))!)
                    if ch == " " || ch == "\t" {
                        closingOffset += 1
                    } else {
                        break
                    }
                }

                if closingOffset < string.length {
                    let closingChar = Character(UnicodeScalar(string.character(at: closingOffset))!)
                    if closingChar == expectedClosing {
                        let innerIndent = baseIndent + GraphQLTextEditor.tabReplacement
                        let insertion = "\n" + innerIndent + "\n" + baseIndent
                        let replaceRange = NSRange(location: cursorPosition, length: closingOffset - cursorPosition)

                        isHandlingKeyEvent = true
                        defer { isHandlingKeyEvent = false }
                        textView.undoManager?.beginUndoGrouping()
                        textView.insertText(insertion, replacementRange: replaceRange)
                        textView.undoManager?.endUndoGrouping()

                        let newCursorPos = cursorPosition + 1 + innerIndent.count
                        textView.setSelectedRange(NSRange(location: newCursorPos, length: 0))
                        return
                    }
                }
            }

            // Regular return handling
            let newIndent: String
            if lastNonWS == "{" || lastNonWS == "(" {
                newIndent = baseIndent + GraphQLTextEditor.tabReplacement
            } else if lastNonWS == "}" {
                newIndent = baseIndent
            } else {
                newIndent = baseIndent
            }

            let insertion = "\n" + newIndent
            isHandlingKeyEvent = true
            defer { isHandlingKeyEvent = false }
            textView.insertText(insertion, replacementRange: affectedRange)
        }

        // MARK: - Auto-Close

        private func handleAutoClose(textView: NSTextView, opening: String, affectedRange: NSRange) {
            let closing = opening == "{" ? "}" : ")"

            lastInsertionWasSingleChar = false
            isHandlingKeyEvent = true
            defer { isHandlingKeyEvent = false }

            if affectedRange.length > 0 {
                // Selection wrapping: {selection} or (selection)
                let string = textView.string as NSString
                let selectedText = string.substring(with: affectedRange)
                let wrapped = opening + selectedText + closing
                textView.insertText(wrapped, replacementRange: affectedRange)
                let newPos = affectedRange.location + wrapped.count
                textView.setSelectedRange(NSRange(location: newPos, length: 0))
            } else {
                // No selection: insert pair with cursor between
                let pair = opening + closing
                textView.insertText(pair, replacementRange: affectedRange)
                let newPos = affectedRange.location + 1
                textView.setSelectedRange(NSRange(location: newPos, length: 0))
            }
        }

        // MARK: - Auto-Dedent

        private func handleAutoDedent(textView: NSTextView, affectedRange: NSRange, lineStart: Int, currentIndent: String) {
            let tabSize = GraphQLTextEditor.tabReplacement.count
            let reducedCount = max(0, currentIndent.count - tabSize)
            let newIndent = String(repeating: " ", count: reducedCount)

            isHandlingKeyEvent = true
            defer { isHandlingKeyEvent = false }

            // Replace the whitespace before cursor with reduced indent + }
            let replaceRange = NSRange(location: lineStart, length: affectedRange.location - lineStart)
            textView.insertText(newIndent + "}", replacementRange: replaceRange)
        }

        // MARK: - Pair Delete

        private func handlePairDelete(textView: NSTextView) -> Bool {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0 else { return false }

            let cursorPos = selectedRange.location
            let string = textView.string as NSString

            guard cursorPos > 0, cursorPos < string.length else { return false }

            if CompletionEngine.isInsideCommentOrString(text: textView.string, cursorOffset: cursorPos) {
                return false
            }

            let charBefore = Character(UnicodeScalar(string.character(at: cursorPos - 1))!)
            let charAfter = Character(UnicodeScalar(string.character(at: cursorPos))!)

            // Direct pair: {} or ()
            if (charBefore == "{" && charAfter == "}") || (charBefore == "(" && charAfter == ")") {
                isHandlingKeyEvent = true
                defer { isHandlingKeyEvent = false }
                let deleteRange = NSRange(location: cursorPos - 1, length: 2)
                textView.insertText("", replacementRange: deleteRange)
                return true
            }

            // Spaced pair: cursor right after { or (, scan forward through whitespace for matching close
            if charBefore == "{" || charBefore == "(" {
                let expectedClose: Character = charBefore == "{" ? "}" : ")"
                var scanPos = cursorPos
                while scanPos < string.length {
                    let c = Character(UnicodeScalar(string.character(at: scanPos))!)
                    if c == expectedClose {
                        isHandlingKeyEvent = true
                        defer { isHandlingKeyEvent = false }
                        let deleteRange = NSRange(location: cursorPos - 1, length: scanPos - cursorPos + 2)
                        textView.insertText("", replacementRange: deleteRange)
                        return true
                    } else if c != " " {
                        break
                    }
                    scanPos += 1
                }
            }

            return false
        }
    }
}
