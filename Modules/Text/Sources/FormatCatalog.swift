import Foundation

/// Come un file va mostrato.
public enum PreviewKind: Equatable, Sendable {
    case code(language: String?)      // evidenziazione con highlight.js
    case text(legacyDOS: Bool)        // testo semplice (CP437 per .nfo & co.)
    case json
    case yaml
    case plist
    case markdown(flavor: String?)    // nil = quello delle impostazioni
    case markup(MarkupKind)
    case man
    case binary                       // non gestito
}

public enum MarkupKind: String, Sendable { case textile, asciidoc, creole, rst, bbcode }

public enum FormatCatalog {
    // File senza estensione che sono testo.
    static let plainNames: Set<String> = [
        "readme", "license", "licence", "changelog", "changes", "authors", "copying", "notice", "contributing",
        "todo", "install", "history", "news", "thanks", "manifest", "version", "credits", "maintainers",
        "owners", "codeowners", "patents", "copyright", "bugs", "hacking", "faq", "notes", "release",
    ]
    static let codeNames: [String: String] = [
        "makefile": "makefile", "gnumakefile": "makefile", "dockerfile": "dockerfile", "cmakelists.txt": "cmake",
        "gemfile": "ruby", "rakefile": "ruby", "podfile": "ruby", "fastfile": "ruby", "vagrantfile": "ruby",
        "brewfile": "ruby", "jenkinsfile": "groovy", "procfile": "yaml", "justfile": "makefile",
        ".bashrc": "bash", ".bash_profile": "bash", ".bash_aliases": "bash", ".profile": "bash", ".zshrc": "bash",
        ".zprofile": "bash", ".zshenv": "bash", ".zlogin": "bash", ".zlogout": "bash", ".kshrc": "bash",
        ".gitconfig": "ini", ".gitignore": "plaintext", ".gitattributes": "plaintext", ".gitmodules": "ini",
        ".editorconfig": "ini", ".npmrc": "ini", ".dockerignore": "plaintext", ".env": "ini", ".htaccess": "apache",
        "hosts": "plaintext", "fstab": "plaintext", "crontab": "bash", "sudoers": "plaintext",
        "package.swift": "swift", "podspec": "ruby", "cartfile": "plaintext", "go.mod": "plaintext", "go.sum": "plaintext",
    ]
    static let textExts: Set<String> = [
        "txt", "text", "tx", "nfo", "diz", "info", "inf", "1st", "log", "out", "asc", "me", "lst", "ans", "asi",
        "srt", "sub", "vtt", "ssa", "ass", "sbv", "lrc", "pub", "csv", "tsv", "list", "rtx", "readme", "ascii",
        "sig", "gitkeep", "mod", "sum", "work", "in",
    ]
    static let dosExts: Set<String> = ["nfo", "diz", "ans", "asi", "1st", "ascii"]
    static let jsonExts: Set<String> = ["json", "jsonc", "json5", "geojson", "webmanifest", "har", "ipynb", "topojson", "jsonld", "mcmeta", "babelrc", "eslintrc", "avsc", "gltf", "sublime-settings", "code-workspace"]
    static let yamlExts: Set<String> = ["yaml", "yml"]
    static let plistExts: Set<String> = ["plist", "entitlements", "mobileconfig", "webloc", "xcprivacy", "tmtheme", "xcsettings", "ichat", "scriptsuite", "scriptterminology"]
    static let markdownExts: [String: String?] = [
        "md": nil, "markdown": nil, "mdown": nil, "mkd": nil, "mkdn": nil, "mdwn": nil, "mdtxt": nil, "mdtext": nil, "mkdown": nil,
        "text.md": nil, "rmd": nil, "qmd": nil, "pendown": nil, "pdn": nil, "mdx": nil, "livemd": nil,
        "mmd": "multimarkdown", "multimarkdown": "multimarkdown", "mmdoc": "multimarkdown",
        "gfm": "gfm", "commonmark": "commonmark", "cm": "commonmark",
    ]
    static let markupExts: [String: MarkupKind] = [
        "textile": .textile, "adoc": .asciidoc, "asciidoc": .asciidoc, "asc.adoc": .asciidoc,
        "creole": .creole, "rst": .rst, "rest": .rst, "bbcode": .bbcode, "bb": .bbcode,
    ]
    /// Estensioni dove highlight.js usa un nome diverso.
    static let languageOverrides: [String: String] = [
        "conf": "ini", "cfg": "ini", "cnf": "ini", "cf": "ini", "rc": "ini", "properties": "properties", "env": "ini", "config": "xml",
        "tf": "ini", "tfvars": "ini", "hcl": "ini", "vue": "xml", "plist": "xml", "storyboard": "xml", "xib": "xml",
        "strings": "properties", "xcconfig": "properties", "gradle": "groovy", "mk": "makefile", "make": "makefile",
        "h": "cpp", "hpp": "cpp", "hh": "cpp", "m": "objectivec", "mm": "objectivec", "ino": "cpp", "pde": "cpp",
        "kts": "kotlin", "ktm": "kotlin", "csx": "csharp", "cs": "csharp", "fsx": "fsharp", "fsi": "fsharp", "fsscript": "fsharp",
        "jsx": "javascript", "mjs": "javascript", "cjs": "javascript", "tsx": "typescript", "ts": "typescript",
        "htm": "xml", "xhtml": "xml", "xsl": "xml", "xslt": "xml", "xsd": "xml", "svg": "xml", "rss": "xml", "atom": "xml",
        "xliff": "xml", "tmx": "xml", "dita": "xml", "ditamap": "xml", "gml": "xml", "dop": "xml", "csproj": "xml", "pbxproj": "properties",
        "tex": "latex", "sty": "latex", "cls": "latex", "bib": "latex", "scss": "scss", "sass": "scss", "less": "less", "styl": "stylus",
        "erl": "erlang", "hrl": "erlang", "ex": "elixir", "exs": "elixir", "hs": "haskell", "lhs": "haskell", "jl": "julia",
        "lsp": "lisp", "fasl": "lisp", "cl": "lisp", "el": "lisp", "rkt": "scheme", "scm": "scheme", "bas": "vbscript", "vbs": "vbscript", "vbe": "vbscript", "wsc": "vbscript", "wsf": "xml",
        "asm": "x86asm", "s": "armasm", "nasm": "x86asm", "asm6809": "x86asm", "pas": "delphi", "pp": "delphi", "adb": "ada", "ads": "ada",
        "for": "fortran", "f": "fortran", "f90": "fortran", "f95": "fortran", "proto": "protobuf", "zsh": "bash", "ksh": "bash", "csh": "bash", "tcsh": "bash", "fish": "bash", "sh": "bash",
        "bat": "dos", "cmd": "dos", "ps1": "powershell", "psm1": "powershell", "cmake": "cmake", "applescript": "applescript", "scpt": "applescript",
        "rs": "rust", "go": "go", "dart": "dart", "kt": "kotlin", "swift": "swift", "py": "python", "rb": "ruby", "pl": "perl", "pm": "perl",
        "lua": "lua", "php": "php", "sql": "sql", "r": "r", "scala": "scala", "groovy": "groovy", "sol": "javascript", "nix": "nix",
        "toml": "ini", "ini": "ini", "diff": "diff", "patch": "diff", "ino2": "cpp", "elm": "elm", "coffee": "coffeescript", "litcoffee": "coffeescript",
        "twig": "twig", "graphql": "graphql", "gql": "graphql", "zig": "zig", "nim": "nim", "d": "d", "cabal": "plaintext", "lock": "plaintext",
        "pug": "pug", "jade": "pug", "haml": "haml", "erb": "erb", "ejs": "erb", "hbs": "handlebars", "mustache": "handlebars", "liquid": "twig", "njk": "twig",
        "brainfuck": "brainfuck", "b": "brainfuck", "bf": "brainfuck", "actionscript": "actionscript", "as": "actionscript", "rc2": "ini", "cnf2": "ini",
    ]

