import AppKit

/// Vista ad albero (NSOutlineView) di un `DataNode`: colonne Chiave / Valore / Tipo.
/// Albero con selezione multipla e copia (⌘C e menu contestuale).
final class CopyableOutlineView: NSOutlineView {
    var copyHandler: ((_ rows: IndexSet, _ keysOnly: Bool, _ valuesOnly: Bool) -> Void)?

    private var targetRows: IndexSet {
        if clickedRow >= 0, !selectedRowIndexes.contains(clickedRow) { return IndexSet(integer: clickedRow) }
        if clickedRow >= 0 { return selectedRowIndexes }
        return selectedRowIndexes
    }
    @objc func copy(_ sender: Any?) { copyHandler?(targetRows, false, false) }
    @objc func copyKey(_ sender: Any?) { copyHandler?(targetRows, true, false) }
    @objc func copyValue(_ sender: Any?) { copyHandler?(targetRows, false, true) }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) || item.action == #selector(copyKey(_:)) || item.action == #selector(copyValue(_:)) { return !targetRows.isEmpty }
        return super.validateUserInterfaceItem(item)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        let m = NSMenu()
        m.addItem(withTitle: String(localized: "Copia chiave", bundle: QTLPaths.bundle), action: #selector(copyKey(_:)), keyEquivalent: "")
        m.addItem(withTitle: String(localized: "Copia valore", bundle: QTLPaths.bundle), action: #selector(copyValue(_:)), keyEquivalent: "")
        m.addItem(withTitle: String(localized: "Copia riga", bundle: QTLPaths.bundle), action: #selector(copy(_:)), keyEquivalent: "")
        m.items.forEach { $0.target = self }
        return m
    }
}

public final class DataOutlineController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    public let scrollView = NSScrollView()
    private let outline = CopyableOutlineView()
    private let root: DataNode
    private let showTypes: Bool

    public init(root: DataNode, expandLevels: Int, showTypes: Bool) {
        self.root = root
        self.showTypes = showTypes
        super.init()
        let keyCol = NSTableColumn(identifier: .init("key")); keyCol.title = String(localized: "Chiave", bundle: QTLPaths.bundle); keyCol.minWidth = 120; keyCol.width = 260
        let valCol = NSTableColumn(identifier: .init("value")); valCol.title = String(localized: "Valore", bundle: QTLPaths.bundle); valCol.minWidth = 120; valCol.width = 380
        outline.addTableColumn(keyCol)
        outline.addTableColumn(valCol)
        if showTypes {
            let typeCol = NSTableColumn(identifier: .init("type")); typeCol.title = String(localized: "Tipo", bundle: QTLPaths.bundle); typeCol.minWidth = 70; typeCol.width = 90
            outline.addTableColumn(typeCol)
        }
        outline.outlineTableColumn = keyCol
        outline.usesAlternatingRowBackgroundColors = true
        outline.style = .inset
        outline.rowSizeStyle = .default
        outline.allowsColumnReordering = false
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.dataSource = self
        outline.delegate = self
        outline.allowsMultipleSelection = true
        outline.setAccessibilityLabel(String(localized: "Struttura del documento", bundle: QTLPaths.bundle))
        outline.copyHandler = { [weak self] rows, keysOnly, valuesOnly in self?.copy(rows: rows, keysOnly: keysOnly, valuesOnly: valuesOnly) }
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        outline.reloadData()
        // la radice è mostrata espansa: i suoi figli sono il primo livello
        if expandLevels > 0 { expand(item: nil, level: expandLevels) }
    }

    private func expand(item: DataNode?, level: Int) {
        guard level > 0 else { return }
        let kids = item == nil ? rootChildren : (item!.children)
        for k in kids where k.isContainer {
            outline.expandItem(k)
            expand(item: k, level: level - 1)
        }
    }

    private func copy(rows: IndexSet, keysOnly: Bool, valuesOnly: Bool) {
        let lines: [String] = rows.compactMap { r in
            guard let n = outline.item(atRow: r) as? DataNode else { return nil }
            let value = n.isContainer ? n.summary : n.value
            if keysOnly { return n.key }
            if valuesOnly { return value }
            return n.key + "\t" + value
        }
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private var rootChildren: [DataNode] { root.isContainer ? root.children : [root] }

    // MARK: DataSource
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let n = item as? DataNode else { return rootChildren.count }
        return n.children.count
    }
    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let n = item as? DataNode else { return rootChildren[index] }
        return n.children[index]
    }
    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? DataNode)?.isContainer == true && !((item as! DataNode).children.isEmpty) }

    // MARK: Delegate
    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? DataNode, let id = tableColumn?.identifier else { return nil }
        let cell = NSTableCellView()
        cell.setAccessibilityLabel("\(n.key.isEmpty ? String(localized: "radice", bundle: QTLPaths.bundle) : n.key), \(n.typeLabel), \(n.summary)")
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.cell?.usesSingleLineMode = true
        cell.addSubview(tf)
        cell.textField = tf
        switch id.rawValue {
        case "key":
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.image = NSImage(systemSymbolName: Self.symbol(n.kind), accessibilityDescription: n.typeLabel)
            icon.contentTintColor = .secondaryLabelColor
            cell.addSubview(icon)
            cell.imageView = icon
            icon.setContentHuggingPriority(.required, for: .horizontal)
            icon.setContentCompressionResistancePriority(.required, for: .horizontal)
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            tf.stringValue = n.key.isEmpty ? String(localized: "(radice)", bundle: QTLPaths.bundle) : n.key
            tf.font = .preferredFont(forTextStyle: .body)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        case "value":
            tf.stringValue = n.summary.replacingOccurrences(of: "\n", with: "↵")
            tf.font = n.isContainer ? .preferredFont(forTextStyle: .body) : .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            tf.textColor = Self.color(n.kind)
            tf.toolTip = n.value.count > 60 ? String(n.value.prefix(2000)) : nil
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        default:
            tf.stringValue = n.typeLabel
            tf.textColor = .secondaryLabelColor
            tf.font = .preferredFont(forTextStyle: .callout)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    static func symbol(_ k: DataNode.Kind) -> String {
        switch k {
        case .object: return "curlybraces"
        case .array: return "list.bullet"
        case .string: return "textformat"
        case .number: return "number"
        case .bool: return "checkmark.square"
        case .null: return "circle.slash"
        case .date: return "calendar"
        case .data: return "doc.badge.gearshape"
        }
    }
    static func color(_ k: DataNode.Kind) -> NSColor {
        switch k {
        case .string: return .systemRed
        case .number: return .systemPurple
        case .bool: return .systemPink
        case .null: return .secondaryLabelColor
        case .date: return .systemTeal
        case .data: return .secondaryLabelColor
        default: return .secondaryLabelColor
        }
    }
}
