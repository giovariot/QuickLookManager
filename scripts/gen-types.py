#!/usr/bin/env python3
"""Rigenera da una sola tabella: i tipi (UTI) esportati dall'app e l'elenco QLSupportedContentTypes delle estensioni.
Quick Look sceglie un'estensione solo per i tipi elencati in modo ESATTO (la conformita' non basta),
quindi ogni estensione di file che non ha un tipo di sistema ha un tipo nostro.
Uso: scripts/gen-types.py   (poi: xcodegen generate)
Riscrive project.yml fra i marcatori «# BEGIN/END ...» e Kit/QLMTypes.swift."""
import re, pathlib

PREFIX = "com.giovariot.quicklookmanager.text."
# (id, descrizione, conforme a, estensioni)
TYPES = [
  # codice senza tipo di sistema
  ("rust", "Rust source", "public.source-code", "rs"), ("go", "Go source", "public.source-code", "go"),
  ("kotlin", "Kotlin source", "public.source-code", "kt kts ktm"), ("dart", "Dart source", "public.source-code", "dart"),
  ("elixir", "Elixir source", "public.source-code", "ex exs"), ("erlang", "Erlang source", "public.source-code", "erl hrl"),
  ("haskell", "Haskell source", "public.source-code", "hs lhs"), ("julia", "Julia source", "public.source-code", "jl"),
  ("lisp", "Lisp source", "public.source-code", "lisp lsp fasl cl el"), ("scheme", "Scheme source", "public.source-code", "scm rkt"),
  ("terraform", "Terraform", "public.source-code", "tf tfvars hcl"), ("vue", "Vue component", "public.source-code", "vue"),
  ("elm", "Elm source", "public.source-code", "elm"), ("stylesheet", "Sass/Less/Stylus", "public.source-code", "scss sass less styl"),
  ("arduino", "Arduino sketch", "public.source-code", "ino pde"), ("fsharp", "F# source", "public.source-code", "fs fsx fsi"),
  ("vbscript", "VBScript", "public.source-code", "vbs vbe wsf bas"), ("coffeescript", "CoffeeScript", "public.source-code", "coffee litcoffee"),
  ("assembly", "Assembly", "public.source-code", "asm nasm"), ("scala", "Scala/Groovy/Gradle", "public.source-code", "scala sc groovy gradle"),
  ("systems", "Nim/Zig/D", "public.source-code", "nim zig d"), ("graphql", "GraphQL", "public.source-code", "graphql gql prisma"),
  ("nix", "Nix", "public.source-code", "nix"), ("powershell", "PowerShell", "public.script", "ps1 psm1"),
  ("batch", "Batch file", "public.script", "bat cmd"), ("fish", "fish/awk script", "public.script", "fish awk"),
  ("template", "Template", "public.source-code", "pug jade haml erb ejs hbs mustache liquid njk twig"),
  ("cmake", "CMake", "public.source-code", "cmake"), ("makefile-ext", "Makefile include", "public.source-code", "mk make"),
  ("jsx", "JSX/TSX/ES module", "public.source-code", "jsx tsx mjs cjs"), ("xmlish", "XML-based", "public.source-code", "xsl xslt xsd rss atom tmx dita ditamap gml dop csproj xcprivacy"),
  # configurazione
  ("conf", "Configuration file", "public.plain-text", "conf cfg cnf cf rc config"), ("env", "Environment file", "public.plain-text", "env"),
  ("properties", "Properties file", "public.plain-text", "properties xcconfig"),
  ("dotfiles", "Dotfile", "public.plain-text", "gitignore gitattributes dockerignore npmrc editorconfig gitconfig gitmodules"),
  # testo
  ("nfo", "NFO / DOS text", "public.plain-text", "nfo diz info inf 1st asi ans ascii"), ("text", "Text file", "public.plain-text", "tx lst me asc readme sig"),
  ("subtitles", "Subtitles", "public.plain-text", "srt sub vtt ssa ass sbv lrc"),
  # man
  ("man", "Man page", "public.plain-text", "man mdoc 1 2 3 4 5 6 7 8 9 n 1m 3p 3pm"),
  # markup
  ("asciidoc", "AsciiDoc", "public.plain-text", "adoc asciidoc"), ("textile", "Textile", "public.plain-text", "textile"), ("creole", "Creole wiki", "public.plain-text", "creole"),
  ("rst", "reStructuredText", "public.plain-text", "rst rest"), ("bbcode", "BBCode", "public.plain-text", "bbcode bb"),
  ("pendown", "Pen Down", "public.plain-text", "pendown pdn"),
  ("markdown-variants", "Markdown variant", "net.daringfireball.markdown", "mmd multimarkdown mmdoc rmd qmd mdx livemd mdtxt mdtext gfm commonmark"),
  # dati
  ("json-variants", "JSON variant", "public.json", "jsonc json5 geojson topojson jsonld har ipynb webmanifest"),
  ("plist-variants", "Property list variant", "com.apple.property-list", "mobileconfig webloc tmtheme xcsettings"),
]

