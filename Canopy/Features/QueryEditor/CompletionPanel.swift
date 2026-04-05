import AppKit

final class CompletionPanel: NSPanel {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let visualEffectView = NSVisualEffectView()
    private(set) var items: [CompletionItem] = []

    private static let rowHeight: CGFloat = 20
    private static let maxVisibleRows = 10
    private static let panelWidth: CGFloat = 260
    private static let cornerRadius: CGFloat = 6
    private static let panelPadding: CGFloat = 4

    // MARK: - Init

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 0),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        level = .floating
        isMovable = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear

        setupVisualEffect()
        setupTableView()
        setupScrollView()

        scrollView.frame = visualEffectView.bounds
        scrollView.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(scrollView)
        contentView = visualEffectView
    }

    // MARK: - Setup

    private func setupVisualEffect() {
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = Self.cornerRadius
        visualEffectView.layer?.masksToBounds = true
    }

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.width = Self.panelWidth
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
    }

    private func setupScrollView() {
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init(top: Self.panelPadding, left: 0, bottom: Self.panelPadding, right: 0)
        tableView.sizeLastColumnToFit()
    }

    // MARK: - Public API

    func show(items: [CompletionItem], at screenPoint: NSPoint, parentWindow: NSWindow) {
        guard !items.isEmpty else { dismiss(); return }

        self.items = items
        tableView.reloadData()

        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        let visibleRows = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(visibleRows) * Self.rowHeight + Self.panelPadding * 2 // +8 for top/bottom insets
        let frame = NSRect(x: screenPoint.x, y: screenPoint.y - height, width: Self.panelWidth, height: height)

        let adjustedFrame = adjustFrameForScreen(frame)
        setFrame(adjustedFrame, display: false)
        tableView.sizeLastColumnToFit()

        parentWindow.addChildWindow(self, ordered: .above)
        orderFront(nil)
    }

    func updateItems(_ newItems: [CompletionItem]) {
        guard !newItems.isEmpty else { dismiss(); return }

        let previousSelection = selectedItem()?.label
        self.items = newItems
        tableView.reloadData()

        if let previousLabel = previousSelection,
           let newIndex = newItems.firstIndex(where: { $0.label == previousLabel }) {
            tableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(newIndex)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        let visibleRows = min(newItems.count, Self.maxVisibleRows)
        let height = CGFloat(visibleRows) * Self.rowHeight + Self.panelPadding * 2
        var frame = self.frame
        let oldTop = frame.maxY
        frame.size.height = height
        frame.origin.y = oldTop - height
        setFrame(frame, display: true)
        tableView.sizeLastColumnToFit()
    }

    func selectedItem() -> CompletionItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    func moveSelectionUp() {
        let current = tableView.selectedRow
        let newRow = max(0, current - 1)
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
    }

    func moveSelectionDown() {
        let current = tableView.selectedRow
        let newRow = min(items.count - 1, current + 1)
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
    }

    func dismiss() {
        parent?.removeChildWindow(self)
        orderOut(nil)
        items = []
    }

    // MARK: - Positioning

    private func adjustFrameForScreen(_ frame: NSRect) -> NSRect {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return frame }
        let screenFrame = screen.visibleFrame
        var adjusted = frame

        if adjusted.origin.y < screenFrame.origin.y {
            adjusted.origin.y = frame.origin.y + frame.height + Self.rowHeight
        }
        if adjusted.maxX > screenFrame.maxX {
            adjusted.origin.x = screenFrame.maxX - adjusted.width
        }
        if adjusted.origin.x < screenFrame.origin.x {
            adjusted.origin.x = screenFrame.origin.x
        }

        return adjusted
    }

    @objc private func rowDoubleClicked() {
        NotificationCenter.default.post(name: .completionAccepted, object: self)
    }
}

// MARK: - NSTableViewDataSource

extension CompletionPanel: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
}

// MARK: - NSTableViewDelegate

extension CompletionPanel: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let cellID = NSUserInterfaceItemIdentifier("CompletionCell")
        let cell: CompletionCellView
        if let existing = tableView.makeView(withIdentifier: cellID, owner: nil) as? CompletionCellView {
            cell = existing
        } else {
            cell = CompletionCellView()
            cell.identifier = cellID
        }

        cell.configure(with: item, isSelected: tableView.selectedRow == row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Refresh all visible rows to update selection highlight
        let visibleRange = tableView.rows(in: tableView.visibleRect)
        for row in visibleRange.lowerBound..<visibleRange.upperBound {
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? CompletionCellView,
               row < items.count {
                cell.configure(with: items[row], isSelected: tableView.selectedRow == row)
            }
        }
    }
}

// MARK: - Cell View

private final class CompletionCellView: NSView {
    private let badgeView = KindBadgeView()
    private let labelField = NSTextField(labelWithString: "")
    private let selectionBackground = NSView()

    private static let badgeSize: CGFloat = 16
    private static let selectionCornerRadius: CGFloat = 4

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        selectionBackground.wantsLayer = true
        selectionBackground.layer?.cornerRadius = Self.selectionCornerRadius
        selectionBackground.shadow = NSShadow()
        selectionBackground.layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        selectionBackground.layer?.shadowOffset = CGSize(width: 0, height: -1)
        selectionBackground.layer?.shadowRadius = 2
        selectionBackground.layer?.shadowOpacity = 0
        selectionBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionBackground)

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeView)

        labelField.font = .systemFont(ofSize: 12)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.drawsBackground = false
        labelField.isBezeled = false
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        NSLayoutConstraint.activate([
            selectionBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            selectionBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            selectionBackground.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            selectionBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: Self.badgeSize),
            badgeView.heightAnchor.constraint(equalToConstant: Self.badgeSize),

            labelField.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 6),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])

        labelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func configure(with item: CompletionItem, isSelected: Bool) {
        labelField.stringValue = item.label
        badgeView.configure(for: item)

        if isSelected {
            selectionBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            selectionBackground.layer?.shadowOpacity = 0.4
        } else {
            selectionBackground.layer?.backgroundColor = NSColor.clear.cgColor
            selectionBackground.layer?.shadowOpacity = 0
        }

        if item.isDeprecated {
            labelField.textColor = .tertiaryLabelColor
        } else {
            labelField.textColor = .labelColor
        }
    }
}

// MARK: - Kind Badge (Xcode-style letter in colored rounded square)

private final class KindBadgeView: NSView {
    private var letter: String = ""
    private var badgeColor: NSColor = .systemGray

    override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)

        // Fill
        badgeColor.setFill()
        path.fill()

        // Letter
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (letter as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        (letter as NSString).draw(at: point, withAttributes: attrs)
    }

    func configure(for item: CompletionItem) {
        let (l, c) = badgeStyle(for: item)
        letter = l
        badgeColor = c
        needsDisplay = true
    }

    private func badgeStyle(for item: CompletionItem) -> (String, NSColor) {
        switch item.kind {
        case .field:
            if item.label == "__typename" {
                return ("T", NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1))
            }
            return ("F", NSColor(red: 0.33, green: 0.67, blue: 0.86, alpha: 1))
        case .argument:
            return ("A", NSColor(red: 0.63, green: 0.44, blue: 0.82, alpha: 1))
        case .keyword:
            return ("K", NSColor(red: 0.82, green: 0.44, blue: 0.60, alpha: 1))
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let completionAccepted = Notification.Name("CompletionPanelAccepted")
}
