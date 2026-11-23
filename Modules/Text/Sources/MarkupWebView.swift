import AppKit
import WebKit

/// Anteprima Markdown e altri linguaggi di markup: `WKWebView` di sistema con la pagina inclusa nel framework.
@MainActor
public final class MarkupWebView: NSObject, WKNavigationDelegate {
    public let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?
    private var pendingMount: (() async throws -> Void)?

    public override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.suppressesIncrementalRendering = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .textBackgroundColor
    }

    /// Carica la pagina e mostra `source` interpretato come `kind` (`markdown`, `textile`, `asciidoc`, `creole`, `rst`, `bbcode`, `html`).
    public func show(kind: String, source: String, settings: QTLSettings.Markdown, flavor: String, documentDirectory: URL? = nil) async throws {
        let dir = QTLPaths.webResources
        try await load(dir.appendingPathComponent("preview.html"), readAccess: dir)
        let opts: [String: Any] = [
            "flavor": flavor,
            "math": settings.math,
            "diagrams": settings.diagrams,
            "fontSize": settings.fontSize,
            "maxWidth": settings.maxWidth,
            "themeCSS": Self.themeCSS(settings.theme),
            "userCSS": Self.userCSS(settings.theme),
        ]
        _ = try await webView.callAsyncJavaScript("return await qtlMount(kind, source, opts);",
                                                  arguments: ["kind": kind, "source": source, "opts": opts],
                                                  in: nil, contentWorld: .page)
        if let documentDirectory { await inlineRelativeImages(in: documentDirectory) }
    }

    /// Le immagini con percorso relativo stanno accanto al documento. A leggerle non puo' essere WebKit (il suo
    /// processo di rete ha un sandbox suo, senza il permesso dell'estensione): le legge l'estensione e le passa
    /// alla pagina come `data:`. Tetto sul totale, per non gonfiare la memoria con documenti pieni di foto.
    private func inlineRelativeImages(in directory: URL) async {
        let script = "return [...document.querySelectorAll('img')].map(i => i.getAttribute('src')).filter(s => s && !/^[a-z][a-z0-9+.-]*:/i.test(s) && !s.startsWith('//'));"
        guard let srcs = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String] else { return }
        var map: [String: String] = [:]
        var budget = 64 * 1024 * 1024
        let root = directory.standardizedFileURL
        for src in Set(srcs) {
            let clean = src.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
            let name = clean.removingPercentEncoding ?? clean
            let file = URL(fileURLWithPath: name, relativeTo: root).standardizedFileURL
            let mime: String
            switch file.pathExtension.lowercased() {
            case "jpg", "jpeg": mime = "image/jpeg"
            case "png": mime = "image/png"
            case "gif": mime = "image/gif"
            case "webp": mime = "image/webp"
            case "svg": mime = "image/svg+xml"
            case "bmp": mime = "image/bmp"
            case "tif", "tiff": mime = "image/tiff"
            case "heic": mime = "image/heic"
            default: continue
            }
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count <= budget else { continue }
            budget -= data.count
            map[src] = "data:\(mime);base64," + data.base64EncodedString()
        }
        guard !map.isEmpty else { return }
        _ = try? await webView.callAsyncJavaScript(
            "for (const img of document.querySelectorAll('img')) { const d = map[img.getAttribute('src')]; if (d) img.src = d; }",
            arguments: ["map": map], in: nil, contentWorld: .page)
    }

    private func load(_ url: URL, readAccess: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else { decisionHandler(.allow); return }
        if url.scheme == "file", url.fragment != nil { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
    }

    // MARK: Temi

    public static let builtInThemes: [(id: String, label: String)] = [
        ("system", String(localized: "Sistema", bundle: QTLPaths.bundle)),
        ("typora", "Typora"),
        ("github", "GitHub"),
        ("claude-code", "Claude Code"),
        ("claude-chat", "Claude"),
    ]

    static func themeCSS(_ id: String) -> String {
        let name = id.hasPrefix("custom:") ? "system" : id
        return (try? String(contentsOf: QTLPaths.webResources.appendingPathComponent("themes/\(name).css"), encoding: .utf8)) ?? ""
    }

    static func userCSS(_ id: String) -> String {
        guard id.hasPrefix("custom:") else { return "" }
        let file = String(id.dropFirst(7))
        guard !file.contains("/") else { return "" }
        let url = QTLPaths.themesDirectory.appendingPathComponent(file)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Fogli di stile importati dall'utente.
    public static func customThemes() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: QTLPaths.themesDirectory.path)) ?? []
        return files.filter { $0.lowercased().hasSuffix(".css") }.sorted()
    }
}