# Tipi di sistema gia' esistenti che l'estensione deve elencare (esatti).
SYSTEM = """public.plain-text public.source-code public.script public.shell-script public.json public.yaml public.toml public.css
public.markdown net.daringfireball.markdown net.multimarkdown.text org.asciidoc com.apple.property-list com.apple.xml-property-list
com.apple.xcode.entitlements-property-list com.apple.xcode.strings-text com.microsoft.ini com.apple.log public.patch-file
public.make-source public.c-source public.swift-source public.python-script public.c-header public.c-plus-plus-source
public.c-plus-plus-header public.objective-c-source public.objective-c-plus-plus-source public.fortran-source public.pascal-source
public.protobuf-source public.ruby-script public.perl-script public.php-script public.zsh-script public.csh-script public.ksh-script
public.tcsh-script public.bash-script public.ada-source public.assembly-source public.lua-script public.nasm-assembly-source
com.apple.applescript.text com.apple.interfacebuilder.document.cocoa com.apple.dt.interfacebuilder.document.storyboard
com.netscape.javascript-source com.sun.java-source com.microsoft.c-sharp com.microsoft.typescript com.seriflabs.xmp com.psion.opl-source
org.lua org.clojure org.tug org.oasis-open.xliff org.oasis-open.dita.map org.oasis-open.dita.document org.iso.sql
com.barebones.bbedit.textile-source public.data""".split()

# Tipi di testo che le miniature non devono elencare (vedi main()).
THUMB_EXCLUDE = {"com.giovariot.quicklookmanager.text.text"}

# --- Modulo «App e pacchetti» ---
APPS_PREVIEW = """com.apple.itunes.ipa com.apple.application-and-system-extension com.apple.xcode.archive com.opa334.trollstore.tipa
dyn.ah62d4rv4ge81k4puqe com.google.android.apk dyn.ah62d4rv4ge80c6dp public.archive.apk dyn.ah62d4rv4ge80c6dpry
com.giovariot.quicklookmanager.classic-application com.apple.application-file com.microsoft.windows-executable
com.microsoft.windows-dynamic-link-library com.apple.application-bundle com.apple.framework com.apple.xpc-service
com.apple.systempreference.prefpane com.apple.system-extension com.apple.driver-extension com.apple.kernel-extension
com.apple.plugin com.apple.mach-o-dylib com.giovariot.quicklookmanager.flatpak-bundle dyn.ah62d4rv4ge80q5dbsv2gc42""".split()
# Le miniature: solo i tipi con un'icona propria da mostrare.
APPS_THUMB = """com.apple.itunes.ipa com.apple.xcode.archive com.opa334.trollstore.tipa dyn.ah62d4rv4ge81k4puqe
com.google.android.apk dyn.ah62d4rv4ge80c6dp public.archive.apk dyn.ah62d4rv4ge80c6dpry
com.giovariot.quicklookmanager.classic-application com.apple.application-file com.microsoft.windows-executable
com.microsoft.windows-dynamic-link-library com.giovariot.quicklookmanager.flatpak-bundle dyn.ah62d4rv4ge80q5dbsv2gc42""".split()
# (id, descrizione, conforme a, estensioni, tipo di mime)
APPS_EXPORTED = [
  ("com.giovariot.quicklookmanager.flatpak-bundle", "Flatpak bundle", "public.data, public.archive", "flatpak", "application/vnd.flatpak"),
  ("com.giovariot.quicklookmanager.classic-application", "Classic Macintosh application", "public.data", "macapp", None),
]
APPS_IMPORTED = [
  ("com.opa334.trollstore.tipa", "AirDrop friendly iOS app", "public.data", "tipa", "application/trollstore-ipa"),
  ("com.google.android.apk", None, "public.data", "apk apkm", "application/vnd.android.package-archive"),
]

