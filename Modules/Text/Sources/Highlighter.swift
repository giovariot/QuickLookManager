import AppKit
import JavaScriptCore

/// Evidenziazione della sintassi: highlight.js eseguito con JavaScriptCore, risultato convertito in
/// `NSAttributedString` con colori semantici di sistema (seguono Chiaro/Scuro e Aumenta contrasto).
public final class Highlighter: @unchecked Sendable {
    public static let shared = Highlighter()

    private let queue = DispatchQueue(label: "quicktextlook.highlighter")
    private var context: JSContext?

    private func ctx() -> JSContext? {
        if let context { return context }
        guard let url = QTLPaths.webResources.appendingPathComponent("hljs.js") as URL?,
              let src = try? String(contentsOf: url, encoding: .utf8),
              let c = JSContext() else { return nil }
        c.exceptionHandler = { _, e in NSLog("QuickTextLook JS: \(String(describing: e))") }
        c.evaluateScript("var globalThis = this; var window = this;")
        c.evaluateScript(src)
        context = c
        return c
    }

    /// `true` se highlight.js conosce il linguaggio (nome o alias).
    public func knows(_ language: String) -> Bool {
        queue.sync { ctx()?.evaluateScript("!!hljs.getLanguage(\(Self.literal(language)))")?.toBool() ?? false }
    }

    /// HTML di highlight.js per il sorgente; `nil` se non riconosciuto.
    public func html(_ code: String, language: String?, autoDetect: Bool) -> (html: String, language: String)? {
        queue.sync {
            guard let c = ctx() else { return nil }
            let lit = Self.literal(code)
            let script: String
            if let language, c.evaluateScript("!!hljs.getLanguage(\(Self.literal(language)))").toBool() {
                script = "(function(){var r=hljs.highlight(\(lit),{language:\(Self.literal(language)),ignoreIllegals:true});return [r.value,r.language];})()"
            } else if autoDetect, code.utf8.count < 200_000 {
                script = "(function(){var r=hljs.highlightAuto(\(lit));if(!r.language||r.relevance<5)return null;return [r.value,r.language];})()"
            } else { return nil }
            guard let v = c.evaluateScript(script), v.isArray, let html = v.atIndex(0)?.toString(), let lang = v.atIndex(1)?.toString() else { return nil }
            return (html, lang)
        }
    }

    /// Sorgente evidenziato. Se il linguaggio non è noto restituisce il testo semplice.
    public func attributed(_ code: String, language: String?, font: NSFont, autoDetect: Bool = true) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        guard let result = html(code, language: language, autoDetect: autoDetect) else {
            return NSAttributedString(string: code, attributes: base)
        }
        return Self.convert(html: result.html, font: font)
    }

    // MARK: HTML di highlight.js → NSAttributedString

    static func convert(html: String, font: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var stack: [[NSAttributedString.Key: Any]] = [[.font: font, .foregroundColor: NSColor.labelColor]]
        var text = ""
        func flush() {
            guard !text.isEmpty else { return }
            out.append(NSAttributedString(string: text, attributes: stack.last!))
            text = ""
        }
        let scalars = Array(html.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let ch = scalars[i]
            if ch == "<" {
                var j = i + 1
                while j < scalars.count, scalars[j] != ">" { j += 1 }
                let tag = String(String.UnicodeScalarView(scalars[(i + 1)..<min(j, scalars.count)]))
                flush()
                if tag.hasPrefix("span") {
                    var attrs = stack.last!
                    if let r = tag.range(of: "class=\""), let e = tag[r.upperBound...].firstIndex(of: "\"") {
                        let classes = tag[r.upperBound..<e].split(separator: " ").map(String.init)
                        apply(classes: classes, to: &attrs, font: font)
                    }
                    stack.append(attrs)
                } else if tag == "/span", stack.count > 1 { stack.removeLast() }
                i = j + 1
            } else if ch == "&" {
                var j = i + 1
                while j < scalars.count, scalars[j] != ";", j - i < 10 { j += 1 }
                let ent = String(String.UnicodeScalarView(scalars[(i + 1)..<min(j, scalars.count)]))
                switch ent {
                case "amp": text += "&"; i = j + 1
                case "lt": text += "<"; i = j + 1
                case "gt": text += ">"; i = j + 1
                case "quot": text += "\""; i = j + 1
                case "#x27", "#39", "apos": text += "'"; i = j + 1
                default: text.unicodeScalars.append(ch); i += 1
                }
            } else { text.unicodeScalars.append(ch); i += 1 }
        }
        flush()
        return out
    }

    private static func apply(classes: [String], to attrs: inout [NSAttributedString.Key: Any], font: NSFont) {
        let names = classes.map { $0.hasPrefix("hljs-") ? String($0.dropFirst(5)) : $0 }
        let first = names.first ?? ""
        var color: NSColor?
        switch first {
        case "keyword", "selector-tag", "doctag", "meta-keyword": color = .systemPink
        case "built_in", "type", "class": color = .systemTeal
        case "string", "regexp", "meta-string", "template-string", "char": color = .systemRed
        case "number", "literal", "symbol", "bullet", "link": color = .systemPurple
        case "comment", "quote": color = .systemGreen
        case "title", "function", "section": color = .systemBlue
        case "attr", "attribute", "variable", "params", "property", "template-variable", "selector-attr", "selector-class", "selector-id", "selector-pseudo": color = .systemIndigo
        case "meta", "tag", "name", "subst", "formula": color = .systemOrange
        case "addition": color = .systemGreen
        case "deletion": color = .systemRed
        default: color = nil
        }
        // "title function_" / "title class_": sfumature
        if names.contains("class_") { color = .systemTeal }
        if names.contains("function_") { color = .systemBlue }
        if let color { attrs[.foregroundColor] = color }
        if first == "section" || first == "strong" {
            attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if first == "emphasis" {
            attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
    }

    private static func literal(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s], options: []), let j = String(data: d, encoding: .utf8) else { return "\"\"" }
        return String(j.dropFirst().dropLast())
    }
}
