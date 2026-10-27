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

    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let max = QLMSettings.load().archives.maxEntries
        let listing = try QLMArchiveKit.listFile(atPath: url.path, maxEntries: max)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