# --- Modulo «Foto RAW» --- (elenco dei tipi dichiarati da Camera RawX, più l'ombrello di sistema)
RAW_TYPES = ['com.nikon.raw-image', 'com.canon.cr3-raw-image', 'com.canon.cr2-raw-image', 'com.fuji.raw-image', 'com.panasonic.rw2-raw-image', 'com.olympus.raw-image', 'com.sony.arw-raw-image', 'com.hasselblad.3fr-raw-image', 'com.samsung.raw-image', 'com.adobe.raw-image', 'com.anogeissus.x3f', 'com.sigmaphoto.photopro-X3F', 'com.anogeissus.arq']
RAW_TYPES = list(dict.fromkeys(["public.camera-raw-image"] + RAW_TYPES + ['com.adobe.raw-image', 'com.canon.cr2-raw-image', 'com.canon.cr3-raw-image', 'com.canon.crw-raw-image', 'com.epson.raw-image', 'com.fuji.raw-image', 'com.gopro.gpr', 'com.hasselblad.3fr-raw-image', 'com.hasselblad.fff-raw-image', 'com.kodak.raw-image', 'com.konicaminolta.raw-image', 'com.leafamerica.raw-image', 'com.leica.rwl-raw-image', 'com.nikon.nrw-raw-image', 'com.nikon.raw-image', 'com.olympus.raw-image', 'com.panasonic.raw-image', 'com.panasonic.rw2-raw-image', 'com.pentax.raw-image', 'com.phaseone.raw-image', 'com.samsung.raw-image', 'com.sony.arw-raw-image', 'com.sony.raw-image', 'com.sony.sr2-raw-image']))

# --- Modulo «Modelli 3D» ---
MODEL_TYPES = ["com.preview3mf.3mf-file", "com.shapr3d.3d-manufacturing.3mf", "com.bambulab.3mf"]
MODEL_IMPORTED = [("com.preview3mf.3mf-file", "3D Manufacturing Format", "public.zip-archive, public.data", "3mf", "model/3mf")]

# --- Modulo «EPS» ---
EPS_TYPES = ["com.adobe.encapsulated-postscript"]

