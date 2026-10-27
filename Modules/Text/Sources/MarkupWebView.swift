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
    public func show(kind: String, source: String, settings: QTLSettings.Markdown, flavor: String) async throws {
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
