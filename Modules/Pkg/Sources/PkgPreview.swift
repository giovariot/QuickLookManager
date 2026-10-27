import AppKit
import QLMNative
import SwiftUI

/// Modulo «Pacchetti PKG»: in alto le informazioni del pacchetto (identificatore, versione, firma, script), in basso il contenuto.
enum PkgPreview {
    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let report = try PkgInspector.inspect(url: url)
        let host = NSHostingView(rootView: PkgView(report: report))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return host
    }
}

private struct PkgNode: Identifiable {
    let id: String
    let name: String
    var size: Int
    var mode: Int?
    var isDirectory: Bool
    var isLink: Bool
    var children: [PkgNode]?
}

/// Costruisce l'albero dai percorsi (con le cartelle che mancano) e somma le dimensioni delle cartelle.
private func buildTree(_ entries: [(path: String, isDirectory: Bool, isLink: Bool, mode: Int?, size: Int)]) -> [PkgNode] {
    final class B {
        var kids: [String: B] = [:]
        var order: [String] = []
        var isDirectory = false, isLink = false
        var mode: Int?
        var size = 0
    }
    let root = B()
    for e in entries {
        let parts = e.path.split(separator: "/").map(String.init)
        // I file «._nome» sono metadati AppleDouble (attributi estesi): non sono contenuto del pacchetto.
        guard !parts.isEmpty, !parts.contains(where: { $0.hasPrefix("._") }) else { continue }
        var node = root
        for (i, part) in parts.enumerated() {
            if node.kids[part] == nil { node.kids[part] = B(); node.order.append(part) }
            node = node.kids[part]!
            if i < parts.count - 1 { node.isDirectory = true }
        }
        node.isDirectory = node.isDirectory || e.isDirectory
        node.isLink = e.isLink
        node.mode = e.mode
        node.size = e.size
    }
    func order(_ a: PkgNode, _ b: PkgNode) -> Bool {
        a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
    func convert(_ b: B, name: String, path: String) -> PkgNode {
        let kids = b.order.map { convert(b.kids[$0]!, name: $0, path: path + "/" + $0) }.sorted(by: order)
        return PkgNode(id: path, name: name, size: b.isDirectory ? kids.reduce(0) { $0 + $1.size } : b.size, mode: b.mode,
                       isDirectory: b.isDirectory, isLink: b.isLink, children: b.isDirectory ? kids : nil)
    }
    return root.order.map { convert(root.kids[$0]!, name: $0, path: $0) }.sorted(by: order)
}

private struct PkgView: View {
    let report: PkgReport

    private var tree: [PkgNode] {
        report.components.flatMap { c -> [PkgNode] in
            var items = buildTree(c.entries.map { ($0.path, $0.isDirectory, $0.isLink, $0.mode, $0.size) })
            if !c.scriptFiles.isEmpty {
                let kids = c.scriptFiles.map { PkgNode(id: "\(c.name)/script/\($0.path)", name: $0.path.replacingOccurrences(of: "./", with: ""),
                                                      size: Int($0.size), mode: nil, isDirectory: false, isLink: false, children: nil) }
                items.insert(PkgNode(id: "\(c.name)/script", name: String(localized: "Script di installazione", bundle: QLMBundle.framework),
                                     size: kids.reduce(0) { $0 + $1.size }, mode: nil, isDirectory: true, isLink: false, children: kids), at: 0)
            }
            guard report.components.count > 1 else { return items }
            let label = c.identifier.map { "\(c.name) (\($0))" } ?? c.name
            return [PkgNode(id: c.name, name: label, size: items.reduce(0) { $0 + $1.size }, mode: nil, isDirectory: true, isLink: false, children: items)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            info
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            Divider()
            List(tree, children: \.children) { node in
                HStack {
                    Label(node.name, systemImage: node.isDirectory ? "folder" : (node.isLink ? "arrow.turn.up.right" : "doc"))
                        .lineLimit(1)
                    Spacer()
                    if let mode = node.mode, !node.isDirectory {
                        Text(permissions(mode)).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 70, alignment: .trailing)
                }
            }
            .listStyle(.plain)
            .overlay { if tree.isEmpty { ContentUnavailableView(String(localized: "Nessun elenco dei file", bundle: QLMBundle.framework), systemImage: "shippingbox") } }
        }
    }

    // MARK: Informazioni

    private var info: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "shippingbox.fill").font(.system(size: 44)).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.title ?? report.components.first?.identifier ?? report.fileName).font(.title2.bold()).lineLimit(2)
                    Text(report.fileName).font(.callout).foregroundStyle(.secondary)
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(rows, id: \.0) { row in
                        GridRow {
                            Text(row.0).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            Text(row.1).textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)
            }
        }
    }

    private var rows: [(String, String)] {
        var r: [(String, String)] = []
        let c = report.components
        let b = QLMBundle.framework
        if c.count == 1, let id = c[0].identifier { r.append((String(localized: "Identificatore", bundle: b), id)) }
        if c.count == 1, let v = c[0].version { r.append((String(localized: "Versione", bundle: b), v)) }
        if c.count > 1 { r.append((String(localized: "Componenti", bundle: b), "\(c.count)")) }
        if c.count == 1, let l = c[0].installLocation { r.append((String(localized: "Si installa in", bundle: b), l)) }
        let files = c.compactMap(\.numberOfFiles).reduce(0, +), kb = c.compactMap(\.installKBytes).reduce(0, +)
        if files > 0 || kb > 0 {
            r.append((String(localized: "Installato", bundle: b),
                      String(localized: "\(files.formatted()) file, \(ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file))", bundle: b)))
        }
        r.append((String(localized: "Dimensione", bundle: b), ByteCountFormatter.string(fromByteCount: report.fileSize, countStyle: .file)))
        if let os = report.minimumOS { r.append((String(localized: "Richiede", bundle: b), "macOS \(os)")) }
        if let arch = report.hostArchitectures { r.append((String(localized: "Architetture", bundle: b), arch.replacingOccurrences(of: ",", with: ", "))) }
        let scripts = Set(c.flatMap(\.scripts) + c.flatMap { $0.scriptFiles.map { ($0.path as NSString).lastPathComponent } }).sorted()
        r.append((String(localized: "Script", bundle: b), scripts.isEmpty ? String(localized: "nessuno", bundle: b) : scripts.joined(separator: ", ")))
        if report.requiresRestart { r.append((String(localized: "Riavvio", bundle: b), String(localized: "richiesto", bundle: b))) }
        if c.contains(where: { $0.auth?.lowercased() == "root" }) { r.append((String(localized: "Privilegi", bundle: b), String(localized: "amministratore", bundle: b))) }
        if let first = report.signers.first {
            var text = first
            if report.signers.count > 1 { text += " › " + report.signers.dropFirst().joined(separator: " › ") }
            if let ok = report.chainIsTrusted {
                text += ok ? "  ·  " + String(localized: "catena dei certificati valida", bundle: b)
                           : "  ·  " + String(localized: "catena dei certificati non valida", bundle: b)
            }
            r.append((String(localized: "Firmato da", bundle: b), text))
        } else {
            r.append((String(localized: "Firma", bundle: b), String(localized: "non firmato", bundle: b)))
        }
        return r
    }

    private func permissions(_ mode: Int) -> String {
        let bits = ["r", "w", "x"]
        return (0..<9).map { mode & (1 << (8 - $0)) != 0 ? bits[$0 % 3] : "-" }.joined()
    }
}
