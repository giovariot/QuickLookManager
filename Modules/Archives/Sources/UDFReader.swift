import Foundation

/// Lettore dell'elenco di un volume UDF (ECMA-167 / UDF 1.02–2.01), letto a mano dal file: niente montaggio,
/// che un'estensione in sandbox non può fare.
///
/// Serve per le ISO di Windows e per i DVD: hanno una parte ISO9660 «di facciata» (spesso un solo file,
/// `README.TXT`) e i file veri nel volume UDF accanto, e libarchive legge solo la prima.
///
/// Si legge soltanto l'elenco (nome, tipo, dimensione, data), mai il contenuto dei file. Supporta le mappe di
/// partizione fisiche; i volumi con partizione virtuale, a sparing o di metadati (UDF 2.50 e successivi)
/// non si leggono e `list` restituisce `nil`: resta l'elenco ISO9660.
enum UDFReader {
    struct Entry {
        var path: String
        var size: Int64
        var modified: Date?
        var isDirectory: Bool
    }

    struct Result {
        /// Per esempio «UDF 1.02».
        var revision: String
        var entries: [Entry]
        /// Voci totali, anche oltre quelle tenute in `entries`.
        var totalCount: Int
        var totalSize: Int64
        var truncated: Bool
    }

    /// Un volume UDF si riconosce dal descrittore di ancoraggio al settore 256.
    static func list(path: String, maxEntries: Int) -> Result? {
        guard let reader = Reader(path: path), reader.open() else { return nil }
        return reader.list(maxEntries: maxEntries)
    }

    // MARK: - Lettura

    private static let sector = 2048
    /// Tetto di voci contate: oltre, l'elenco si ferma (un volume enorme non deve bloccare l'anteprima).
    private static let hardLimit = 300_000

    private final class Reader {
        let fd: Int32
        var partitions: [UInt16: UInt64] = [:]   // numero di partizione -> primo settore
        var maps: [UInt16] = []                  // indice della mappa -> numero di partizione
        var revision = 0
        var fileSet: (block: UInt32, part: UInt16)?

        init?(path: String) {
            fd = Darwin.open(path, O_RDONLY)
            guard fd >= 0 else { return nil }
        }
        deinit { Darwin.close(fd) }

        func read(offset: UInt64, length: Int) -> [UInt8]? {
            guard length > 0, length <= 64 * 1024 * 1024 else { return nil }
            var buffer = [UInt8](repeating: 0, count: length)
            let n = pread(fd, &buffer, length, off_t(offset))
            return n == length ? buffer : nil
        }
        func readSector(_ n: UInt64) -> [UInt8]? { read(offset: n * UInt64(UDFReader.sector), length: UDFReader.sector) }

        // Little endian
        func u16(_ b: [UInt8], _ o: Int) -> UInt16 { o + 2 <= b.count ? UInt16(b[o]) | UInt16(b[o + 1]) << 8 : 0 }
        func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
            o + 4 <= b.count ? UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 : 0
        }
        func u64(_ b: [UInt8], _ o: Int) -> UInt64 { UInt64(u32(b, o)) | UInt64(u32(b, o + 4)) << 32 }

        /// Ancora, sequenza dei descrittori del volume, partizioni e insieme di file.
        func open() -> Bool {
            guard let anchor = readSector(256), u16(anchor, 0) == 2 else { return false }
            let length = Int(u32(anchor, 16)), start = UInt64(u32(anchor, 20))
            let count = min(max(length / UDFReader.sector, 1), 64)
            var supported = true
            for i in 0..<UInt64(count) {
                guard let b = readSector(start + i) else { break }
                let tag = u16(b, 0)
                if tag == 8 { break }
                if tag == 5 {
                    partitions[u16(b, 22)] = UInt64(u32(b, 188))
                } else if tag == 6 {
                    guard u32(b, 212) == UInt32(UDFReader.sector) else { return false }
                    revision = Int(u16(b, 240))
                    fileSet = (u32(b, 252), u16(b, 256))
                    var o = 440
                    for _ in 0..<min(Int(u32(b, 268)), 16) {
                        guard o + 2 <= b.count else { break }
                        let type = b[o], len = Int(b[o + 1])
                        if type == 1 {
                            maps.append(u16(b, o + 4))
                        } else {
                            supported = false  // virtuale, sparing o metadati
                        }
                        o += max(len, 2)
                    }
                }
            }
            return supported && !partitions.isEmpty && !maps.isEmpty && fileSet != nil
        }

