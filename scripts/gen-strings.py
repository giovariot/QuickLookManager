#!/usr/bin/env python3
"""Genera i String Catalog (it sorgente; en, fr, de, es, ar) dalle tabelle in scripts/traduzioni/.
Prima compila (SWIFT_EMIT_LOC_STRINGS e' attivo), poi: scripts/gen-strings.py
Segnala le chiavi trovate nei sorgenti senza traduzione in una lingua."""
import glob, json, re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / "scripts/traduzioni"))
from en_extra import EN_EXTRA
from lingue_a import LA
from lingue_b import LB
from lingue_c import LC
from lingue_d import LD

LANGS = ["en", "fr", "de", "es", "ar"]
# chiave italiana -> inglese ; (one, other) per i plurali
EN = {
 # ---- impostazioni
 "Codice": "Code", "JSON e YAML": "JSON and YAML", "Testo": "Text", "Markdown": "Markdown",
 "Visualizzazione": "Display", "Linguaggio": "Language", "Limiti": "Limits", "Numeri di riga": "Line numbers",
 "Vai a capo automaticamente": "Wrap lines", "Dimensione del carattere: %lld pt": "Font size: %lld pt",
 "Larghezza della tabulazione": "Tab width", "%lld spazi": "%lld spaces",
 "Usato quando l'estensione non indica un linguaggio noto.": "Used when the file extension doesn't indicate a known language.",
 "Riconosci il linguaggio dal contenuto": "Detect the language from the content",
 "Dimensione massima evidenziata": "Maximum size to highlight", "All'apertura": "On opening", "Mostra": "Show",
 "Livelli espansi: %lld": "Expanded levels: %lld", "Mostra la colonna «Tipo»": "Show the “Type” column",
 "Property list: mostra la struttura": "Property lists: show the structure", "Struttura": "Structure", "Sorgente": "Source",
 "Dimensione massima letta": "Maximum size to read",
 "Il sorgente usa le impostazioni di carattere e numeri di riga della scheda Codice.": "The source view uses the font and line number settings from the Code tab.",
 "Codifica": "Encoding", "Carattere": "Font", "Dimensione: %lld pt": "Size: %lld pt", "A spaziatura fissa": "Monospaced",
 "Proporzionale": "Proportional", "Leggi .nfo, .diz e simili come DOS (CP437)": "Read .nfo, .diz and similar as DOS (CP437)",
 "Automatica": "Automatic", "Dialetto": "Dialect", "Tema": "Theme", "Formule matematiche (KaTeX)": "Math formulas (KaTeX)",
 "Diagrammi (Mermaid)": "Diagrams (Mermaid)", "Mostra anche Textile, AsciiDoc, Creole, reStructuredText e BBCode": "Also render Textile, AsciiDoc, Creole, reStructuredText and BBCode",
 "Typora (tutte le estensioni)": "Typora (all extensions)", "GitHub (GFM)": "GitHub (GFM)", "CommonMark": "CommonMark", "MultiMarkdown": "MultiMarkdown",
 "Sono compatibili i temi di Typora e qualunque CSS che usi #write o .markdown-body. Il tema scelto si applica sopra la base di sistema.": "Typora themes and any CSS that targets #write or .markdown-body are supported. The chosen theme is applied on top of the system base style.",
 "Stile": "Style", "Importa CSS…": "Import CSS…", "Mostra cartella dei temi": "Show Themes Folder", "Larghezza massima": "Maximum width",
 "Tutta la finestra": "Full window", "Stretta (680 pt)": "Narrow (680 pt)", "Media (860 pt)": "Medium (860 pt)", "Ampia (1100 pt)": "Wide (1100 pt)",
 # ---- finestra
 "QuickTextLook": "QuickTextLook", "Apri…": "Open…", "Prova un file": "Try a File", "Formati supportati": "Supported Formats", "Attivazione": "Activation",
 "Trascina un file qui": "Drop a File Here",
 "Vedrai l'anteprima di Quick Look: se QuickTextLook è attivo, è quella delle sue estensioni.": "You'll see the Quick Look preview. If QuickTextLook is active, it comes from its extensions.",
 "Scegli un file…": "Choose a File…", "Scegli file": "Choose File",
 "Tipo": "Type", "Nomi di file": "File names",
 "Evidenziazione con highlight.js (oltre 190 linguaggi, anche per estensioni non elencate) e numeri di riga. I file senza estensione si riconoscono da nome o da #!.": "Highlighted with highlight.js (over 190 languages, including extensions not listed) with line numbers. Files without an extension are recognized by name or by #!.",
 "Albero e sorgente; commenti e virgole finali tollerati.": "Tree and source; comments and trailing commas are tolerated.",
 "Albero e sorgente; più documenti separati da ---.": "Tree and source; multiple documents separated by --- are supported.",
 "Albero e sorgente XML, anche per le plist binarie.": "Tree and XML source, including binary plists.",
 "Codifica rilevata automaticamente; .nfo, .diz e simili come DOS (CP437).": "Encoding is detected automatically; .nfo, .diz and similar are read as DOS (CP437).",
 "Dialetti Typora, GitHub, CommonMark e MultiMarkdown; formule, diagrammi, note a piè di pagina, temi e CSS importabili.": "Typora, GitHub, CommonMark and MultiMarkdown dialects; formulas, diagrams, footnotes, themes and importable CSS.",
 "Altri markup": "Other Markup",
 "Textile, AsciiDoc, Creole, reStructuredText e BBCode con gli stessi temi del Markdown.": "Textile, AsciiDoc, Creole, reStructuredText and BBCode, using the same themes as Markdown.",
 "Pagine man": "Man pages", "Macro man e mdoc.": "man and mdoc macros.",
 "Le anteprime e le miniature sono estensioni di Quick Look. macOS le attiva da solo quando l'app è in Applicazioni; se vuoi controllare o scegliere quale estensione ha la precedenza:": "Previews and thumbnails are Quick Look extensions. macOS enables them automatically when the app is in Applications. To check or choose which extension takes precedence:",
 "Apri Impostazioni di Sistema…": "Open System Settings…", "Estensioni": "Extensions",
 "Se un'anteprima non cambia dopo un aggiornamento, ricarica Quick Look.": "If a preview doesn't change after an update, reload Quick Look.",
 "Ricarica Quick Look": "Reload Quick Look", "Se qualcosa non va": "If Something Is Wrong",
 "Le impostazioni di ogni formato sono in QuickTextLook › Impostazioni… (⌘,) e valgono sia per l'app sia per le estensioni.": "Each format's settings are in QuickTextLook › Settings… (⌘,) and apply to both the app and its extensions.",
 "Impostazioni": "Settings",
 # ---- framework
 "Copia chiave": "Copy Key", "Copia valore": "Copy Value", "Copia riga": "Copy Row", "Chiave": "Key", "Valore": "Value",
 "Struttura del documento": "Document structure", "radice": "root", "(radice)": "(root)", "Formato non supportato da QuickTextLook.": "This format isn't supported by QuickTextLook.",
 "Modo di visualizzazione": "View mode", "File troncato al limite impostato.": "File truncated at the configured limit.",
 "Il file è più grande del limite impostato: mostrata solo la parte iniziale.": "The file is larger than the configured limit: only the beginning is shown.",
 "Errore di sintassi: %@": "Syntax error: %@", "Sistema": "System", "Contenuto del file": "File contents",
 "Dizionario": "Dictionary", "Array": "Array", "Stringa": "String", "Numero": "Number", "Booleano": "Boolean", "Nullo": "Null", "Data": "Date", "Dati": "Data",
 "Atteso «:»": "Expected “:”", "Oggetto non chiuso": "Unterminated object", "Array non chiuso": "Unterminated array", "Carattere inatteso": "Unexpected character",
 "Valore non valido «%@»": "Invalid value “%@”", "Fine inattesa": "Unexpected end", "%@ alla posizione %lld": "%@ at position %lld",
 "Stringa non chiusa": "Unterminated string", "Documento %lld": "Document %lld",
 "Unicode (UTF-8)": "Unicode (UTF-8)", "Unicode (UTF-16)": "Unicode (UTF-16)", "Latin 1 (Windows)": "Western (Windows Latin 1)", "Latin 1 (ISO)": "Western (ISO Latin 1)",
 "Latin 9 (ISO 8859-15)": "Western (ISO Latin 9)", "Mac Roman": "Western (Mac OS Roman)", "DOS (CP437)": "DOS (CP437)", "DOS Latin 1 (CP850)": "DOS Latin 1 (CP850)",
 "Giapponese (Shift JIS)": "Japanese (Shift JIS)", "Cinese semplificato (GB 18030)": "Simplified Chinese (GB 18030)", "Cinese tradizionale (Big5)": "Traditional Chinese (Big5)",
 "Coreano (EUC-KR)": "Korean (EUC-KR)", "Cirillico (KOI8-R)": "Cyrillic (KOI8-R)", "Cirillico (Windows)": "Cyrillic (Windows)",
}


