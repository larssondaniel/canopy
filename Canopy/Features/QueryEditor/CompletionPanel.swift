import AppKit

final class CompletionPanel: NSPanel {

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private(set) var items: [CompletionItem] = []

    private static let rowHeight: CGFloat = 22
    private static let maxVisibleRows = 10
    private static let panelWidth: CGFloat = 300

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
        backgroundColor = .clear

        setupTableView()
        setupScrollView()
        contentView = scrollView
    }

    // MARK: - Setup

    private func setupTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.width = Self.panelWidth
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .windowBackgroundColor
        tableView.selectionHighlightStyle = .regular
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
        scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor
    }

    // MARK: - Public API

    /// Show the panel with items at a screen position (below the cursor line).
    func show(items: [CompletionItem], at screenPoint: NSPoint, parentWindow: NSWindow) {
        guard !items.isEmpty else { dismiss(); return }

        self.items = items
        tableView.reloadData()

        // Select first item
        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        // Size to fit content
        let visibleRows = min(items.count, Self.maxVisibleRows)
        let height = CGFloat(visibleRows) * Self.rowHeight + 2 // +2 for border
        let frame = NSRect(x: screenPoint.x, y: screenPoint.y - height, width: Self.panelWidth, height: height)

        // Adjust if panel would go off-screen
        let adjustedFrame = adjustFrameForScreen(frame)
        setFrame(adjustedFrame, display: false)

        parentWindow.addChildWindow(self, ordered: .above)
        orderFront(nil)
    }

    /// Update the displayed items without changing position.
    func updateItems(_ newItems: [CompletionItem]) {
        guard !newItems.isEmpty else { dismiss(); return }

        let previousSelection = selectedItem()?.label
        self.items = newItems
        tableView.reloadData()

        // Try to preserve selection, otherwise select first
        if let previousLabel = previousSelection,
           let newIndex = newItems.firstIndex(where: { $0.label == previousLabel }) {
            tableView.selectRowIndexes(IndexSet(integer: newIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(newIndex)
        } else {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        // Resize height
        let visibleRows = min(newItems.count, Self.maxVisibleRows)
        let height = CGFloat(visibleRows) * Self.rowHeight + 2
        var frame = self.frame
        let oldBottom = frame.origin.y
        frame.size.height = height
        frame.origin.y = oldBottom + (self.frame.height - height)
        setFrame(frame, display: true)
    }

    /// Return the currently selected completion item.
    func selectedItem() -> CompletionItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    /// Move selection up by one row.
    func moveSelectionUp() {
        let current = tableView.selectedRow
        let newRow = max(0, current - 1)
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
    }

    /// Move selection down by one row.
    func moveSelectionDown() {
        let current = tableView.selectedRow
        let newRow = min(items.count - 1, current + 1)
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
    }

    /// Dismiss and remove the panel.
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

        // If panel goes below screen bottom, show above the cursor instead
        if adjusted.origin.y < screenFrame.origin.y {
            // Flip above: move up by panel height + line height (~20pt)
            adjusted.origin.y = frame.origin.y + frame.height + Self.rowHeight + 4
        }

        // Clamp to right edge
        if adjusted.maxX > screenFrame.maxX {
            adjusted.origin.x = screenFrame.maxX - adjusted.width
        }

        // Clamp to left edge
        if adjusted.origin.x < screenFrame.origin.x {
            adjusted.origin.x = screenFrame.origin.x
        }

        return adjusted
    }

    @objc private func rowDoubleClicked() {
        // Double-click accepts completion — handled by the coordinator via notification
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

        cell.configure(with: item)
        return cell
    }
}

// MARK: - Cell View

private final class CompletionCellView: NSView {
    private let labelField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        labelField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        labelField.lineBreakMode = .byTruncatingTail
        labelField.translatesAutoresizingMaskIntoConstraints = false

        detailField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.alignment = .right
        detailField.lineBreakMode = .byTruncatingTail
        detailField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelField)
        addSubview(detailField)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: detailField.leadingAnchor, constant: -8),

            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
        ])

        labelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        detailField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    func configure(with item: CompletionItem) {
        labelField.stringValue = item.label
        detailField.stringValue = item.detail ?? ""

        if item.isDeprecated {
            labelField.textColor = .tertiaryLabelColor
        } else {
            labelField.textColor = .labelColor
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let completionAccepted = Notification.Name("CompletionPanelAccepted")
}