        func sectorOf(block: UInt32, part: UInt16) -> UInt64? {
            guard Int(part) < maps.count, let start = partitions[maps[Int(part)]] else { return nil }
            return start + UInt64(block)
        }

        // MARK: Voci

        struct Node {
            var isDirectory = false
            var isSymlink = false
            var size: Int64 = 0
            var modified: Date?
            var data: [UInt8]?                 // allocazione incorporata
            var extents: [(length: Int, sector: UInt64)] = []
        }

        func timestamp(_ b: [UInt8], _ o: Int) -> Date? {
            guard o + 12 <= b.count else { return nil }
            var c = DateComponents()
            c.timeZone = TimeZone(identifier: "UTC")
            c.year = Int(Int16(bitPattern: u16(b, o + 2)))
            c.month = Int(b[o + 4]); c.day = Int(b[o + 5])
            c.hour = Int(b[o + 6]); c.minute = Int(b[o + 7]); c.second = Int(b[o + 8])
            guard (1...12).contains(c.month ?? 0), (1...31).contains(c.day ?? 0), (1970...2200).contains(c.year ?? 0) else { return nil }
            return Calendar(identifier: .gregorian).date(from: c)
        }

        /// File entry (261) o extended file entry (266) all'indirizzo dato.
        func node(block: UInt32, part: UInt16, wantExtents: Bool) -> Node? {
            guard let at = sectorOf(block: block, part: part), var b = readSector(at) else { return nil }
            let tag = u16(b, 0)
            guard tag == 261 || tag == 266 else { return nil }
            let extended = tag == 266
            let eaLen = Int(u32(b, extended ? 208 : 168)), adLen = Int(u32(b, extended ? 212 : 172))
            let adStart = (extended ? 216 : 176) + eaLen
            if adStart + adLen > b.count, wantExtents {
                let total = (adStart + adLen + UDFReader.sector - 1) / UDFReader.sector * UDFReader.sector
                guard let more = read(offset: at * UInt64(UDFReader.sector), length: total) else { return nil }
                b = more
            }
            var n = Node()
            let fileType = b[27]
            n.isDirectory = fileType == 4
            n.isSymlink = fileType == 12
            n.size = Int64(clamping: u64(b, 56))
            n.modified = timestamp(b, extended ? 92 : 84)
            guard wantExtents else { return n }
            let kind = Int(u16(b, 34) & 7)
            guard adStart + adLen <= b.count else { return n }
            if kind == 3 { return n }
            if kind == 2 {
                n.data = Array(b[adStart..<adStart + adLen])
            } else {
                appendExtents(from: Array(b[adStart..<adStart + adLen]), long: kind == 1, part: part, into: &n, depth: 0)
            }
            return n
        }

        func appendExtents(from ad: [UInt8], long: Bool, part: UInt16, into n: inout Node, depth: Int) {
            let step = long ? 16 : 8
            var o = 0
            while o + step <= ad.count {
                let raw = u32(ad, o)
                let length = Int(raw & 0x3FFF_FFFF), type = raw >> 30
                let block = u32(ad, o + 4)
                let partRef = long ? u16(ad, o + 8) : part
                if length == 0 { break }
                if type == 3 {
                    // Continuazione: un descrittore (258) con altre allocazioni.
                    guard depth < 8, let at = sectorOf(block: block, part: partRef), let aed = read(offset: at * UInt64(UDFReader.sector), length: max(length, UDFReader.sector)),
                          u16(aed, 0) == 258 else { return }
                    let l = Int(u32(aed, 20))
                    guard 24 + l <= aed.count else { return }
                    appendExtents(from: Array(aed[24..<24 + l]), long: long, part: part, into: &n, depth: depth + 1)
                } else if type == 0, let at = sectorOf(block: block, part: partRef) {
                    n.extents.append((length, at))
                }
                o += step
            }
        }

