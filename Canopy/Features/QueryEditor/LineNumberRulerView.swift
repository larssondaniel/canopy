import AppKit

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    private let rulerFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let textColor = NSColor.secondaryLabelColor
    private let gutterPadding: CGFloat = 8
    nonisolated(unsafe) private var observerTokens: [Any] = []

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 36
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startObserving() {
        guard let textView = textView else { return }

        let textToken = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.updateGutterWidth()
            self?.needsDisplay = true
        }
        observerTokens.append(textToken)

        if let clipView = scrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            let scrollToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.needsDisplay = true
            }
            observerTokens.append(scrollToken)
        }
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func updateGutterWidth() {
        guard let textView = textView else { return }
        let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
        let digitCount = max(3, String(lineCount).count)
        let charWidth = rulerFont.advancement(forGlyph: rulerFont.glyph(withName: "0")).width
        let newThickness = CGFloat(digitCount) * charWidth + gutterPadding * 2
        if abs(ruleThickness - newThickness) > 1 {
            ruleThickness = newThickness
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let backgroundColor = NSColor.controlBackgroundColor
        backgroundColor.setFill()
        rect.fill()

        let string = textView.string as NSString
        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let textOriginY = textView.textContainerOrigin.y
        let attributes: [NSAttributedString.Key: Any] = [
            .font: rulerFont,
            .foregroundColor: textColor
        ]

        var lineNumber = 1
        var index = 0

        // Count lines before visible range
        while index < visibleCharRange.location && index < string.length {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }

        // Draw visible line numbers
        index = visibleCharRange.location
        while index <= NSMaxRange(visibleCharRange) && index <= string.length {
            let lineRange: NSRange
            if index < string.length {
                lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            } else if index == string.length && string.length > 0 {
                // Handle trailing newline
                let lastChar = string.character(at: string.length - 1)
                if lastChar == 0x0A || lastChar == 0x0D {
                    lineRange = NSRange(location: index, length: 0)
                } else {
                    break
                }
            } else {
                break
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: max(glyphRange.location, 0), effectiveRange: nil)
            lineRect.origin.y += textOriginY

            let numberString = "\(lineNumber)" as NSString
            let size = numberString.size(withAttributes: attributes)
            let x = ruleThickness - size.width - gutterPadding
            let y = lineRect.origin.y + (lineRect.height - size.height) / 2

            // Convert from text view coordinate to ruler coordinate
            let convertedY = y - visibleRect.origin.y
            numberString.draw(at: NSPoint(x: x, y: convertedY), withAttributes: attributes)

            index = NSMaxRange(lineRange)
            lineNumber += 1

            // Safety: prevent infinite loop at end of text
            if lineRange.length == 0 { break }
        }
    }
}
