import AppKit
import SwiftUI
import SwitchboardCore
import SwitchboardEditor

/// The rules as an AppKit table, as `main` shows them: selection, drag to reorder, double-click or
/// Return to edit, Delete to remove, a context menu, and its own scrolling. A SwiftUI List inside a
/// grouped Form gives none of those reliably. Each row is drawn by `RuleRow`.
struct RulesTable: NSViewRepresentable {
    let rules: [Rule]
    let hiddenBy: [Int: Int]
    let editor: Editor
    @Binding var selection: RuleID?
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Moves a rule to its final position (0-based).
    let onMove: (RuleID, Int) -> Void
    @Environment(\.isEnabled) private var isEnabled

    static let rowHeight: CGFloat = 44

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = RulesTableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClick)
        table.headerView = nil
        table.style = .inset
        table.backgroundColor = .clear
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("Rules. The first rule that matches a link wins.")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.registerForDraggedTypes([Coordinator.pasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.menu = context.coordinator.menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        context.coordinator.table = table
        context.coordinator.update(from: self, reload: true)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let previous = context.coordinator.parent
        let reload =
            previous.rules != rules || previous.hiddenBy != hiddenBy
            || previous.editor.config.browser != editor.config.browser
        context.coordinator.update(from: self, reload: reload)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let pasteboardType = NSPasteboard.PasteboardType(Identity.bundleID + ".rule-row")
        var parent: RulesTable
        weak var table: RulesTableView?
        private var updating = false

        init(_ parent: RulesTable) { self.parent = parent }

        func update(from parent: RulesTable, reload: Bool) {
            self.parent = parent
            guard let table else { return }
            table.onEdit = parent.onEdit
            table.onDelete = parent.onDelete
            table.isEnabled = parent.isEnabled
            updating = true
            defer { updating = false }
            if reload { table.reloadData() }
            let index = parent.rules.firstIndex { $0.id == parent.selection }
            if table.selectedRow != (index ?? -1) {
                table.selectRowIndexes(index.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
                if let index { table.scrollRowToVisible(index) }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.rules.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.rules.indices.contains(row) else { return nil }
            let cell =
                tableView.makeView(withIdentifier: RuleCell.identifier, owner: nil) as? RuleCell ?? RuleCell()
            cell.content = AnyView(
                RuleRow(
                    index: row, rule: parent.rules[row], hiddenBy: parent.hiddenBy[row], editor: parent.editor
                )
                .padding(.horizontal, 6))
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            parent.selection =
                parent.rules.indices.contains(table.selectedRow) ? parent.rules[table.selectedRow].id : nil
        }

        @objc func doubleClick() {
            guard let table, table.clickedRow >= 0 else { return }
            parent.onEdit()
        }

        // Dragging a row to a new place.

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard parent.isEnabled, parent.rules.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(String(row), forType: Self.pasteboardType)
            return item
        }

        func tableView(
            _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
            proposedDropOperation operation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard info.draggingSource as? NSTableView === tableView else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(
            _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard info.draggingSource as? NSTableView === tableView,
                let value = info.draggingPasteboard.string(forType: Self.pasteboardType),
                let from = Int(value), parent.rules.indices.contains(from)
            else { return false }
            // `row` is the gap the rule is dropped into; below its old place, that gap moves up one.
            let to = row > from ? row - 1 : row
            guard to != from else { return false }
            parent.onMove(parent.rules[from].id, to)
            return true
        }

        // The context menu acts on the row that was right-clicked.

        lazy var menu: NSMenu = {
            let menu = NSMenu()
            menu.addItem(withTitle: "Edit Rule…", action: #selector(editClicked), keyEquivalent: "").target =
                self
            menu.addItem(withTitle: "Delete Rule", action: #selector(deleteClicked), keyEquivalent: "")
                .target = self
            return menu
        }()

        private func selectClicked() -> Bool {
            guard let table, parent.rules.indices.contains(table.clickedRow) else { return false }
            parent.selection = parent.rules[table.clickedRow].id
            return true
        }

        @objc private func editClicked() {
            if selectClicked() { parent.onEdit() }
        }

        @objc private func deleteClicked() {
            if selectClicked() { parent.onDelete() }
        }
    }
}

/// Return edits the selected rule; Delete removes it.
final class RulesTableView: NSTableView {
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        guard selectedRow >= 0, isEnabled else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 36, 76: onEdit()  // Return, Enter
        case 51, 117: onDelete()  // Delete, Forward Delete
        default: super.keyDown(with: event)
        }
    }
}

/// A table cell that draws SwiftUI content, in white on the selected row of a key window as the
/// system draws its own rows.
final class RuleCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("RuleCell")

    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    var content = AnyView(EmptyView()) {
        didSet { render() }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { render() }
    }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RuleCell isn’t loaded from a nib.") }

    private func render() {
        let emphasized = backgroundStyle == .emphasized
        host.rootView = AnyView(
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(emphasized ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)))
    }
}