# plurali: chiave -> {lingua: {categoria: testo}}
def _p(it, en, fr, de, es, ar):
    return {"it": it, "en": en, "fr": fr, "de": de, "es": es, "ar": ar}
PLURAL = {
 "%lld chiavi": _p({"one": "%lld chiave", "other": "%lld chiavi"}, {"one": "%lld key", "other": "%lld keys"},
    {"one": "%lld clé", "other": "%lld clés"}, {"one": "%lld Schlüssel", "other": "%lld Schlüssel"},
    {"one": "%lld clave", "other": "%lld claves"},
    {"zero": "لا مفاتيح", "one": "مفتاح واحد", "two": "مفتاحان", "few": "%lld مفاتيح", "many": "%lld مفتاحًا", "other": "%lld مفتاح"}),
 "%lld elementi": _p({"one": "%lld elemento", "other": "%lld elementi"}, {"one": "%lld item", "other": "%lld items"},
    {"one": "%lld élément", "other": "%lld éléments"}, {"one": "%lld Element", "other": "%lld Elemente"},
    {"one": "%lld elemento", "other": "%lld elementos"},
    {"zero": "لا عناصر", "one": "عنصر واحد", "two": "عنصران", "few": "%lld عناصر", "many": "%lld عنصرًا", "other": "%lld عنصر"}),
 "%lld byte": _p({"one": "%lld byte", "other": "%lld byte"}, {"one": "%lld byte", "other": "%lld bytes"},
    {"one": "%lld octet", "other": "%lld octets"}, {"one": "%lld Byte", "other": "%lld Byte"},
    {"one": "%lld byte", "other": "%lld bytes"},
    {"zero": "0 بايت", "one": "بايت واحد", "two": "بايتان", "few": "%lld بايتات", "many": "%lld بايتًا", "other": "%lld بايت"}),
}
EN.update({
 ".app, framework, plug-in, estensioni, binari Mach-O: architetture, sistema minimo, firma, entitlement, notarizzazione": ".app, framework, plug-ins, extensions, Mach-O binaries: architectures, minimum system, signature, entitlements, notarization",
 ".ipa, .tipa, .xcarchive: profilo di provisioning, entitlement, App Transport Security": ".ipa, .tipa, .xcarchive: provisioning profile, entitlements, App Transport Security",
 ".apk, .apkm: permessi, funzionalità, versione dell'SDK": ".apk, .apkm: permissions, features, SDK version",
 ".exe e .dll di Windows, pacchetti .flatpak, programmi e documenti dei vecchi Mac": "Windows .exe and .dll, .flatpak packages, classic Mac programs and documents",
 "Formato non supportato da QuickLook Manager.": "This format isn't supported by QuickLook Manager.",
 "modificato %@": "modified %@", "Estensione %@": "%@ extension", "%lld in %lld tipi": "%lld in %lld types",
 "%lld risorse in %lld tipi": "%lld resources in %lld types", "Icone nel file: %@": "Icons in the file: %@",
 "%@ %@ o successivo": "%@ %@ or later", "macOS %@ o successivo": "macOS %@ or later",
 "non torna: %@": "does not verify: %@", "non si è potuta controllare (errore %d)": "could not be checked (error %d)",
 "sì, versione %@": "yes, version %@",
})
CODE = {"en": "en", "fr": "fr", "de": "de", "es": "es", "ar": "ar"}

