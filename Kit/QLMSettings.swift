import Foundation

/// Impostazioni del gestore: quali moduli sono attivi e come si presentano.
/// Le scrive l'app, le legge l'estensione (in sandbox, sola lettura).
public struct QLMSettings: Codable, Equatable, Sendable {
    /// Moduli spenti dall'utente. Un modulo non elencato è acceso.
    public var disabled: Set<QLMModule> = []
    /// Stile del pannello del modulo «App e pacchetti»: `centrato`, `apparency`, `originale`.
    public var appsPanelStyle = "centrato"
    public var raw = Raw()
    public var eps = EPS()
    public var archives = Archives()
    public var video = Video()

    public init() {}

    /// Foto RAW.
    public struct Raw: Codable, Equatable, Sendable {
        /// Mostra marca, modello, obiettivo e dati di scatto sotto la foto.
        public var showInfo = true
        /// Se il file non ha un'anteprima incorporata, sviluppa il RAW a mezza risoluzione (più lento).
        public var renderIfMissing = true
        public init() {}
        enum CodingKeys: CodingKey { case showInfo, renderIfMissing }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            showInfo = try c.decodeIfPresent(Bool.self, forKey: .showInfo) ?? showInfo
            renderIfMissing = try c.decodeIfPresent(Bool.self, forKey: .renderIfMissing) ?? renderIfMissing
        }
    }

    /// File EPS.
    public struct EPS: Codable, Equatable, Sendable {
        /// Preferisce l'anteprima incorporata nel file (veloce) a quella resa con Ghostscript (fedele).
        public var preferEmbeddedPreview = true
        /// Risoluzione di resa con Ghostscript, in punti per pollice.
        public var resolution = 144
        public init() {}
        enum CodingKeys: CodingKey { case preferEmbeddedPreview, resolution }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            preferEmbeddedPreview = try c.decodeIfPresent(Bool.self, forKey: .preferEmbeddedPreview) ?? preferEmbeddedPreview
            resolution = try c.decodeIfPresent(Int.self, forKey: .resolution) ?? resolution
        }
    }

    /// Video.
    public struct Video: Codable, Equatable, Sendable {
        /// Il filmato parte da solo quando si apre l'anteprima.
        public var autoplay = true
        /// Punto del filmato (0…1) da cui si prende la miniatura.
        public var thumbnailFraction = 0.25
        public init() {}
        enum CodingKeys: CodingKey { case autoplay, thumbnailFraction }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            autoplay = try c.decodeIfPresent(Bool.self, forKey: .autoplay) ?? autoplay
            thumbnailFraction = try c.decodeIfPresent(Double.self, forKey: .thumbnailFraction) ?? thumbnailFraction
        }
    }

    /// Archivi.
    public struct Archives: Codable, Equatable, Sendable {
        /// Quante voci elencare al massimo (gli archivi enormi si fermano lì).
        public var maxEntries = 5000
        public init() {}
        enum CodingKeys: CodingKey { case maxEntries }
        public init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            maxEntries = try c.decodeIfPresent(Int.self, forKey: .maxEntries) ?? maxEntries
        }
    }

    public func isEnabled(_ module: QLMModule) -> Bool {
        module.isImplemented && !disabled.contains(module)
    }

    public mutating func setEnabled(_ on: Bool, for module: QLMModule) {
        if on { disabled.remove(module) } else { disabled.insert(module) }
    }

    enum CodingKeys: CodingKey { case disabled, appsPanelStyle, raw, eps, archives, video }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        disabled = try c.decodeIfPresent(Set<QLMModule>.self, forKey: .disabled) ?? disabled
        appsPanelStyle = try c.decodeIfPresent(String.self, forKey: .appsPanelStyle) ?? appsPanelStyle
        raw = try c.decodeIfPresent(Raw.self, forKey: .raw) ?? raw
        eps = try c.decodeIfPresent(EPS.self, forKey: .eps) ?? eps
        archives = try c.decodeIfPresent(Archives.self, forKey: .archives) ?? archives
        video = try c.decodeIfPresent(Video.self, forKey: .video) ?? video
    }

    public static var file: URL { QTLPaths.supportDirectory.appendingPathComponent("manager.json") }

    public static func load() -> QLMSettings {
        guard let data = try? Data(contentsOf: file),
              let value = try? JSONDecoder().decode(QLMSettings.self, from: data) else { return QLMSettings() }
        return value
    }

    public func save() {
        do {
            try FileManager.default.createDirectory(at: QTLPaths.supportDirectory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(self).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("QuickLook Manager: impossibile salvare le impostazioni: \(error)")
        }
    }
}
