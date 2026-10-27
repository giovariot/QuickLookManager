import AppKit

/// Disegno delle miniature: prime righe del file, con i colori della sintassi per codice, JSON, YAML e plist.
public enum Thumbnailer {
    /// Disegna in `rect` (coordinate flipped, origine in alto a sinistra). Restituisce `false` se il file non è gestito.
    public static func draw(url: URL, in rect: CGRect, settings: QTLSettings = .load()) -> Bool {
        let head = (try? FileHandle(forReadingFrom: url).read(upToCount: 8192)) ?? Data()
        let kind = FormatCatalog.kind(for: url, head: head)
        // le miniature sono sempre in aspetto Chiaro, come la carta
        guard let cg = NSGraphicsContext.current?.cgContext else { return false }
        var ok = false
        // contesto con origine in alto a sinistra, come il testo si aspetta
        cg.saveGState()
        cg.translateBy(x: 0, y: rect.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            ok = render(url: url, kind: kind, rect: rect, settings: settings)
        }
        NSGraphicsContext.restoreGraphicsState()
        cg.restoreGState()
        return ok
    }

    private static func render(url: URL, kind: PreviewKind, rect: CGRect, settings: QTLSettings) -> Bool {
        if case .binary = kind { return false }
        guard let r = try? TextDecoding.read(url: url, maxBytes: 24 * 1024, legacyDOS: { if case .text(let d) = kind { return d } else { return false } }()) else { return false }
        // righe iniziali: sono sufficienti per riempire qualunque miniatura
        let lines = r.string.split(separator: "\n", maxSplits: 60, omittingEmptySubsequences: false).prefix(60)
        let text = lines.joined(separator: "\n")
        let columns: CGFloat = 46
        let size = max(5, rect.width / columns * 1.55)
        let mono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let attr: NSAttributedString
        switch kind {
        case .code(let lang): attr = Highlighter.shared.attributed(text, language: lang, font: mono, autoDetect: false)
        case .json: attr = Highlighter.shared.attributed(text, language: "json", font: mono, autoDetect: false)
        case .yaml: attr = Highlighter.shared.attributed(text, language: "yaml", font: mono, autoDetect: false)
        case .plist: attr = Highlighter.shared.attributed(text, language: "xml", font: mono, autoDetect: false)
        case .markdown, .markup: attr = markdownLike(text, size: size)
        case .man: attr = NSAttributedString(string: text, attributes: [.font: mono, .foregroundColor: NSColor.labelColor])
        case .text(let dos):
            let f: NSFont = (dos || settings.text.fontStyle == .monospaced) ? mono : .systemFont(ofSize: size)
            attr = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: NSColor.labelColor])
        case .binary: return false
        }
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        let inset = rect.width * 0.07
        let area = rect.insetBy(dx: inset, dy: inset)
        NSGraphicsContext.current?.cgContext.saveGState()
        NSBezierPath(rect: area).addClip()
        // il testo non va a capo: righe lunghe tagliate come in un'anteprima di pagina
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byClipping
        let m = NSMutableAttributedString(attributedString: attr)
        m.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: m.length))
        m.draw(with: NSRect(x: area.minX, y: area.minY, width: area.width, height: area.height + 4000), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.current?.cgContext.restoreGState()
        return true
    }

    private static func markdownLike(_ text: String, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(line)
            var font = NSFont.systemFont(ofSize: size)
            var color = NSColor.labelColor
            if let m = s.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let level = s[m].filter { $0 == "#" }.count
                s = String(s[m.upperBound...])
                font = .systemFont(ofSize: size, weight: .bold)
            } else if s.hasPrefix("```") || s.hasPrefix("    ") {
                font = .monospacedSystemFont(ofSize: size, weight: .regular); color = .secondaryLabelColor
            } else if s.hasPrefix(">") { color = .secondaryLabelColor }
            else if s.hasPrefix("- ") || s.hasPrefix("* ") { s = "• " + s.dropFirst(2) }
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color]))
        }
        return out
    }
}
