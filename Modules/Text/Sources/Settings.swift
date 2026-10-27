import Foundation

/// Impostazioni condivise tra app ed estensioni (file JSON in `QTLPaths.supportDirectory`).
public struct QTLSettings: Codable, Equatable, Sendable {
    public var code = Code()
    public var data = DataFormats()
    public var text = Text()
    public var markdown = Markdown()

    public init() {}

    public struct Code: Codable, Equatable, Sendable {
        public var lineNumbers = true
        public var wrapLines = false
        public var fontSize: Double = 12
        public var tabWidth = 4
        public var autoDetectLanguage = true
        public var maxKilobytes = 2048
        public init() {}
        enum CodingKeys: CodingKey { case lineNumbers, wrapLines, fontSize, tabWidth, autoDetectLanguage, maxKilobytes }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            lineNumbers = try c.decodeIfPresent(Bool.self, forKey: .lineNumbers) ?? lineNumbers
            wrapLines = try c.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? wrapLines
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
            tabWidth = try c.decodeIfPresent(Int.self, forKey: .tabWidth) ?? tabWidth
            autoDetectLanguage = try c.decodeIfPresent(Bool.self, forKey: .autoDetectLanguage) ?? autoDetectLanguage
            maxKilobytes = try c.decodeIfPresent(Int.self, forKey: .maxKilobytes) ?? maxKilobytes
        }
    }

    /// JSON, YAML e property list.
    public struct DataFormats: Codable, Equatable, Sendable {
        public enum Mode: String, Codable, CaseIterable, Sendable { case tree, source }
        public var startMode = Mode.tree
        public var expandLevels = 1
        public var showTypes = true
        public var plistAsTree = true
        public var maxKilobytes = 5120
        public init() {}
        enum CodingKeys: CodingKey { case startMode, expandLevels, showTypes, plistAsTree, maxKilobytes }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            startMode = try c.decodeIfPresent(Mode.self, forKey: .startMode) ?? startMode
            expandLevels = try c.decodeIfPresent(Int.self, forKey: .expandLevels) ?? expandLevels
            showTypes = try c.decodeIfPresent(Bool.self, forKey: .showTypes) ?? showTypes
            plistAsTree = try c.decodeIfPresent(Bool.self, forKey: .plistAsTree) ?? plistAsTree
            maxKilobytes = try c.decodeIfPresent(Int.self, forKey: .maxKilobytes) ?? maxKilobytes
        }
    }

    public struct Text: Codable, Equatable, Sendable {
        public enum FontStyle: String, Codable, CaseIterable, Sendable { case monospaced, proportional }
        public var fontStyle = FontStyle.monospaced
        public var fontSize: Double = 13
        public var wrapLines = true
        public var lineNumbers = false
        /// Nome della codifica, `auto` per il rilevamento.
        public var encoding = "auto"
        /// I file `.nfo`, `.diz`, `.ans` sono letti come CP437 se non sono UTF-8 valido.
        public var legacyDOSEncoding = true
        public var maxKilobytes = 2048
        public init() {}
        enum CodingKeys: CodingKey { case fontStyle, fontSize, wrapLines, lineNumbers, encoding, legacyDOSEncoding, maxKilobytes }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            fontStyle = try c.decodeIfPresent(FontStyle.self, forKey: .fontStyle) ?? fontStyle
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
            wrapLines = try c.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? wrapLines
            lineNumbers = try c.decodeIfPresent(Bool.self, forKey: .lineNumbers) ?? lineNumbers
            encoding = try c.decodeIfPresent(String.self, forKey: .encoding) ?? encoding
            legacyDOSEncoding = try c.decodeIfPresent(Bool.self, forKey: .legacyDOSEncoding) ?? legacyDOSEncoding
            maxKilobytes = try c.decodeIfPresent(Int.self, forKey: .maxKilobytes) ?? maxKilobytes
        }
    }

    public struct Markdown: Codable, Equatable, Sendable {
        /// `typora`, `gfm`, `commonmark`, `multimarkdown`.
        public var flavor = "typora"
        /// Identificatore del tema: uno integrato (`typora`, `github`, `claude-code`, `claude-chat`, `system`) oppure `custom:nomefile.css`.
        public var theme = "typora"
        public var fontSize: Double = 14
        /// Larghezza massima del testo in punti; 0 = tutta la finestra.
        public var maxWidth: Double = 860
        public var math = true
        public var diagrams = true
        public var renderOtherMarkup = true
        public init() {}
        enum CodingKeys: CodingKey { case flavor, theme, fontSize, maxWidth, math, diagrams, renderOtherMarkup }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            flavor = try c.decodeIfPresent(String.self, forKey: .flavor) ?? flavor
            theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? theme
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
            maxWidth = try c.decodeIfPresent(Double.self, forKey: .maxWidth) ?? maxWidth
            math = try c.decodeIfPresent(Bool.self, forKey: .math) ?? math
            diagrams = try c.decodeIfPresent(Bool.self, forKey: .diagrams) ?? diagrams
            renderOtherMarkup = try c.decodeIfPresent(Bool.self, forKey: .renderOtherMarkup) ?? renderOtherMarkup
        }
    }

    enum CodingKeys: CodingKey { case code, data, text, markdown }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(Code.self, forKey: .code) ?? code
        data = try c.decodeIfPresent(DataFormats.self, forKey: .data) ?? data
        text = try c.decodeIfPresent(Text.self, forKey: .text) ?? text
        markdown = try c.decodeIfPresent(Markdown.self, forKey: .markdown) ?? markdown
    }

    // MARK: Archiviazione

    /// Legge le impostazioni; se il file manca o è illeggibile restituisce i valori predefiniti.
    public static func load() -> QTLSettings {
        guard let data = try? Data(contentsOf: QTLPaths.settingsFile),
              let value = try? JSONDecoder().decode(QTLSettings.self, from: data) else { return QTLSettings() }
        return value
    }

    /// Scrive le impostazioni (solo l'app: le estensioni hanno accesso in sola lettura).
    public func save() {
        do {
            try FileManager.default.createDirectory(at: QTLPaths.supportDirectory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(self).write(to: QTLPaths.settingsFile, options: .atomic)
        } catch {
            NSLog("QuickTextLook: impossibile salvare le impostazioni: \(error)")
        }
    }
}
