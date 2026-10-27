import Foundation

/// Lettore del file `Bom` («bill of materials») di un pacchetto: l'elenco di tutti i file che installa, con tipo, permessi e
/// dimensione, senza dover scompattare il payload (che può pesare gigabyte). Formato in big-endian: un archivio di «blocchi»
/// indicizzati e un albero B che contiene i percorsi.
struct BomReader {
    struct Entry {
        var path: String
        var isDirectory: Bool
        var isLink: Bool
        var mode: Int
        var size: Int
        var user: Int
        var group: Int
        var linkTarget: String?
    }

    private let data: Data
    private var blocks: [(offset: Int, length: Int)] = []

    init?(data: Data) {
        self.data = data
        guard data.count > 512, data.prefix(8) == Data("BOMStore".utf8) else { return nil }
        let indexOffset = Int(u32(16)), varsOffset = Int(u32(24))
        guard indexOffset > 0, indexOffset + 4 <= data.count else { return nil }
        let count = Int(u32(indexOffset))
        guard count > 0, indexOffset + 4 + count * 8 <= data.count else { return nil }
        blocks = (0..<count).map { (Int(u32(indexOffset + 4 + $0 * 8)), Int(u32(indexOffset + 8 + $0 * 8))) }
        guard varsOffset + 4 <= data.count else { return nil }
        // Le variabili dicono dove sta la radice dell'albero dei percorsi («Paths»).
        var pos = varsOffset + 4
        let varCount = Int(u32(varsOffset))
        for _ in 0..<varCount {
            guard pos + 5 <= data.count else { break }
            let index = Int(u32(pos)), nameLength = Int(data[pos + 4])
            guard pos + 5 + nameLength <= data.count else { break }
            if String(decoding: data[(pos + 5)..<(pos + 5 + nameLength)], as: UTF8.self) == "Paths" { pathsBlock = index }
            pos += 5 + nameLength
        }
        guard pathsBlock != nil else { return nil }
    }

    private var pathsBlock: Int?

    private func u32(_ o: Int) -> UInt32 {
        guard o >= 0, o + 4 <= data.count else { return 0 }
        return UInt32(data[o]) << 24 | UInt32(data[o + 1]) << 16 | UInt32(data[o + 2]) << 8 | UInt32(data[o + 3])
    }
    private func u16(_ o: Int) -> Int {
        guard o >= 0, o + 2 <= data.count else { return 0 }
        return Int(data[o]) << 8 | Int(data[o + 1])
    }
    private func block(_ i: Int) -> Int? { i >= 0 && i < blocks.count ? blocks[i].offset : nil }

    /// Tutte le voci, in ordine di albero, fino a `limit`. `truncated` dice se ce n'erano di più.
    func entries(limit: Int) -> (entries: [Entry], total: Int, truncated: Bool) {
        guard let treeBlock = pathsBlock.flatMap(block), data.count >= treeBlock + 21 else { return ([], 0, false) }
        let total = Int(u32(treeBlock + 16))
        var node = Int(u32(treeBlock + 8))               // blocco della prima pagina dell'albero
        // Scende fino alla prima foglia: nei nodi interni il primo valore è il figlio.
        var guardDepth = 0
        while let off = block(node), u16(off) == 0, guardDepth < 32 {
            node = Int(u32(off + 12))
            guardDepth += 1
        }
        struct Raw { var id: Int; var parent: Int; var name: String; var info: Entry }
        var raw: [Int: Raw] = [:]
        var order: [Int] = []
        var visited = Set<Int>()
        while let off = block(node), !visited.contains(node) {
            visited.insert(node)
            let count = u16(off + 2)
            let forward = Int(u32(off + 4))
            for i in 0..<count {
                let rec = off + 12 + i * 8
                guard let infoBlock = block(Int(u32(rec))), let keyBlock = block(Int(u32(rec + 4))) else { continue }
                let id = Int(u32(infoBlock)), info2 = block(Int(u32(infoBlock + 4)))
                let parent = Int(u32(keyBlock))
                var nameEnd = keyBlock + 4
                while nameEnd < data.count, data[nameEnd] != 0 { nameEnd += 1 }
                let name = String(decoding: data[(keyBlock + 4)..<nameEnd], as: UTF8.self)
                var e = Entry(path: name, isDirectory: false, isLink: false, mode: 0, size: 0, user: 0, group: 0, linkTarget: nil)
                if let i2 = info2, i2 + 22 <= data.count {
                    let type = Int(data[i2])
                    e.isDirectory = type == 2
                    e.isLink = type == 3
                    e.mode = u16(i2 + 4)
                    e.user = Int(u32(i2 + 6))
                    e.group = Int(u32(i2 + 10))
                    e.size = Int(u32(i2 + 18))
                    if e.isLink {
                        let len = Int(u32(i2 + 27))
                        if len > 0, len < 4096, i2 + 31 + len <= data.count {
                            e.linkTarget = String(decoding: data[(i2 + 31)..<(i2 + 31 + len - 1)], as: UTF8.self)
                        }
                    }
                }
                raw[id] = Raw(id: id, parent: parent, name: name, info: e)
                order.append(id)
            }
            node = forward
            if forward == 0 { break }
        }
        // Percorsi completi risalendo i genitori.
        func fullPath(_ id: Int) -> String {
            var parts: [String] = []
            var cursor = id, depth = 0
            while let r = raw[cursor], depth < 64 {
                if r.name != "." { parts.append(r.name) }
                if r.parent == 0 || r.parent == cursor { break }
                cursor = r.parent
                depth += 1
            }
            return parts.reversed().joined(separator: "/")
        }
        var result: [Entry] = []
        for id in order.prefix(limit) {
            guard var e = raw[id]?.info else { continue }
            e.path = fullPath(id)
            if !e.path.isEmpty { result.append(e) }
        }
        return (result, max(total, order.count), order.count > limit)
    }
}
