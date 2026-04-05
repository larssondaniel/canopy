import AppKit

final class CompletionPanel: NSPanel {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let visualEffectView = NSVisualEffectView()
    private(set) var items: [CompletionItem] = []

    private static let rowHeight: CGFloat = 20
    private static let maxVisibleRows = 10
    private static let panelWidth: CGFloat = 340
    private static let cornerRadius: CGFloat = 6

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
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
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
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        scrollView.frame = visualEffectView.bounds
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
        let height = CGFloat(visibleRows) * Self.rowHeight + 8 // +8 for top/bottom insets
        let frame = NSRect(x: screenPoint.x, y: screenPoint.y - height, width: Self.panelWidth, height: height)

        let adjustedFrame = adjustFrameForScreen(frame)
        setFrame(adjustedFrame, display: false)
        scrollView.frame = visualEffectView.bounds

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
        let height = CGFloat(visibleRows) * Self.rowHeight + 8
        var frame = self.frame
        let oldTop = frame.maxY
        frame.size.height = height
        frame.origin.y = oldTop - height
        setFrame(frame, display: true)
        scrollView.frame = visualEffectView.bounds
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
            adjusted.origin.y = frame.origin.y + frame.height + Self.rowHeight + 4
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
    private let kindBadge = NSView()
    private let labelField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let selectionBackground = NSView()

    private static let badgeSize: CGFloat = 8
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
        // Selection background (rounded rect)
        selectionBackground.wantsLayer = true
        selectionBackground.layer?.cornerRadius = Self.selectionCornerRadius
        selectionBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionBackground)

        // Kind badge (colored square)
        kindBadge.wantsLayer = true
        kindBadge.layer?.cornerRadius = 2
        kindBadge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(kindBadge)

        // Label
        labelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.drawsBackground = false
        labelField.isBezeled = false
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        // Detail (type annotation)
        detailField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.alignment = .right
        detailField.lineBreakMode = .byTruncatingTail
        detailField.drawsBackground = false
        detailField.isBezeled = false
        detailField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailField)

        NSLayoutConstraint.activate([
            // Selection background fills row with horizontal padding
            selectionBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            selectionBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            selectionBackground.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            selectionBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            // Kind badge
            kindBadge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            kindBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            kindBadge.widthAnchor.constraint(equalToConstant: Self.badgeSize),
            kindBadge.heightAnchor.constraint(equalToConstant: Self.badgeSize),

            // Label after badge
            labelField.leadingAnchor.constraint(equalTo: kindBadge.trailingAnchor, constant: 6),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: detailField.leadingAnchor, constant: -8),

            // Detail right-aligned
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
        ])

        labelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detailField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    func configure(with item: CompletionItem, isSelected: Bool) {
        labelField.stringValue = item.label
        detailField.stringValue = item.detail ?? ""

        // Kind badge color
        kindBadge.layer?.backgroundColor = badgeColor(for: item).cgColor

        // Selection highlight
        if isSelected {
            selectionBackground.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.6).cgColor
        } else {
            selectionBackground.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Text styling
        if item.isDeprecated {
            labelField.textColor = .tertiaryLabelColor
            detailField.textColor = .tertiaryLabelColor
        } else {
            labelField.textColor = isSelected ? .white : .labelColor
            detailField.textColor = isSelected ? NSColor.white.withAlphaComponent(0.7) : .secondaryLabelColor
        }
    }

    private func badgeColor(for item: CompletionItem) -> NSColor {
        switch item.kind {
        case .field:
            if item.label == "__typename" {
                return .systemGray
            }
            return .systemBlue
        case .argument:
            return .systemPurple
        case .keyword:
            return .systemPink
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let completionAccepted = Notification.Name("CompletionPanelAccepted")
}
