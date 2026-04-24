import AppKit

class PrivateDropdown: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let button: NSButton
    private let panel: NSPanel
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    var items: [String] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.tableView.reloadData()
            }
        }
    }
    var selected: String = "" { didSet { updateButtonTitle() } }
    var onSelect: ((String) -> Void)?

    override init() {
        button = NSButton(title: "—  ▾", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        button.frame = NSRect(x: 0, y: 0, width: 220, height: 24)

        let col = NSTableColumn(identifier: .init("item"))
        col.width = 240
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.allowsEmptySelection = false
        tableView.usesAlternatingRowBackgroundColors = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 200),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        panel.sharingType = .none
        panel.backgroundColor = NSColor.controlBackgroundColor
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false

        super.init()
        panel.contentView = scrollView
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        button.target = self
        button.action = #selector(toggle)
    }

    private func updateButtonTitle() {
        button.title = (selected.isEmpty ? "—" : selected) + "  ▾"
    }

    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil); return }
        tableView.reloadData()
        guard let win = button.window else { return }
        let bf = button.convert(button.bounds, to: nil)
        let sf = win.convertToScreen(bf)
        let rowH: CGFloat = 22
        let h = min(CGFloat(max(items.count, 1)) * rowH + 2, 220)
        let w = max(sf.width, 260)
        panel.setFrame(NSRect(x: sf.minX, y: sf.minY - h, width: w, height: h), display: true)
        tableView.frame = NSRect(x: 0, y: 0, width: w, height: CGFloat(items.count) * rowH)
        if let idx = items.firstIndex(of: selected) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        }
        win.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func rowClicked() {
        let idx = tableView.clickedRow
        guard idx >= 0, idx < items.count else { return }
        selected = items[idx]
        onSelect?(selected)
        close()
    }

    func close() {
        if let parent = panel.parent { parent.removeChildWindow(panel) }
        panel.orderOut(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let tf = NSTextField(labelWithString: items[row])
        tf.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tf.lineBreakMode = .byTruncatingMiddle
        tf.identifier = .init("cell")
        return tf
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        NSTableRowView()
    }
}
