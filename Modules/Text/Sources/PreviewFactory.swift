import AppKit

public enum PreviewError: Error, LocalizedError {
    case unsupported
    public var errorDescription: String? { String(localized: "Formato non supportato da QuickLook Manager.", bundle: QTLPaths.bundle) }
}

/// Contenitore di una vista dati: barra con Struttura/Sorgente e avviso d'errore.
final class DataPreviewContainer: NSView {
    private let segmented: NSSegmentedControl
    private let tree: NSView?
    private let source: NSView
    private let holder = NSView()

    init(tree: NSView?, source: NSView, startWithTree: Bool, error: String?) {
        self.tree = tree
        self.source = source
        segmented = NSSegmentedControl(labels: [String(localized: "Struttura", bundle: QTLPaths.bundle), String(localized: "Sorgente", bundle: QTLPaths.bundle)], trackingMode: .selectOne, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        segmented.target = self
        segmented.action = #selector(modeChanged)
        segmented.segmentStyle = .automatic
        segmented.setAccessibilityLabel(String(localized: "Modo di visualizzazione", bundle: QTLPaths.bundle))
        segmented.selectedSegment = (tree != nil && startWithTree) ? 0 : 1
        segmented.isEnabled = tree != nil
        segmented.translatesAutoresizingMaskIntoConstraints = false
        holder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(holder)
        let bar = NSVisualEffectView()
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        bar.addSubview(segmented)
        var constraints = [
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            segmented.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            segmented.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            holder.topAnchor.constraint(equalTo: bar.bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: leadingAnchor),
            holder.trailingAnchor.constraint(equalTo: trailingAnchor),
            holder.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if let error {
            let label = NSTextField(wrappingLabelWithString: error)
            label.font = .preferredFont(forTextStyle: .callout)
            label.textColor = .systemRed
            label.translatesAutoresizingMaskIntoConstraints = false
            label.maximumNumberOfLines = 2
            bar.addSubview(label)
            constraints += [
                segmented.leadingAnchor.constraint(greaterThanOrEqualTo: bar.leadingAnchor, constant: 8),
                label.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 6),
                label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
                label.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
            ]
        } else {
            constraints.append(segmented.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8))
        }
        NSLayoutConstraint.activate(constraints)
        modeChanged()
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func modeChanged() {
        holder.subviews.forEach { $0.removeFromSuperview() }
        let v = (segmented.selectedSegment == 0 ? tree : source) ?? source
        v.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: holder.topAnchor),
            v.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
        ])
    }
}

@MainActor
public enum PreviewFactory {
    /// Costruisce la vista di anteprima per un file.
    public static func makeView(for url: URL, settings: QTLSettings = .load()) async throws -> NSView {
        let head = (try? FileHandle(forReadingFrom: url).read(upToCount: 8192)) ?? Data()
        let kind = FormatCatalog.kind(for: url, head: head)
        switch kind {
        case .binary: throw PreviewError.unsupported
        case .text(let dos): return try textView(url: url, legacyDOS: dos, settings: settings)
        case .code(let lang): return try codeView(url: url, language: lang, settings: settings)
        case .json: return try await dataView(url: url, kind: .json, settings: settings)
        case .yaml: return try await dataView(url: url, kind: .yaml, settings: settings)
        case .plist: return try await dataView(url: url, kind: .plist, settings: settings)
        case .markdown(let flavor):
            let f = flavor ?? (settings.markdown.flavor)
            return try await webView(url: url, kind: "markdown", flavor: f, settings: settings)
        case .markup(let m):
            guard settings.markdown.renderOtherMarkup else { return try textView(url: url, legacyDOS: false, settings: settings) }
            return try await webView(url: url, kind: m.rawValue, flavor: settings.markdown.flavor, settings: settings)
        case .man:
            return try await webView(url: url, kind: "man", flavor: "typora", settings: settings)
        }
    }

    nonisolated(unsafe) private static var retained: [MarkupWebView] = []

    // MARK: Testo

    static func notice(truncated: Bool) -> String? {
        truncated ? String(localized: "Il file è più grande del limite impostato: mostrata solo la parte iniziale.", bundle: QTLPaths.bundle) : nil
    }

