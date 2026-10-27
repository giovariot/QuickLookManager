import AppKit
import Foundation

/// Il raccordo fra i lettori dei formati vecchi e il resto di QLAppBundle.
///
/// `AppIcon` e `PreviewGenerator` smistano per `FileType`, e a loro basta
/// sapere «dammi l'icona» e «dammi le righe da mostrare». Tutto il sapere sui
/// fork di risorse e sui file PE resta di là; qui c'è solo la traduzione.
enum ClassicSupport {

    /// L'icona di un file, qualunque delle due famiglie sia.
    ///
    /// Per i Macintosh classici si guarda nel fork di risorse: prima l'icona
    /// personalizzata, che vale per qualunque file, poi quella che
    /// un'applicazione si porta dentro, trovata come la trovava il Finder nel
    /// 1984 — BNDL, poi il FREF che dichiara `APPL`, poi l'`ICN#` che quello
    /// nomina.
    ///
    /// Per gli eseguibili Windows si guarda nella sezione risorse del PE, e ne
    /// esce un `.ico`, che macOS legge da sé.
    static func icon(for meta: MetaInfo) -> NSImage? {
        switch meta.type {
        case .ClassicMac:
            guard let raw = ClassicIcon.resourceFork(of: meta.url),
                  let fork = ClassicIcon.Fork(raw)
            else { return nil }

            if let custom = ClassicIcon.custom(fork: fork) { return NSImage(data: custom) }

            // Il controllo sul type non è una formalità: il `Desktop` di ogni
            // disco è pieno di BNDL — essere il database delle icone è il suo
            // mestiere — e senza si finisce per dare a un file qualunque
            // l'icona del primo programma che ci si trova dentro.
            guard ClassicIcon.isApplication(ClassicIcon.fileType(of: meta.url)),
                  let id = ClassicIcon.applicationIconID(in: fork),
                  let icns = ClassicIcon.icns(from: fork, id: id)
            else { return nil }
            return NSImage(data: icns)

        case .WindowsPE:
            guard let ico = WindowsIcon.ico(at: meta.url) else { return nil }
            return NSImage(data: ico)

        default:
            return nil
        }
    }

    /// Le righe che descrivono il file, sotto il nome.
    ///
    /// Di un programma del 1992 le cose che dicono qualcosa sono poche: cosa
    /// dichiara di essere, quanto pesano le sue due metà, e quante risorse ha
    /// dentro. L'elenco dei tipi sta altrove, perché è lungo mezza pagina.
    ///
    /// Ogni riga si porta dietro sia l'etichetta sia la forma distesa: quale
    /// delle due si vede lo decide lo stile scelto per il pannello.
    static func summaryLines(for meta: MetaInfo) -> [Riga] {
        switch meta.type {
        case .ClassicMac:   return righeClassiche(meta.url)
        case .WindowsPE:    return righeWindows(meta.url)
        default:            return []
        }
    }

    /// I tipi di risorsa che il file contiene, per la sezione dedicata.
    static func resourceTypes(for meta: MetaInfo) -> [String] {
        guard meta.type == .ClassicMac,
              let raw = ClassicIcon.resourceFork(of: meta.url),
              let fork = ClassicIcon.Fork(raw)
        else { return [] }
        return fork.resources.keys.sorted()
    }

    private static func righeClassiche(_ url: URL) -> [Riga] {
        var righe: [Riga] = []

        let type = ClassicIcon.fileType(of: url) ?? "-"
        let creator = ClassicIcon.fileCreator(of: url) ?? "-"
        righe.append(Riga(String(localized: "Type e creator", bundle: QLMBundle.framework), "\(type) / \(creator)",
                          disteso: "Type \(type), creator \(creator)"))

        let dati = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        righe.append(Riga(String(localized: "Fork dati", bundle: QLMBundle.framework), misura(dati)))

        guard let raw = ClassicIcon.resourceFork(of: url) else {
            righe.append(Riga(String(localized: "Fork di risorse", bundle: QLMBundle.framework), String(localized: "nessuno", bundle: QLMBundle.framework)))
            return righe
        }
        righe.append(Riga(String(localized: "Fork di risorse", bundle: QLMBundle.framework), misura(raw.count)))

        guard let fork = ClassicIcon.Fork(raw) else {
            righe.append(Riga.sola(String(localized: "Il fork di risorse non si legge", bundle: QLMBundle.framework)))
            return righe
        }
        let quante = fork.resources.values.reduce(0) { $0 + $1.count }
        righe.append(Riga(String(localized: "Risorse", bundle: QLMBundle.framework),
                          String(localized: "\(quante) in \(fork.resources.count) tipi", bundle: QLMBundle.framework),
                          disteso: String(localized: "\(quante) risorse in \(fork.resources.count) tipi", bundle: QLMBundle.framework)))
        return righe
    }

    private static func righeWindows(_ url: URL) -> [Riga] {
        var righe: [Riga] = []

        // Le informazioni di versione stanno in una risorsa del PE, quindi il
        // file va letto: se ne prende un pezzo, non tutto.
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let bytes = handle.readData(ofLength: 64 * 1024 * 1024)
            for (chiave, valore) in WindowsVersionInfo.read(from: bytes) where !valore.isEmpty {
                righe.append(Riga(chiave, valore))
            }
        }
        if let ico = WindowsIcon.ico(at: url), let img = NSImage(data: ico) {
            let misure = img.representations
                .map { "\($0.pixelsWide)×\($0.pixelsHigh)" }
                .joined(separator: " ")
            righe.append(Riga(String(localized: "Icone nel file", bundle: QLMBundle.framework), misure,
                              disteso: String(localized: "Icone nel file: \(misure)", bundle: QLMBundle.framework)))
        }
        return righe
    }

    /// «446 KB (446.330 byte)»: il tondo per farsi un'idea, il numero esatto
    /// perché su un file del 1992 i byte contano davvero — un fork cresciuto di
    /// duemila byte si vede solo così.
    private static func misura(_ byte: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        let esatto = NumberFormatter.localizedString(from: NSNumber(value: byte), number: .decimal)
        return "\(f.string(fromByteCount: Int64(byte))) (\(esatto) \(String(localized: "byte", bundle: QLMBundle.framework)))"
    }
}