def norm(s):
    return re.sub(r"%(?:\d+\$)?(?:lld|@|d)|\{\}", "{}", s)

def holes(s):
    return len(re.findall(r"%(?:\d+\$)?(?:lld|@|d)", s))

# tabella unificata: inglese normalizzato -> (fr, de, es, ar)
TAB = {}
for t in (LA, LB, LC, LD):
    for k, v in t.items():
        TAB[norm(k)] = v

try:
    TR_EN = json.load(open(root / "scripts/traduzioni/tr-en.json"))
except OSError:
    TR_EN = {}

def english(k):
    return EN.get(k) or TR_EN.get(k) or EN_EXTRA.get(k)

def fill(tpl, key):
    """Rimette in tpl i segnaposto della chiave italiana, nell'ordine."""
    ph = re.findall(r"%(?:\d+\$)?(?:lld|@|d)", key)
    it = iter(ph)
    return re.sub(r"\{\}", lambda m: next(it, "%@"), tpl)

def used(pattern):
    keys = {}
    for f in glob.glob(str(root / f"build/DerivedData/**/{pattern}/Objects-normal/arm64/*.stringsdata"), recursive=True):
        for items in json.load(open(f)).get("tables", {}).values():
            for it in items:
                keys[it["key"]] = True
    return keys

