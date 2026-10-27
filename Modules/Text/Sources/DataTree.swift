import Foundation
import JavaScriptCore

/// Albero di un documento JSON/YAML/plist, con l'ordine originale delle chiavi.
public final class DataNode {
    public enum Kind: String { case object, array, string, number, bool, null, date, data }
    public let key: String
    public let kind: Kind
    public let value: String          // valore mostrato (vuoto per i contenitori)
    public var children: [DataNode]
    public init(key: String, kind: Kind, value: String = "", children: [DataNode] = []) {
        self.key = key; self.kind = kind; self.value = value; self.children = children
    }
    public var isContainer: Bool { kind == .object || kind == .array }

    /// Descrizione del tipo, in italiano.
    public var typeLabel: String {
        switch kind {
        case .object: return String(localized: "Dizionario", bundle: QTLPaths.bundle)
        case .array: return String(localized: "Array", bundle: QTLPaths.bundle)
        case .string: return String(localized: "Stringa", bundle: QTLPaths.bundle)
        case .number: return String(localized: "Numero", bundle: QTLPaths.bundle)
        case .bool: return String(localized: "Booleano", bundle: QTLPaths.bundle)
        case .null: return String(localized: "Nullo", bundle: QTLPaths.bundle)
        case .date: return String(localized: "Data", bundle: QTLPaths.bundle)
        case .data: return String(localized: "Dati", bundle: QTLPaths.bundle)
        }
    }
    public var summary: String {
        switch kind {
        case .object: return String(localized: "\(children.count) chiavi", bundle: QTLPaths.bundle)
        case .array: return String(localized: "\(children.count) elementi", bundle: QTLPaths.bundle)
        case .null: return "null"
        default: return value
        }
    }
}

public enum DataParseError: Error, LocalizedError {
    case syntax(String)
    public var errorDescription: String? { if case .syntax(let s) = self { return s }; return nil }
}

public enum DataTree {
    // MARK: JSON (parser tollerante: commenti, virgole finali, JSON5 di base)

    public static func parseJSON(_ text: String) throws -> DataNode {
        var p = JSONParser(Array(text.unicodeScalars))
        p.skip()
        let node = try p.value(key: "")
        p.skip()
        if p.i < p.s.count {
            // JSON Lines: più valori di fila
            var nodes = [node]
            while p.i < p.s.count { nodes.append(try p.value(key: "[\(nodes.count)]")); p.skip() }
            return DataNode(key: "", kind: .array, children: nodes)
        }
        return node
    }

    struct JSONParser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        mutating func skip() {
            while i < s.count {
                let c = s[i]
                if c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{FEFF}" || c == "," && false { i += 1 }
                else if c == "/", i + 1 < s.count, s[i + 1] == "/" { while i < s.count, s[i] != "\n" { i += 1 } }
                else if c == "/", i + 1 < s.count, s[i + 1] == "*" { i += 2; while i + 1 < s.count, !(s[i] == "*" && s[i + 1] == "/") { i += 1 }; i += 2 }
                else { break }
            }
        }
        func err(_ m: String) -> DataParseError { .syntax(String(localized: "\(m) alla posizione \(i)", bundle: QTLPaths.bundle)) }

        mutating func value(key: String) throws -> DataNode {
            skip()
            guard i < s.count else { throw err(String(localized: "Fine inattesa", bundle: QTLPaths.bundle)) }
            switch s[i] {
            case "{":
                i += 1; var kids: [DataNode] = []
                while true {
                    skip()
                    guard i < s.count else { throw err(String(localized: "Oggetto non chiuso", bundle: QTLPaths.bundle)) }
                    if s[i] == "}" { i += 1; break }
                    if s[i] == "," { i += 1; continue }
                    let k: String
                    if s[i] == "\"" || s[i] == "'" { k = try string() } else { k = bare() }
                    skip()
                    guard i < s.count, s[i] == ":" else { throw err(String(localized: "Atteso «:»", bundle: QTLPaths.bundle)) }
                    i += 1
                    kids.append(try value(key: k))
                }
                return DataNode(key: key, kind: .object, children: kids)
            case "[":
                i += 1; var kids: [DataNode] = []
                while true {
                    skip()
                    guard i < s.count else { throw err(String(localized: "Array non chiuso", bundle: QTLPaths.bundle)) }
                    if s[i] == "]" { i += 1; break }
                    if s[i] == "," { i += 1; continue }
                    kids.append(try value(key: "[\(kids.count)]"))
                }
                return DataNode(key: key, kind: .array, children: kids)
            case "\"", "'":
                return DataNode(key: key, kind: .string, value: try string())
            default:
                let w = bare()
                if w.isEmpty { i += 1; throw err(String(localized: "Carattere inatteso", bundle: QTLPaths.bundle)) }
                switch w {
                case "true", "false": return DataNode(key: key, kind: .bool, value: w)
                case "null": return DataNode(key: key, kind: .null)
                default:
                    if Double(w) != nil || w == "NaN" || w.hasPrefix("0x") || w.hasSuffix("Infinity") { return DataNode(key: key, kind: .number, value: w) }
                    throw err(String(localized: "Valore non valido «\(w)»", bundle: QTLPaths.bundle))
                }
            }
        }

        mutating func bare() -> String {
            var out = String.UnicodeScalarView()
            while i < s.count {
                let c = s[i]
                if c == "," || c == ":" || c == "}" || c == "]" || c == " " || c == "\n" || c == "\t" || c == "\r" || c == "{" || c == "[" { break }
                out.append(c); i += 1
            }
            return String(out)
        }

