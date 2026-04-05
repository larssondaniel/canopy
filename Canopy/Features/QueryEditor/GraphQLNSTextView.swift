import AppKit

final class GraphQLNSTextView: NSTextView {
    private let highlightColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.08)

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCurrentLineHighlight(in: rect)
    }

    private func drawCurrentLineHighlight(in rect: NSRect) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        // Only highlight when there's an insertion point (no selection)
        let selectedRange = selectedRange()
        guard selectedRange.length == 0 else { return }

        let cursorPosition = selectedRange.location
        let lineRange = (string as NSString).lineRange(for: NSRange(location: cursorPosition, length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)

        var lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        lineRect.origin.x = 0
        lineRect.size.width = bounds.width
        lineRect.origin.y += textContainerOrigin.y

        guard lineRect.intersects(rect) else { return }

        highlightColor.setFill()
        lineRect.fill()
    }
}
