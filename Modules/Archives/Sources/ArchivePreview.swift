import AppKit
import SwiftUI
import QLMNative

/// Modulo «Archivi»: elenco ad albero del contenuto, letto con libarchive.
enum ArchivePreview {
    struct Node: Identifiable {
        let id: String
        let name: String
        var size: Int64
        var modified: Date?
        var isDirectory: Bool
        var children: [Node]?
    }

    private static func folderFirst(_ a: Node, _ b: Node) -> Bool {
        a.isDirectory != b.isDirectory ? a.isDirectory : a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Costruisce l'albero dai percorsi: le cartelle mancanti vengono create.
    static func tree(from entries: [QLMArchiveEntry]) -> [Node] {
        final class Builder {
            var children: [String: Builder] = [:]
            var order: [String] = []
            var size: Int64 = 0
            var modified: Date?
            var isDirectory = false
            var isLeaf = true
        }
        let root = Builder()
        for e in entries {
            let parts = e.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
            guard !parts.isEmpty else { continue }
            var node = root
            for (i, part) in parts.enumerated() {
                if node.children[part] == nil { node.children[part] = Builder(); node.order.append(part) }
                node = node.children[part]!
                if i < parts.count - 1 { node.isDirectory = true; node.isLeaf = false }
            }
            node.size = e.size
            node.modified = e.modified
            if e.isDirectory { node.isDirectory = true }
        }
        func convert(_ b: Builder, name: String, path: String) -> Node {
            let kids = b.order.map { convert(b.children[$0]!, name: $0, path: path + "/" + $0) }.sorted(by: Self.folderFirst)
            return Node(id: path, name: name, size: b.isDirectory ? kids.reduce(0) { $0 + $1.size } : b.size,
                        modified: b.modified, isDirectory: b.isDirectory, children: b.isDirectory ? kids : nil)
        }
        return root.order.map { convert(root.children[$0]!, name: $0, path: $0) }.sorted(by: folderFirst)
    }

    /// libarchive per i formati d'archivio; per le immagini disco con volume UDF (ISO di Windows, DVD) si aggiunge
    /// il contenuto del UDF, perché la parte ISO9660 spesso è solo una facciata con un file di avviso.
    /// La voce «.» (la radice) non è un file e non si conta.
    static func combinedListing(path: String, maxEntries: Int) throws -> QLMArchiveListing {
        let base: QLMArchiveListing
        var failure: Error?
        var found: QLMArchiveListing?
        do { found = try QLMArchiveKit.listFile(atPath: path, maxEntries: maxEntries) } catch { failure = error }
        let udf = UDFReader.list(path: path, maxEntries: maxEntries)
        if let found { base = found } else if udf != nil { base = QLMArchiveListing(); base.format = "ISO9660"; base.filter = "none"; base.entries = [] }
        else { throw failure ?? PreviewError.unsupported }

        let isRoot: (QLMArchiveEntry) -> Bool = { e in
            let p = e.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return p.isEmpty || p == "."
        }
        let dots = base.entries.filter(isRoot).count
        base.entries = base.entries.filter { !isRoot($0) }
        base.totalCount = Swift.max(base.totalCount - dots, base.entries.count)

        guard let udf else { return base }
        var seen = Set<String>()
        var merged: [QLMArchiveEntry] = []
        for u in udf.entries {
            let e = QLMArchiveEntry()
            e.path = u.path; e.size = u.size; e.modified = u.modified; e.isDirectory = u.isDirectory
            merged.append(e)
            seen.insert(u.path.lowercased())
        }
        // Le voci della parte ISO9660 che nel UDF non ci sono (il file di avviso) restano.
        var extraCount = 0
        var extraSize: Int64 = 0
        for e in base.entries where !seen.contains(e.path.trimmingCharacters(in: CharacterSet(charactersIn: "./")).lowercased()) {
            merged.append(e); extraCount += 1
            if !e.isDirectory { extraSize += e.size }
        }
        base.entries = Array(merged.prefix(maxEntries))
        base.format = "\(base.format) + \(udf.revision)"
        base.totalCount = udf.totalCount + extraCount
        base.totalSize = udf.totalSize + extraSize
        base.truncated = udf.truncated || merged.count > maxEntries
        return base
    }

    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let max = QLMSettings.load().archives.maxEntries
        let listing = try combinedListing(path: url.path, maxEntries: max)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let root = ArchiveView(name: url.lastPathComponent, listing: listing, fileSize: fileSize, nodes: tree(from: listing.entries))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return host
    }
}

private struct ArchiveView: View {
    let name: String
    let listing: QLMArchiveListing
    let fileSize: Int64?
    let nodes: [ArchivePreview.Node]

    private var summary: String {
        var parts = [listing.format]
        if listing.filter != "none" { parts.append(listing.filter) }
        parts.append(String(localized: "\(listing.totalCount) voci", bundle: QLMBundle.framework))
        parts.append(String(localized: "\(ByteCountFormatter.string(fromByteCount: listing.totalSize, countStyle: .file)) non compressi", bundle: QLMBundle.framework))
        if let fileSize { parts.append(String(localized: "\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) su disco", bundle: QLMBundle.framework)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(summary).font(.callout).foregroundStyle(.secondary)
                if listing.truncated {
                    Text("Elenco limitato alle prime voci: gli altri file ci sono ma non sono mostrati.", bundle: QLMBundle.framework)
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            Divider()
            List(nodes, children: \.children) { node in
                HStack {
                    Label(node.name, systemImage: node.isDirectory ? "folder" : "doc")
                        .lineLimit(1)
                    Spacer()
                    if let date = node.modified, !node.isDirectory {
                        Text(date, format: .dateTime.year().month().day())
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
            }
            .listStyle(.plain)
            // Senza sfondo proprio: si vede quello semitrasparente della finestra di Quick Look.
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