        mutating func string() throws -> String {
            let q = s[i]; i += 1
            var out = String.UnicodeScalarView()
            while i < s.count, s[i] != q {
                if s[i] == "\\", i + 1 < s.count {
                    i += 1
                    switch s[i] {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "b": out.append("\u{8}")
                    case "f": out.append("\u{C}")
                    case "u":
                        var hex = ""
                        var j = i + 1
                        while j < s.count, j <= i + 4 { hex.unicodeScalars.append(s[j]); j += 1 }
                        if let v = UInt32(hex, radix: 16) {
                            i += 4
                            if (0xD800..<0xDC00).contains(v), i + 6 < s.count, s[i + 1] == "\\", s[i + 2] == "u" {
                                var hex2 = ""; for k in (i + 3)...(i + 6) { hex2.unicodeScalars.append(s[k]) }
                                if let lo = UInt32(hex2, radix: 16), (0xDC00..<0xE000).contains(lo), let u = Unicode.Scalar(0x10000 + ((v - 0xD800) << 10) + (lo - 0xDC00)) { out.append(u); i += 6 }
                            } else if let u = Unicode.Scalar(v) { out.append(u) }
                        }
                    default: out.append(s[i])
                    }
                    i += 1
                } else { out.append(s[i]); i += 1 }
            }
            guard i < s.count else { throw err(String(localized: "Stringa non chiusa", bundle: QTLPaths.bundle)) }
            i += 1
            return String(out)
        }
    }

    // MARK: YAML (js-yaml in JavaScriptCore)

    private static let yamlQueue = DispatchQueue(label: "quicktextlook.yaml")
    nonisolated(unsafe) private static var yamlContext: JSContext?

    /// Un documento YAML (se ce ne sono più d'uno, un array di documenti).
    public static func parseYAML(_ text: String) throws -> DataNode {
        let json: String = try yamlQueue.sync {
            if yamlContext == nil {
                let src = try String(contentsOf: QTLPaths.webResources.appendingPathComponent("yaml.js"), encoding: .utf8)
                let c = JSContext()!
                c.evaluateScript("var globalThis = this;")
                c.evaluateScript(src)
                yamlContext = c
            }
            let c = yamlContext!
            c.exception = nil
            guard let fn = c.evaluateScript("QTLYaml.parse") else { throw DataParseError.syntax("js-yaml non disponibile") }
            let r = fn.call(withArguments: [text])
            if let e = c.exception {
                c.exception = nil
                let msg = e.objectForKeyedSubscript("message")?.toString() ?? "errore"
                throw DataParseError.syntax(msg)
            }
            guard let r, let s = r.toString() else { throw DataParseError.syntax("risposta vuota") }
            return s
        }
        guard let data = json.data(using: .utf8), let docs = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DataParseError.syntax("risposta non valida")
        }
        func conv(_ d: [String: Any], key: String) -> DataNode {
            switch d["t"] as? String {
            case "o":
                let pairs = d["v"] as? [[Any]] ?? []
                return DataNode(key: key, kind: .object, children: pairs.compactMap { p in
                    guard p.count == 2, let k = p[0] as? String, let v = p[1] as? [String: Any] else { return nil }
                    return conv(v, key: k)
                })
            case "a":
                let items = d["v"] as? [[String: Any]] ?? []
                return DataNode(key: key, kind: .array, children: items.enumerated().map { conv($1, key: "[\($0)]") })
            case "b": return DataNode(key: key, kind: .bool, value: (d["v"] as? Bool ?? false) ? "true" : "false")
            case "d": return DataNode(key: key, kind: .number, value: d["v"] as? String ?? "")
            case "n": return DataNode(key: key, kind: .null)
            default: return DataNode(key: key, kind: .string, value: d["v"] as? String ?? "")
            }
        }
        if docs.count == 1 { return conv(docs[0], key: "") }
        return DataNode(key: "", kind: .array, children: docs.enumerated().map { conv($1, key: String(localized: "Documento \($0 + 1)", bundle: QTLPaths.bundle)) })
    }

    // MARK: Property list

    /// Legge una plist (XML, binaria o vecchio formato testuale).
    public static func parsePlist(_ data: Data) throws -> DataNode {
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        func conv(_ v: Any, key: String) -> DataNode {
            switch v {
            case let d as [String: Any]: return DataNode(key: key, kind: .object, children: d.keys.sorted().map { conv(d[$0]!, key: $0) })
            case let a as [Any]: return DataNode(key: key, kind: .array, children: a.enumerated().map { conv($1, key: "[\($0)]") })
            case let s as String: return DataNode(key: key, kind: .string, value: s)
            case let date as Date: return DataNode(key: key, kind: .date, value: date.formatted(.iso8601))
            case let d as Data: return DataNode(key: key, kind: .data, value: String(localized: "\(d.count) byte", bundle: QTLPaths.bundle))
            case let n as NSNumber:
                if CFGetTypeID(n) == CFBooleanGetTypeID() { return DataNode(key: key, kind: .bool, value: n.boolValue ? "true" : "false") }
                return DataNode(key: key, kind: .number, value: n.stringValue)
            default: return DataNode(key: key, kind: .string, value: String(describing: v))
            }
        }
        return conv(obj, key: "")
    }

    /// Testo XML per le plist binarie (così l'origine è sempre leggibile).
    public static func xmlText(ofPlist data: Data) -> String? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let xml = try? PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0) else { return nil }
        return String(data: xml, encoding: .utf8)
    }
}