        /// Contenuto di una directory: i descrittori dei nomi, uno dopo l'altro.
        func directoryData(_ n: Node) -> [UInt8]? {
            if let d = n.data { return d }
            var out = [UInt8]()
            let wanted = Int(min(n.size, 16 * 1024 * 1024))
            for e in n.extents {
                guard out.count < wanted else { break }
                let take = min(e.length, wanted - out.count)
                guard let chunk = read(offset: e.sector * UInt64(UDFReader.sector), length: take) else { return nil }
                out += chunk
            }
            return out
        }

        func name(_ d: [UInt8], _ o: Int, _ len: Int) -> String? {
            guard len > 0, o + len <= d.count else { return nil }
            let comp = d[o]
            let body = Array(d[(o + 1)..<(o + len)])
            if comp == 16 {
                var units = [UInt16]()
                var i = 0
                while i + 1 < body.count { units.append(UInt16(body[i]) << 8 | UInt16(body[i + 1])); i += 2 }
                return String(decoding: units, as: UTF16.self)
            }
            return String(body.map { Character(UnicodeScalar($0)) })   // 8 bit: Latin-1
        }

        // MARK: Elenco

        func list(maxEntries: Int) -> Result? {
            guard let fs = fileSet, let at = sectorOf(block: fs.block, part: fs.part), let fsd = readSector(at), u16(fsd, 0) == 256 else { return nil }
            // Directory radice: long_ad a 400 (lunghezza, blocco, partizione).
            let rootBlock = u32(fsd, 404), rootPart = u16(fsd, 408)
            guard let root = node(block: rootBlock, part: rootPart, wantExtents: true), root.isDirectory else { return nil }
            var result = Result(revision: "UDF \(revision >> 8).\(String(format: "%02x", revision & 0xFF))", entries: [], totalCount: 0, totalSize: 0, truncated: false)
            walk(root, prefix: "", depth: 0, limit: maxEntries, into: &result)
            return result
        }

        func walk(_ dir: Node, prefix: String, depth: Int, limit: Int, into result: inout Result) {
            guard depth < 48, result.totalCount < UDFReader.hardLimit, let d = directoryData(dir) else {
                if result.totalCount >= UDFReader.hardLimit { result.truncated = true }
                return
            }
            var o = 0
            while o + 38 <= d.count {
                guard u16(d, o) == 257 else { break }
                let chars = d[o + 18], nameLen = Int(d[o + 19])
                let block = u32(d, o + 24), part = u16(d, o + 28)
                let iuLen = Int(u16(d, o + 36))
                let nameAt = o + 38 + iuLen
                let next = (38 + iuLen + nameLen + 3) & ~3
                defer { o += Swift.max(next, 4) }
                if chars & 0x04 != 0 || chars & 0x08 != 0 { continue }   // cancellata o «genitore»
                guard let entryName = name(d, nameAt, nameLen), !entryName.isEmpty,
                      let n = node(block: block, part: part, wantExtents: true) else { continue }
                let path = prefix.isEmpty ? entryName : prefix + "/" + entryName
                result.totalCount += 1
                if !n.isDirectory { result.totalSize += n.size }
                if result.entries.count < limit {
                    result.entries.append(Entry(path: path, size: n.isDirectory ? 0 : n.size, modified: n.modified, isDirectory: n.isDirectory))
                } else {
                    result.truncated = true
                }
                if n.isDirectory { walk(n, prefix: path, depth: depth + 1, limit: limit, into: &result) }
                if result.totalCount >= UDFReader.hardLimit { result.truncated = true; return }
            }
        }
    }
}