def unit(v): return {"stringUnit": {"state": "translated", "value": v}}

def localizations(k):
    miss = []
    if k in PLURAL:
        loc = {l: {"variations": {"plural": {c: unit(t) for c, t in PLURAL[k][l].items()}}} for l in LANGS}
        return loc, miss
    en = english(k)
    if k == "it":
        return {l: unit(CODE[l]) for l in LANGS}, miss
    if en is None:
        return None, ["en"]
    en_n = norm(en)
    loc = {"en": unit(fill(en_n, k))}
    row = TAB.get(en_n)
    for i, l in enumerate(LANGS[1:]):
        if row is not None and row[i]:
            loc[l] = unit(fill(norm(row[i]), k))
        elif en_n == "" or norm(k) == en_n:
            loc[l] = unit(fill(en_n, k))   # nome proprio/identico: nessuna traduzione necessaria
        else:
            miss.append(l)
    for l, u in loc.items():
        if l != "en" and "variations" not in u and holes(u["stringUnit"]["value"]) != holes(k):
            miss.append(l + "(segnaposto)")
    return loc, miss

ok = True
for target, pattern, path in (("App", "QuickLookManager.build", "App/Localizable.xcstrings"),
                              ("Core", "QLMCore.build", "Modules/Text/Resources/Localizable.xcstrings")):
    keys = used(pattern)
    out = {}
    for k in keys:
        loc, miss = localizations(k)
        if miss:
            print(f"[{target}] {k!r}: manca {miss}"); ok = False
        if loc is None: continue
        out[k] = {"extractionState": "manual", "localizations": loc}
    (root / path).write_text(json.dumps({"sourceLanguage": "it", "strings": dict(sorted(out.items())), "version": "1.0"}, ensure_ascii=False, indent=2) + "\n")
    print(f"{target}: {len(out)} chiavi")
sys.exit(0 if ok else 1)
