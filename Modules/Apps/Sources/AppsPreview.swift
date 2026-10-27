import AppKit
import WebKit
import os

private let log = OSLog(subsystem: "com.giovariot.QuickLookManager", category: "apps")

/// Punto d'ingresso del modulo «App e pacchetti»: anteprima HTML e miniatura con l'icona.
public enum AppsPreview {
    /// Il file dell'utente (Documenti) vince su tutto, poi il modello dello stile scelto, poi quello predefinito.
    private static func resource(_ name: String, _ ext: String) throws -> String {
        if let user = URL.UserModDir?.appendingPathComponent(name + "." + ext), user.exists() {
            return try String(contentsOf: user, encoding: .utf8)
        }
        let bundle = QLMBundle.appsResources
        let stile = StilePannello.scelto
        if !stile.suffisso.isEmpty,
           let url = bundle.url(forResource: name + stile.suffisso, withExtension: ext),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw RuntimeError("manca \(name).\(ext) nelle risorse del modulo")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Genera la pagina HTML dell'anteprima. Lancia un errore se il file non è un pacchetto riconosciuto.
    public static func html(for url: URL) throws -> String {
        let meta = MetaInfo(url)
        return try PreviewGenerator(meta).generate(
            template: try resource("template", "html"),
            css: try resource("style", "css"))
    }

    @MainActor
    public static func makeView(for url: URL) throws -> NSView {
        let html = try html(for: url)
        let web = WebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        web.autoresizingMask = [.width, .height]
        web.mainFrame.loadHTMLString(html, baseURL: nil)
        return web
    }

    public static func drawThumbnail(url: URL, in rect: CGRect) -> Bool {
        let meta = MetaInfo(url)
        let image = AppIcon(meta).extractImageForThumbnail().withRoundCorners()
        image.draw(in: rect)
        return true
    }
}