    /// Decide come mostrare un file a partire da nome ed eventualmente dai primi byte.
    public static func kind(for url: URL, head: Data? = nil) -> PreviewKind {
        let k = classify(url: url, head: head)
        // Un file con NUL e senza BOM UTF-16/32 è binario, qualunque estensione abbia.
        if let head, !head.isEmpty, head.prefix(8192).contains(0),
           !(head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF])) {
            switch k {
            case .plist: if head.starts(with: Array("bplist".utf8)) { return k }; return .binary
            default: return .binary
            }
        }
        return k
    }

    static func classify(url: URL, head: Data?) -> PreviewKind {
        let name = url.lastPathComponent.lowercased()
        var ext = url.pathExtension.lowercased()
        // estensioni composte (.text.md)
        if name.hasSuffix(".text.md") { ext = "md" }

        if let lang = codeNames[name] { return .code(language: lang) }
        if name.hasPrefix(".env") { return .code(language: "ini") }
        if ext.isEmpty {
            let stem = name.hasPrefix(".") ? String(name.dropFirst()) : name
            if plainNames.contains(stem) { return .text(legacyDOS: false) }
            return sniff(head: head)
        }
        // pagine man: .1 … .9, .man, .mdoc, e varianti tipo .1m .3pm
        if ext == "man" || ext == "mdoc" || isManSection(ext) {
            if ext == "1st" { return .text(legacyDOS: true) }
            if let head, let s = String(data: head.prefix(4096), encoding: .utf8) ?? String(data: head.prefix(4096), encoding: .isoLatin1), looksLikeMan(s) { return .man }
            if ext == "man" || ext == "mdoc" { return .man }
            return .text(legacyDOS: false)
        }
        if jsonExts.contains(ext) { return .json }
        if yamlExts.contains(ext) { return .yaml }
        if plistExts.contains(ext) { return .plist }
        if let flavor = markdownExts[ext] { return .markdown(flavor: flavor) }
        if let m = markupExts[ext] { return .markup(m) }
        if ext == "asc" {
            if let head, let s = String(data: head.prefix(4096), encoding: .utf8) {
                if s.contains("-----BEGIN PGP") { return .text(legacyDOS: false) }
                if s.range(of: #"(?m)^=+ \S"#, options: .regularExpression) != nil || s.contains("\n:toc:") || s.hasPrefix(":") { return .markup(.asciidoc) }
            }
            return .text(legacyDOS: false)
        }
        if textExts.contains(ext) { return .text(legacyDOS: dosExts.contains(ext)) }
        if let lang = languageOverrides[ext] { return .code(language: lang) }
        // altrimenti: highlight.js proverà con l'estensione come alias
        return .code(language: ext)
    }

    static func isManSection(_ ext: String) -> Bool {
        guard let f = ext.first, f.isNumber, f != "0" else { return false }
        return ext.count <= 3 && ext != "1st" && ext.dropFirst().allSatisfy { $0.isLetter }
    }
    static func looksLikeMan(_ s: String) -> Bool {
        s.range(of: #"(?m)^\.(TH|Dd|Dt|SH|Sh|\\\")\b"#, options: .regularExpression) != nil
    }

    /// File senza estensione: guarda il contenuto.
    static func sniff(head: Data?) -> PreviewKind {
        guard let head, !head.isEmpty else { return .text(legacyDOS: false) }
        if head.prefix(8192).contains(0) {
            // UTF-16 con BOM è comunque testo
            if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return .text(legacyDOS: false) }
            return .binary
        }
        let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) ?? ""
        if text.hasPrefix("#!") {
            let line = text.prefix(while: { $0 != "\n" }).lowercased()
            let table: [(String, String)] = [("python", "python"), ("ruby", "ruby"), ("perl", "perl"), ("node", "javascript"), ("deno", "typescript"), ("php", "php"),
                                              ("lua", "lua"), ("bash", "bash"), ("zsh", "bash"), ("/sh", "bash"), ("env sh", "bash"), ("fish", "bash"), ("awk", "awk"), ("osascript", "applescript"), ("swift", "swift"), ("tclsh", "tcl"), ("pwsh", "powershell")]
            for (needle, lang) in table where line.contains(needle) { return .code(language: lang) }
            return .code(language: "bash")
        }
        if text.hasPrefix("<?xml") || text.hasPrefix("<!DOCTYPE plist") { return text.contains("<plist") ? .plist : .code(language: "xml") }
        if text.hasPrefix("bplist00") { return .plist }
        if looksLikeMan(text) { return .man }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (t.hasPrefix("{") && t.contains("\"")) || (t.hasPrefix("[") && t.hasSuffix("]") && t.contains("{")) { return .json }
        return .text(legacyDOS: false)
    }
}