    static func textView(url: URL, legacyDOS: Bool, settings: QTLSettings) throws -> NSView {
        let s = settings.text
        let r = try TextDecoding.read(url: url, maxBytes: s.maxKilobytes * 1024, preferred: s.encoding, legacyDOS: legacyDOS && s.legacyDOSEncoding)
        let mono = legacyDOS || s.fontStyle == .monospaced
        let font: NSFont = mono ? .monospacedSystemFont(ofSize: s.fontSize, weight: .regular) : .systemFont(ofSize: s.fontSize)
        let a = NSAttributedString(string: r.string, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        return CodeView.make(attributed: a, lineNumbers: s.lineNumbers, wrap: s.wrapLines && !legacyDOS, notice: notice(truncated: r.truncated))
    }

    // MARK: Codice

    static func codeView(url: URL, language: String?, settings: QTLSettings) throws -> NSView {
        let s = settings.code
        let r = try TextDecoding.read(url: url, maxBytes: s.maxKilobytes * 1024)
        let font = NSFont.monospacedSystemFont(ofSize: s.fontSize, weight: .regular)
        let a = Highlighter.shared.attributed(r.string, language: language, font: font, autoDetect: s.autoDetectLanguage)
        return CodeView.make(attributed: a, lineNumbers: s.lineNumbers, wrap: s.wrapLines, tabWidth: s.tabWidth, notice: notice(truncated: r.truncated))
    }

    // MARK: JSON / YAML / plist

    enum DataFormat { case json, yaml, plist }

    static func dataView(url: URL, kind: DataFormat, settings: QTLSettings) async throws -> NSView {
        let d = settings.data
        let handle = try FileHandle(forReadingFrom: url)
        let raw = try handle.read(upToCount: d.maxKilobytes * 1024 + 1) ?? Data()
        try? handle.close()
        let truncated = raw.count > d.maxKilobytes * 1024
        let data = truncated ? raw.prefix(d.maxKilobytes * 1024) : raw
        var sourceText: String
        var language: String
        var root: DataNode?
        var banner: String?

        switch kind {
        case .json:
            sourceText = TextDecoding.decode(data).string; language = "json"
            do { root = try DataTree.parseJSON(sourceText) } catch let e { banner = describe(e) }
        case .yaml:
            sourceText = TextDecoding.decode(data).string; language = "yaml"
            do { root = try DataTree.parseYAML(sourceText) } catch let e { banner = describe(e) }
        case .plist:
            language = "xml"
            sourceText = data.starts(with: Array("bplist".utf8)) ? (DataTree.xmlText(ofPlist: data) ?? "") : TextDecoding.decode(data).string
            if sourceText.isEmpty, let x = DataTree.xmlText(ofPlist: data) { sourceText = x }
            do { root = try DataTree.parsePlist(data) } catch let e { banner = describe(e) }
            if root == nil, banner != nil, sourceText.range(of: "<plist") == nil { language = "plaintext" }
        }
        if truncated { banner = (banner.map { $0 + " " } ?? "") + String(localized: "File troncato al limite impostato.", bundle: QTLPaths.bundle) }
        let font = NSFont.monospacedSystemFont(ofSize: settings.code.fontSize, weight: .regular)
        let attr = Highlighter.shared.attributed(sourceText, language: language, font: font, autoDetect: false)
        let sourceView = CodeView.make(attributed: attr, lineNumbers: settings.code.lineNumbers, wrap: settings.code.wrapLines, tabWidth: settings.code.tabWidth)
        var treeView: NSView?
        var controller: DataOutlineController?
        if let root {
            controller = DataOutlineController(root: root, expandLevels: d.expandLevels, showTypes: d.showTypes)
            treeView = controller!.scrollView
        }
        let startTree = (kind == .plist ? d.plistAsTree : true) && d.startMode == .tree
        let container = DataPreviewContainer(tree: treeView, source: sourceView, startWithTree: startTree, error: banner)
        if let controller { objc_setAssociatedObject(container, &assocKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
        return container
    }

    private static func describe(_ e: Error) -> String {
        let msg = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        return String(localized: "Errore di sintassi: \(msg)", bundle: QTLPaths.bundle)
    }

    // MARK: Markdown e altri markup

    static func webView(url: URL, kind: String, flavor: String, settings: QTLSettings) async throws -> NSView {
        let r = try TextDecoding.read(url: url, maxBytes: 8 * 1024 * 1024)
        let view = MarkupWebView()
        retained.append(view)
        if retained.count > 4 { retained.removeFirst() }
        // pendown e simili: trattati come Markdown
        try await view.show(kind: kind, source: r.string, settings: settings.markdown, flavor: flavor == "auto" ? "typora" : flavor)
        return view.webView
    }
}

nonisolated(unsafe) private var assocKey: UInt8 = 0
