import Foundation

public enum TextDecoding {
    public struct Result: Sendable {
        public var string: String
        public var encodingName: String
        public var truncated: Bool
    }

    /// Codifiche proposte nelle impostazioni (nome → codifica).
    public static let namedEncodings: [(name: String, label: String, encoding: String.Encoding)] = [
        ("utf-8", String(localized: "Unicode (UTF-8)", bundle: QTLPaths.bundle), .utf8),
        ("utf-16", String(localized: "Unicode (UTF-16)", bundle: QTLPaths.bundle), .utf16),
        ("windows-1252", String(localized: "Latin 1 (Windows)", bundle: QTLPaths.bundle), .windowsCP1252),
        ("iso-8859-1", String(localized: "Latin 1 (ISO)", bundle: QTLPaths.bundle), .isoLatin1),
        ("iso-8859-15", String(localized: "Latin 9 (ISO 8859-15)", bundle: QTLPaths.bundle), String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)))),
        ("macroman", String(localized: "Mac Roman", bundle: QTLPaths.bundle), .macOSRoman),
        ("cp437", String(localized: "DOS (CP437)", bundle: QTLPaths.bundle), cp437),
        ("cp850", String(localized: "DOS Latin 1 (CP850)", bundle: QTLPaths.bundle), String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatin1.rawValue)))),
        ("shift-jis", String(localized: "Giapponese (Shift JIS)", bundle: QTLPaths.bundle), .shiftJIS),
        ("gb18030", String(localized: "Cinese semplificato (GB 18030)", bundle: QTLPaths.bundle), String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))),
        ("big5", String(localized: "Cinese tradizionale (Big5)", bundle: QTLPaths.bundle), String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))),
        ("euc-kr", String(localized: "Coreano (EUC-KR)", bundle: QTLPaths.bundle), String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))),
        ("koi8-r", String(localized: "Cirillico (KOI8-R)", bundle: QTLPaths.bundle), String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)))),
        ("windows-1251", String(localized: "Cirillico (Windows)", bundle: QTLPaths.bundle), .windowsCP1251),
    ]

    public static let cp437 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))

    /// Legge al più `maxBytes` byte di un file e li decodifica.
    public static func read(url: URL, maxBytes: Int, preferred: String = "auto", legacyDOS: Bool = false) throws -> Result {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        let truncated = data.count > maxBytes
        return decode(truncated ? data.prefix(maxBytes) : data, preferred: preferred, legacyDOS: legacyDOS, truncated: truncated)
    }

    public static func decode(_ data: Data, preferred: String = "auto", legacyDOS: Bool = false, truncated: Bool = false) -> Result {
        func make(_ s: String, _ n: String) -> Result { Result(string: s, encodingName: n, truncated: truncated) }
        // BOM
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return make(s, "utf-8") }
        if data.starts(with: [0xFF, 0xFE, 0, 0]) || data.starts(with: [0, 0, 0xFE, 0xFF]), let s = String(data: data, encoding: .utf32) { return make(s, "utf-32") }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return make(s, "utf-16") }
        // scelta esplicita dell'utente
        if preferred != "auto", let e = namedEncodings.first(where: { $0.name == preferred }), let s = String(data: data, encoding: e.encoding) { return make(s, preferred) }
        // UTF-8 valido (tollerando un carattere troncato in fondo se il file è stato tagliato)
        if let s = String(data: data, encoding: .utf8) { return make(s, "utf-8") }
        if truncated {
            for cut in 1...3 where data.count > cut { if let s = String(data: data.dropLast(cut), encoding: .utf8) { return make(s, "utf-8") } }
        }
        // UTF-16 senza BOM: molti zeri alternati
        let sample = data.prefix(512)
        let zerosOdd = stride(from: 1, to: sample.count, by: 2).filter { sample[sample.startIndex + $0] == 0 }.count
        let zerosEven = stride(from: 0, to: sample.count, by: 2).filter { sample[sample.startIndex + $0] == 0 }.count
        if sample.count > 8, zerosOdd * 3 > sample.count / 2 || zerosEven * 3 > sample.count / 2, let s = String(data: data, encoding: zerosOdd > zerosEven ? .utf16LittleEndian : .utf16BigEndian) { return make(s, "utf-16") }
        // codifiche legacy
        if legacyDOS, let s = String(data: data, encoding: cp437) { return make(s, "cp437") }
        var converted: NSString?
        var lossy = ObjCBool(false)
        let enc = NSString.stringEncoding(for: data, encodingOptions: [.suggestedEncodingsKey: [String.Encoding.windowsCP1252.rawValue, String.Encoding.macOSRoman.rawValue], .useOnlySuggestedEncodingsKey: false], convertedString: &converted, usedLossyConversion: &lossy)
        if enc != 0, let converted { return make(converted as String, String.Encoding(rawValue: enc).description) }
        return make(String(decoding: data, as: UTF8.self), "utf-8")
    }
}