# --- Modulo «Archivi» --- (libarchive di sistema)
ARCHIVE_TYPES = """public.zip-archive org.gnu.gnu-zip-archive public.tar-archive org.gnu.gnu-zip-tar-archive public.bzip2-archive
public.tar-bzip2-archive public.cpio-archive com.apple.xar-archive org.debian.deb-archive com.redhat.rpm-archive
org.7-zip.7-zip-archive com.rarlab.rar-archive org.tukaani.xz-archive org.tukaani.lzma-archive org.tukaani.tar-xz-archive
com.microsoft.cab public.lha-archive com.facebook.zstd-archive public.iso-image""".split()
ARCHIVE_IMPORTED = [
  ("org.7-zip.7-zip-archive", "7-Zip archive", "public.data, public.archive", "7z", "application/x-7z-compressed"),
  ("com.rarlab.rar-archive", "RAR archive", "public.data, public.archive", "rar", "application/vnd.rar"),
  ("org.tukaani.xz-archive", "XZ archive", "public.data, public.archive", "xz", "application/x-xz"),
  ("org.tukaani.lzma-archive", "LZMA archive", "public.data, public.archive", "lzma", None),
  ("org.tukaani.tar-xz-archive", "XZ-compressed tar archive", "public.data, public.archive", "txz tar.xz", None),
  ("com.microsoft.cab", "Cabinet archive", "public.data, public.archive", "cab", "application/vnd.ms-cab-compressed"),
  ("public.lha-archive", "LHA archive", "public.data, public.archive", "lzh lha", None),
  ("com.facebook.zstd-archive", "Zstandard archive", "public.data, public.archive", "zst", "application/zstd"),
  ("com.redhat.rpm-archive", "RPM package", "public.data, public.archive", "rpm", "application/x-rpm"),
]

# --- Modulo «Pacchetti PKG» ---
PKG_TYPES = ["com.apple.installer-package-archive", "com.apple.installer-meta-package"]

# --- Modulo «Video» --- (solo i formati che AVFoundation non legge; mp4, mov e m4v restano ad Apple)
VIDEO_TYPES = """org.matroska.mkv org.matroska.mka org.webmproject.webm public.avi com.microsoft.windows-media-wmv
com.microsoft.advanced-systems-format com.adobe.flash.video org.xiph.ogv com.giovariot.quicklookmanager.m2ts
com.giovariot.quicklookmanager.vob com.giovariot.quicklookmanager.realmedia com.giovariot.quicklookmanager.divx
com.giovariot.quicklookmanager.mxf""".split()
VIDEO_IMPORTED = [
  ("org.matroska.mkv", "Matroska video", "public.movie", "mkv mk3d", "video/x-matroska"),
  ("org.matroska.mka", "Matroska audio", "public.audio", "mka", "audio/x-matroska"),
  ("org.webmproject.webm", "WebM video", "public.movie", "webm", "video/webm"),
  ("com.microsoft.windows-media-wmv", "Windows Media video", "public.movie", "wmv", "video/x-ms-wmv"),
  ("com.microsoft.advanced-systems-format", "Advanced Systems Format", "public.movie", "asf", "video/x-ms-asf"),
  ("com.adobe.flash.video", "Flash video", "public.movie", "flv f4v", "video/x-flv"),
  ("org.xiph.ogv", "Ogg video", "public.movie", "ogv ogm", "video/ogg"),
]
VIDEO_OWN = [
  ("com.giovariot.quicklookmanager.m2ts", "MPEG-2 transport stream video", "public.movie", "m2ts mts", None),
  ("com.giovariot.quicklookmanager.vob", "DVD video object", "public.movie", "vob", None),
  ("com.giovariot.quicklookmanager.realmedia", "RealMedia video", "public.movie", "rm rmvb", "application/vnd.rn-realmedia"),
  ("com.giovariot.quicklookmanager.divx", "DivX video", "public.movie", "divx", None),
  ("com.giovariot.quicklookmanager.mxf", "Material Exchange Format", "public.movie", "mxf", "application/mxf"),
]

def decl(items, indent):
    out = ""
    for (i, desc, conf, exts, mime) in items:
        out += f"{indent}- UTTypeIdentifier: {i}\n"
        if desc: out += f"{indent}  UTTypeDescription: {desc}\n"
        out += f"{indent}  UTTypeConformsTo: [{conf}]\n{indent}  UTTypeTagSpecification:\n"
        out += f"{indent}    public.filename-extension: [" + ", ".join(f'"{e}"' for e in exts.split()) + "]\n"
        if mime: out += f"{indent}    public.mime-type: [\"{mime}\"]\n"
    return out

