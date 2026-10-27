import Compression
import Foundation

/// Lettore di archivi `xar`, il contenitore dei pacchetti `.pkg` «flat». L'indice (TOC) è un XML compresso con zlib; i dati
/// dei file stanno nello «heap» che lo segue.
final class XarArchive {
    struct Member {
        var path: String
        var isDirectory: Bool
        var offset: Int = 0
        var length: Int = 0
        var size: Int = 0
        var encoding: String = ""
    }

    struct SignatureInfo {
        var style: String
        var certificates: [Data]   // DER, dal firmatario alla radice
    }

    enum XarError: Error { case notXar, badHeader, badTOC }

    let url: URL
    private(set) var members: [Member] = []
    private(set) var signature: SignatureInfo?
    private(set) var tocXML = ""
    private let heapStart: Int
    private let handle: FileHandle

    init(url: URL) throws {
        self.url = url
        handle = try FileHandle(forReadingFrom: url)
        guard let head = try handle.read(upToCount: 28), head.count == 28 else { throw XarError.badHeader }
        guard head.prefix(4) == Data("xar!".utf8) else { throw XarError.notXar }
        func u16(_ o: Int) -> Int { Int(head[o]) << 8 | Int(head[o + 1]) }
        func u64(_ o: Int) -> Int { (0..<8).reduce(0) { $0 << 8 | Int(head[o + $1]) } }
        let headerSize = u16(4), compressed = u64(8), uncompressed = u64(16)
        guard compressed > 0, compressed < 512 << 20, uncompressed > 0, uncompressed < 1 << 30 else { throw XarError.badHeader }
        try handle.seek(toOffset: UInt64(headerSize))
        guard let packed = try handle.read(upToCount: compressed), packed.count == compressed,
              let xml = Self.inflateZlib(packed, expected: uncompressed) else { throw XarError.badTOC }
        heapStart = headerSize + compressed
        tocXML = String(decoding: xml, as: UTF8.self)
        let parser = TOCParser()
        let xmlParser = XMLParser(data: xml)
        xmlParser.delegate = parser
        xmlParser.parse()
        members = parser.members
        if !parser.certificates.isEmpty { signature = SignatureInfo(style: parser.signatureStyle, certificates: parser.certificates) }
    }

    deinit { try? handle.close() }

    func member(_ path: String) -> Member? { members.first { $0.path == path } }

    /// Il contenuto di un membro, già decompresso. `maxBytes` evita di caricare file enormi.
    func data(of member: Member, maxBytes: Int = 64 << 20) -> Data? {
        guard !member.isDirectory, member.length > 0, member.length <= maxBytes else { return nil }
        do {
            try handle.seek(toOffset: UInt64(heapStart + member.offset))
            guard let raw = try handle.read(upToCount: member.length), raw.count == member.length else { return nil }
            if member.encoding.contains("gzip") || member.encoding.contains("zlib") {
                return Self.inflateZlib(raw, expected: member.size)
            }
            return raw
        } catch { return nil }
    }

    /// zlib («78 9c…»): COMPRESSION_ZLIB di Apple vuole il flusso senza le due byte iniziali e senza la somma finale.
    static func inflateZlib(_ data: Data, expected: Int) -> Data? {
        guard data.count > 6 else { return nil }
        let body = data.dropFirst(2)
        let capacity = max(expected, 1) + 16
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst in
            body.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        out.count = n
        return out
    }
}

/// Legge l'XML dell'indice: i `<file>` annidati (con i loro `<data>`) e i certificati della firma.
private final class TOCParser: NSObject, XMLParserDelegate {
    var members: [XarArchive.Member] = []
    var certificates: [Data] = []
    var signatureStyle = ""

    private var stack: [String] = []
    private var names: [String] = []                   // i nomi dei `<file>` aperti
    private var pending: [XarArchive.Member] = []      // i membri aperti, dal più esterno
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String]) {
        stack.append(name)
        text = ""
        switch name {
        case "file": pending.append(XarArchive.Member(path: "", isDirectory: false)); names.append("")
        case "encoding" where parent(of: "data") && stack.count >= 3 && stack[stack.count - 3] == "file":
            if !pending.isEmpty { pending[pending.count - 1].encoding = attrs["style"] ?? "" }
        case "signature": signatureStyle = attrs["style"] ?? ""
        default: break
        }
    }

    private func parent(of name: String) -> Bool { stack.count >= 2 && stack[stack.count - 2] == name }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { stack.removeLast() }
        let inFile = stack.count >= 2 && stack[stack.count - 2] == "file"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "name" where inFile && !names.isEmpty: names[names.count - 1] = trimmed
        case "type" where inFile && !pending.isEmpty: pending[pending.count - 1].isDirectory = (trimmed == "directory")
        case "offset" where stack.count >= 3 && stack[stack.count - 2] == "data" && stack[stack.count - 3] == "file":
            if !pending.isEmpty { pending[pending.count - 1].offset = Int(trimmed) ?? 0 }
        case "length" where stack.count >= 3 && stack[stack.count - 2] == "data" && stack[stack.count - 3] == "file":
            if !pending.isEmpty { pending[pending.count - 1].length = Int(trimmed) ?? 0 }
        case "size" where stack.count >= 3 && stack[stack.count - 2] == "data" && stack[stack.count - 3] == "file":
            if !pending.isEmpty { pending[pending.count - 1].size = Int(trimmed) ?? 0 }
        case "X509Certificate":
            let b64 = trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
            if let der = Data(base64Encoded: b64) { certificates.append(der) }
        case "file":
            var m = pending.removeLast()
            let path = (names.filter { !$0.isEmpty }).joined(separator: "/")
            names.removeLast()
            m.path = path
            members.append(m)
        default: break
        }
    }
}
