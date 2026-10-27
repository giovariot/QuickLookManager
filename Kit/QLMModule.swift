import Foundation

/// I moduli di QuickLook Manager. Ogni modulo è un gruppo di formati con le sue impostazioni.
public enum QLMModule: String, CaseIterable, Identifiable, Codable, Sendable {
    case text, apps, archives, video, raw, models, eps, pkg

    public var id: String { rawValue }

    /// `true` se il modulo esiste già; gli altri compaiono nell'elenco ma restano spenti.
    public var isImplemented: Bool {
        switch self {
        case .text, .apps, .archives, .raw, .models, .eps, .video, .pkg: true
        }
    }

    public var title: String {
        switch self {
        case .text: String(localized: "Testo e codice", bundle: QLMBundle.framework)
        case .apps: String(localized: "App e pacchetti", bundle: QLMBundle.framework)
        case .archives: String(localized: "Archivi", bundle: QLMBundle.framework)
        case .video: String(localized: "Video", bundle: QLMBundle.framework)
        case .raw: String(localized: "Foto RAW", bundle: QLMBundle.framework)
        case .models: String(localized: "Modelli 3D", bundle: QLMBundle.framework)
        case .eps: String(localized: "EPS", bundle: QLMBundle.framework)
        case .pkg: String(localized: "Pacchetti PKG", bundle: QLMBundle.framework)
        }
    }

    public var summary: String {
        switch self {
        case .text: String(localized: "Codice con evidenziazione, JSON, YAML, property list, Markdown e altri linguaggi di marcatura.", bundle: QLMBundle.framework)
        case .apps: String(localized: "Informazioni su app macOS, iOS, Android, Windows, Flatpak e programmi dei vecchi Mac: firma, entitlement, architetture.", bundle: QLMBundle.framework)
        case .archives: String(localized: "Elenco del contenuto dei file compressi: ZIP, 7z, RAR, tar e altri formati letti da libarchive.", bundle: QLMBundle.framework)
        case .video: String(localized: "Lettore integrato (ffmpeg) per i video che macOS non conosce, come MKV, WebM, AVI, WMV e FLV: parte da solo e si ferma quando chiudi la finestra.", bundle: QLMBundle.framework)
        case .raw: String(localized: "Anteprima e miniature delle foto RAW, usando l'immagine incorporata nel file, letta con LibRaw.", bundle: QLMBundle.framework)
        case .models: String(localized: "Anteprima 3D interattiva e miniature dei file 3MF, con SceneKit.", bundle: QLMBundle.framework)
        case .pkg: String(localized: "Pacchetti di installazione: in alto identificatore, versione, script e firma; in basso l'elenco dei file che installa, senza scompattarli.", bundle: QLMBundle.framework)
        case .eps: String(localized: "Anteprima e miniature dei file EPS: l'immagine incorporata o, se manca, il disegno reso con Ghostscript.", bundle: QLMBundle.framework)
        }
    }

    /// Simbolo SF Symbols.
    public var symbol: String {
        switch self {
        case .text: "doc.plaintext"
        case .apps: "app.badge"
        case .archives: "archivebox"
        case .video: "film"
        case .raw: "camera.aperture"
        case .models: "cube"
        case .eps: "pencil.and.outline"
        case .pkg: "shippingbox"
        }
    }
}