def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    ids = [PREFIX + t[0] for t in TYPES]
    p = root / "project.yml"
    s = p.read_text()
    more = RAW_TYPES + MODEL_TYPES + EPS_TYPES + ARCHIVE_TYPES + VIDEO_TYPES + PKG_TYPES
    prev = SYSTEM + ids + APPS_PREVIEW + more
    # ThumbnailsAgent scarta l'intera estensione miniature (e tutti i tipi che seguono) se uno dei tipi elencati ha un'estensione di
    # file «vietata» (log: «is trying to register for a prohibited filename extension»). Trovato per bisezione: il tipo «text».
    thumb_ids = [i for i in ids if i not in THUMB_EXCLUDE]
    thumb = SYSTEM + thumb_ids + APPS_THUMB + RAW_TYPES + MODEL_TYPES + EPS_TYPES + VIDEO_TYPES
    def block(name, items):
        return f"            # BEGIN {name}\n" + "".join(f"            - {t}\n" for t in items) + f"            # END {name}\n"
    for name, items in (("preview-types", prev), ("thumbnail-types", thumb)):
        s = re.sub(rf"            # BEGIN {name}\n.*?            # END {name}\n", lambda m: block(name, items), s, flags=re.S)
    exp = ""
    for (i, desc, conf, exts) in TYPES:
        exp += f"          - UTTypeIdentifier: {PREFIX}{i}\n            UTTypeDescription: {desc}\n            UTTypeConformsTo: [{conf}, public.text]\n"
        exp += "            UTTypeTagSpecification:\n              public.filename-extension: [" + ", ".join(f'"{e}"' for e in exts.split()) + "]\n"
    exp += decl(APPS_EXPORTED + VIDEO_OWN, "          ")
    imp = decl(APPS_IMPORTED + MODEL_IMPORTED + ARCHIVE_IMPORTED + VIDEO_IMPORTED, "          ")
    s = re.sub(r"        # BEGIN exported\n.*?        # END exported\n", lambda m: "        # BEGIN exported\n        UTExportedTypeDeclarations:\n" + exp + "        # END exported\n", s, flags=re.S)
    s = re.sub(r"        # BEGIN imported\n.*?        # END imported\n", lambda m: "        # BEGIN imported\n        UTImportedTypeDeclarations:\n" + imp + "        # END imported\n", s, flags=re.S)
    p.write_text(s)
    def lower(items): return sorted({t.lower() for t in items})
    def block_set(name, items):
        return f"    static let {name}: Set<String> = [\n" + "".join(f'        "{t}",\n' for t in lower(items)) + "    ]\n"
    (root / "Kit" / "QLMTypes.swift").write_text(
        "// Generato da scripts/gen-types.py: non modificare a mano.\nenum QLMTypes {\n"
        + block_set("apps", APPS_PREVIEW + APPS_THUMB) + block_set("raw", RAW_TYPES) + block_set("models", MODEL_TYPES)
        + block_set("eps", EPS_TYPES) + block_set("archives", ARCHIVE_TYPES) + block_set("video", VIDEO_TYPES) + block_set("pkg", PKG_TYPES)
        + "\n    /// Il modulo che dichiara questo tipo (UTI in minuscolo), se ce n'è uno; il testo non ha un elenco proprio.\n"
        + "    static func module(forType uti: String) -> QLMModule? {\n"
        + "        if apps.contains(uti) { return .apps }\n        if raw.contains(uti) { return .raw }\n        if models.contains(uti) { return .models }\n"
        + "        if eps.contains(uti) { return .eps }\n        if archives.contains(uti) { return .archives }\n        if video.contains(uti) { return .video }\n        if pkg.contains(uti) { return .pkg }\n        return nil\n    }\n}\n")
    apps = APPS_PREVIEW
    print(len(TYPES), "tipi di testo,", len(apps), "tipi di app, anteprima:", len(prev), "miniature:", len(thumb))
main()