// MARK: Riepilogo dei formati (mostrato nella finestra dell'app)

public struct FormatGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let note: String?
    public let extensions: [String]
    public let fileNames: [String]
}

extension FormatCatalog {
    /// Estensioni di linguaggi comuni, oltre a quelle in `languageOverrides` (highlight.js ne riconosce altre ancora).
    static let commonCodeExtensions = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "cxx", "hpp", "hh", "cs", "java", "kt", "kts", "scala", "groovy", "gradle",
        "js", "mjs", "cjs", "jsx", "ts", "tsx", "py", "pyi", "rb", "php", "pl", "pm", "lua", "r", "jl", "go", "rs", "dart", "zig", "nim",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "awk", "sql", "html", "htm", "xml", "css", "scss", "sass", "less",
        "diff", "patch", "ini", "toml", "properties", "env", "conf", "cfg", "tf", "hcl", "proto", "graphql", "vue", "svelte",
        "ex", "exs", "erl", "hs", "ml", "fs", "clj", "lisp", "scm", "tex", "make", "mk", "cmake", "dockerfile", "ino", "asm", "s",
        "applescript", "scpt", "plist", "strings", "entitlements", "storyboard", "xib",
    ]

    /// Tutti i formati gestiti, raggruppati per modo di visualizzazione.
    public static var groups: [FormatGroup] {
        func list(_ s: Set<String>) -> [String] { s.sorted() }
        let code = Set(commonCodeExtensions).union(languageOverrides.keys).subtracting(["ino2", "cnf2", "rc2"])
        let markdown = Set(markdownExts.keys).subtracting(["text.md"])
        let man = ["man", "mdoc", "1", "2", "3", "4", "5", "6", "7", "8", "9", "n", "1m", "3p", "3pm"]
        return [
            FormatGroup(id: "code", title: String(localized: "Codice", bundle: QTLPaths.bundle),
                        note: String(localized: "Evidenziazione con highlight.js (oltre 190 linguaggi, anche per estensioni non elencate) e numeri di riga. I file senza estensione si riconoscono da nome o da #!.", bundle: QTLPaths.bundle),
                        extensions: list(code), fileNames: codeNames.keys.sorted()),
            FormatGroup(id: "json", title: "JSON", note: String(localized: "Albero e sorgente; commenti e virgole finali tollerati.", bundle: QTLPaths.bundle), extensions: list(jsonExts), fileNames: []),
            FormatGroup(id: "yaml", title: "YAML", note: String(localized: "Albero e sorgente; più documenti separati da ---.", bundle: QTLPaths.bundle), extensions: list(yamlExts), fileNames: []),
            FormatGroup(id: "plist", title: "Property list", note: String(localized: "Albero e sorgente XML, anche per le plist binarie.", bundle: QTLPaths.bundle), extensions: list(plistExts), fileNames: []),
            FormatGroup(id: "text", title: String(localized: "Testo", bundle: QTLPaths.bundle),
                        note: String(localized: "Codifica rilevata automaticamente; .nfo, .diz e simili come DOS (CP437).", bundle: QTLPaths.bundle),
                        extensions: list(textExts), fileNames: plainNames.sorted()),
            FormatGroup(id: "markdown", title: "Markdown", note: String(localized: "Dialetti Typora, GitHub, CommonMark e MultiMarkdown; formule, diagrammi, note a piè di pagina, temi e CSS importabili.", bundle: QTLPaths.bundle), extensions: list(markdown), fileNames: []),
            FormatGroup(id: "markup", title: String(localized: "Altri markup", bundle: QTLPaths.bundle), note: String(localized: "Textile, AsciiDoc, Creole, reStructuredText e BBCode con gli stessi temi del Markdown.", bundle: QTLPaths.bundle), extensions: markupExts.keys.sorted(), fileNames: []),
            FormatGroup(id: "man", title: String(localized: "Pagine man", bundle: QTLPaths.bundle), note: String(localized: "Macro man e mdoc.", bundle: QTLPaths.bundle), extensions: man, fileNames: []),
        ]
    }
}
