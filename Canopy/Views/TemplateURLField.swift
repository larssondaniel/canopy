import SwiftUI
import AppKit

struct TemplateURLField: NSViewRepresentable {
    @Binding var url: String
    var placeholder: String = ""
    var environmentVariables: [String: String] = [:]

    func makeNSView(context: Context) -> TokenizedURLTextField {
        let textField = TokenizedURLTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.isBordered = true
        textField.bezelStyle = .roundedBezel
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ textField: TokenizedURLTextField, context: Context) {
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        if let cell = textField.cell as? TokenizedURLFieldCell {
            cell.environmentVariables = environmentVariables
        }

        // The field editor owns the text while editing — skip redundant updates.
        guard textField.currentEditor() == nil else { return }

        if textField.stringValue != url {
            textField.stringValue = url
        }

        textField.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TemplateURLField
        var isUpdating = false

        init(_ parent: TemplateURLField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdating, let textField = notification.object as? NSTextField else { return }
            parent.url = textField.stringValue
        }
    }
}

// MARK: - Custom NSTextField that uses a tokenized cell

class TokenizedURLTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { TokenizedURLFieldCell.self }
        set { super.cellClass = newValue }
    }

    private var tooltipStrings: [NSView.ToolTipTag: String] = [:]

    func updateTooltips(_ tooltips: [(rect: NSRect, text: String)]) {
        removeAllToolTips()
        tooltipStrings.removeAll()
        for tooltip in tooltips {
            let tag = addToolTip(tooltip.rect, owner: self, userData: nil)
            tooltipStrings[tag] = tooltip.text
        }
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tooltipStrings[tag] ?? ""
    }
}

// MARK: - Custom cell that draws token pills when not editing

class TokenizedURLFieldCell: NSTextFieldCell {
    var environmentVariables: [String: String] = [:]

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        // When the field editor is active, it covers this cell — super is fine
        guard let textField = controlView as? NSTextField,
              textField.currentEditor() == nil else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }

        let text = stringValue
        guard !text.isEmpty else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }

        let segments = TokenizedURLDisplay.segments(from: text, variables: environmentVariables)
        let hasTokens = segments.contains { segment in
            if case .resolvedVariable = segment { return true }
            return false
        }
        guard hasTokens else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }

        let font = self.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        let titleRect = self.titleRect(forBounds: cellFrame)
        let accentColor = NSColor.controlAccentColor

        // Build display attributed string: {{var}} → " var " (with space padding for pill inset)
        let displayString = NSMutableAttributedString()
        struct PillInfo {
            let displayRange: NSRange
            let name: String
            let value: String
        }
        var pills: [PillInfo] = []

        for segment in segments {
            switch segment {
            case .text(let str):
                displayString.append(NSAttributedString(string: str, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.textColor
                ]))
            case .resolvedVariable(let name, let value):
                let padded = " \(name) "
                let start = displayString.length
                displayString.append(NSAttributedString(string: padded, attributes: [
                    .font: font,
                    .foregroundColor: accentColor.withAlphaComponent(0.85)
                ]))
                pills.append(PillInfo(
                    displayRange: NSRange(location: start, length: padded.count),
                    name: name,
                    value: value
                ))
            case .unresolvedVariable(let rawText):
                displayString.append(NSAttributedString(string: rawText, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
        }

        // Use NSLayoutManager for a single source of truth on glyph positions
        let textStorage = NSTextStorage(attributedString: displayString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: titleRect.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byTruncatingTail
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cellFrame).addClip()

        var tooltips: [(rect: NSRect, text: String)] = []

        // Draw pill backgrounds at exact glyph positions
        for pill in pills {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: pill.displayRange, actualCharacterRange: nil)
            var pillRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            pillRect = pillRect.offsetBy(dx: titleRect.origin.x, dy: titleRect.origin.y)

            let bgPath = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
            accentColor.withAlphaComponent(0.12).setFill()
            bgPath.fill()

            let borderPath = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            accentColor.withAlphaComponent(0.25).setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()

            tooltips.append((rect: pillRect, text: "\(pill.name) \u{2192} \(pill.value)"))
        }

        (textField as? TokenizedURLTextField)?.updateTooltips(tooltips)

        // Draw text glyphs from the same layout — positions are guaranteed consistent
        let allGlyphs = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.drawGlyphs(forGlyphRange: allGlyphs, at: titleRect.origin)

        NSGraphicsContext.restoreGraphicsState()
    }
}
