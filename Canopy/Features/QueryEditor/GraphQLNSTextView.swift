import AppKit

final class GraphQLNSTextView: NSTextView {
    private let highlightColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.08)

    /// Called when the user presses Ctrl+Space to trigger manual completion.
    var completionTrigger: (() -> Void)?

    /// Closure to retrieve current validation errors. Set by the Coordinator.
    var errorProvider: (() -> [QueryValidator.ValidationError])?

    /// Whether the completion panel is currently visible. Set by the Coordinator.
    var isCompletionVisible: (() -> Bool)?

    private var errorPopover: NSPopover?
    private var currentlyShownErrorIndex: Int?
    private var trackingArea: NSTrackingArea?

    override func keyDown(with event: NSEvent) {
        // Dismiss error tooltip on keystroke
        dismissErrorPopover()

        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers == " " {
            completionTrigger?()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Mouse Hover

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)

        // Don't show error tooltip while completion panel is visible
        if isCompletionVisible?() == true {
            dismissErrorPopover()
            return
        }

        guard let errors = errorProvider?(), !errors.isEmpty else {
            dismissErrorPopover()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndex(at: point)
        guard charIndex != NSNotFound else {
            dismissErrorPopover()
            return
        }

        // Find error at this character position
        if let errorIndex = errors.firstIndex(where: { NSLocationInRange(charIndex, $0.range) }) {
            if currentlyShownErrorIndex == errorIndex { return } // Already showing this one
            showErrorPopover(for: errors[errorIndex], index: errorIndex)
        } else {
            dismissErrorPopover()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        dismissErrorPopover()
    }

    // MARK: - Error Popover

    private func showErrorPopover(for error: QueryValidator.ValidationError, index: Int) {
        dismissErrorPopover()

        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        // Calculate rect for the error range
        let glyphRange = layoutManager.glyphRange(forCharacterRange: error.range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = true

        let label = NSTextField(labelWithString: error.message)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.preferredMaxLayoutWidth = 300
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])

        let vc = NSViewController()
        vc.view = contentView
        popover.contentViewController = vc

        errorPopover = popover
        currentlyShownErrorIndex = index
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    private func dismissErrorPopover() {
        errorPopover?.performClose(nil)
        errorPopover = nil
        currentlyShownErrorIndex = nil
    }

    /// Called externally (e.g. on scroll) to dismiss the error popover.
    func dismissErrorPopoverOnScroll() {
        dismissErrorPopover()
    }

    /// Convert a point in view coordinates to a character index.
    private func characterIndex(at point: NSPoint) -> Int {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return NSNotFound }

        let textPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        // Check the point is within text bounds
        let textRect = layoutManager.usedRect(for: textContainer)
        guard textRect.contains(textPoint) else { return NSNotFound }

        var fraction: CGFloat = 0
        let index = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        return index
    }

    // MARK: - Current Line Highlight

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineHighlight(in: rect)
    }

    private func drawCurrentLineHighlight(in rect: NSRect) {
        guard let layoutManager = layoutManager,
              textContainer != nil else { return }

        // Only highlight when there's an insertion point (no selection)
        let selectedRange = selectedRange()
        guard selectedRange.length == 0 else { return }

        let cursorPosition = selectedRange.location
        let lineRange = (string as NSString).lineRange(for: NSRange(location: cursorPosition, length: 0))

        var lineRect: NSRect
        if lineRange.length == 0 {
            // Cursor is on the extra line after trailing newline — use extraLineFragmentRect
            lineRect = layoutManager.extraLineFragmentRect
        } else {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        }

        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        lineRect.origin.y += textContainerOrigin.y

        guard lineRect.intersects(rect) else { return }

        highlightColor.setFill()
        lineRect.fill()
    }
}
