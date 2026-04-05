import AppKit

final class GraphQLNSTextView: NSTextView {
    private let highlightColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.08)

    /// Called when the user presses Ctrl+Space to trigger manual completion.
    var completionTrigger: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers == " " {
            completionTrigger?()
            return
        }
        super.keyDown(with: event)
    }

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
