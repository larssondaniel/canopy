import AppKit

final class LineNumberView: NSView {
    weak var textView: NSTextView?

    private let gutterFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let gutterPadding: CGFloat = 8
    private let minimumDigits = 3

    nonisolated(unsafe) private var observerTokens: [Any] = []
    private var thickness: CGFloat = 36 {
        didSet {
            if oldValue != thickness {
                invalidateIntrinsicContentSize()
            }
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: thickness, height: NSView.noIntrinsicMetric)
    }

    override var isOpaque: Bool { true }

    override var isFlipped: Bool { true }

    func startObserving() {
        guard let textView = textView,
              let scrollView = textView.enclosingScrollView else { return }

        let textToken = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.updateThickness()
            self?.needsDisplay = true
        }
        observerTokens.append(textToken)

        let selectionToken = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        observerTokens.append(selectionToken)

        scrollView.contentView.postsBoundsChangedNotifications = true
        let scrollToken = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        observerTokens.append(scrollToken)

        let frameToken = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
        observerTokens.append(frameToken)
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func updateThickness() {
        guard let textView = textView else { return }
        let lineCount = max(1, textView.string.components(separatedBy: "\n").count)
        let digitCount = max(minimumDigits, String(lineCount).count)
        let charWidth = ("8" as NSString).size(withAttributes: [.font: gutterFont]).width
        let newThickness = (CGFloat(digitCount) * charWidth + gutterPadding * 2).rounded(.up)
        thickness = newThickness
    }

    override func draw(_ dirtyRect: NSRect) {
        // Always clear entire bounds to prevent stale numbers on partial redraws
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        drawLineNumbers()
    }

    private func drawLineNumbers() {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let string = textView.string as NSString

        let attributes: [NSAttributedString.Key: Any] = [
            .font: gutterFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Convert coordinate systems: where is textView relative to us?
        let relativePoint = convert(NSPoint.zero, from: textView)
        let originOffset = textView.textContainerOrigin.y

        // Handle empty document
        guard string.length > 0 else {
            let lineRect = layoutManager.extraLineFragmentRect
            let y = relativePoint.y + originOffset + lineRect.origin.y
            drawNumber(1, at: y, lineHeight: lineRect.height, attributes: attributes)
            return
        }

        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Count lines before visible range
        var lineNumber = 1
        var index = 0
        while index < visibleCharRange.location && index < string.length {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }

        // Draw visible line numbers
        index = visibleCharRange.location
        while index < string.length {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)

            let y = relativePoint.y + originOffset + lineRect.origin.y
            drawNumber(lineNumber, at: y, lineHeight: lineRect.height, attributes: attributes)

            index = NSMaxRange(lineRange)
            lineNumber += 1

            if index > NSMaxRange(visibleCharRange) { break }
        }

        // Draw number for trailing empty line (text ends with newline)
        let lastChar = string.character(at: string.length - 1)
        if (lastChar == 0x0A || lastChar == 0x0D) && index >= string.length {
            let extraRect = layoutManager.extraLineFragmentRect
            if !extraRect.isEmpty {
                let y = relativePoint.y + originOffset + extraRect.origin.y
                drawNumber(lineNumber, at: y, lineHeight: extraRect.height, attributes: attributes)
            }
        }
    }

    private func drawNumber(_ number: Int, at y: CGFloat, lineHeight: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let numberString = "\(number)" as NSString
        let size = numberString.size(withAttributes: attributes)
        let x = thickness - size.width - gutterPadding
        let drawY = y + (lineHeight - size.height) / 2
        numberString.draw(at: NSPoint(x: x, y: drawY), withAttributes: attributes)
    }
}
