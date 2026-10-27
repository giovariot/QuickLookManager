import Foundation

/// Il binario di un programma macOS: per quali processori è compilato, e da
/// quale sistema in poi gira.
///
/// Sono le due righe che in Apparency stanno subito sotto il nome, e vengono
/// dal file eseguibile, non dall'`Info.plist`: l'`Info.plist` dichiara
/// `LSMinimumSystemVersion` quando l'autore si è ricordato di scriverlo, il
/// binario invece se lo porta dentro sempre, messo lì dal compilatore.
///
/// Si leggono le intestazioni e i comandi di caricamento, che stanno in cima al
/// file: qualche kilobyte, non il programma intero.
enum MachO {

    struct Info {
        /// Come le scriverebbe Apple: «Apple Silicon — 64-bit», «Intel — 64-bit».
        let architetture: [String]
        /// Il sistema minimo, per esempio «14.0».
        let minOS: String?
        /// Con quale SDK è stato costruito.
        let sdk: String?
        /// Per quale piattaforma: macOS, iOS, Mac Catalyst…
        let piattaforma: String?
    }

    // Le costanti stanno qui invece che venire da <mach-o/loader.h>: sono
    // quattro numeri che non cambiano dal 1993, e importarsi mezzo header per
    // averli vorrebbe dire anche portarsi dietro le sue strutture, che in
    // Swift si leggono peggio dei byte.
    private static let FAT_MAGIC: UInt32 = 0xcafe_babe      // big-endian sul disco
    private static let FAT_MAGIC_64: UInt32 = 0xcafe_babf
    private static let MH_MAGIC_64: UInt32 = 0xfeed_facf
    private static let MH_MAGIC_32: UInt32 = 0xfeed_face
    private static let MH_CIGAM_64: UInt32 = 0xcffa_edfe    // little-endian, il caso normale
    private static let MH_CIGAM_32: UInt32 = 0xcefa_edfe

    private static let LC_VERSION_MIN_MACOSX: UInt32 = 0x24
    private static let LC_VERSION_MIN_IPHONEOS: UInt32 = 0x25
    private static let LC_BUILD_VERSION: UInt32 = 0x32

    /// Quanto si legge dalla testa di ogni fetta: i comandi di caricamento
    /// stanno lì, e in un programma vero non arrivano a tanto.
    private static let testa = 256 * 1024

    // MARK: - Lettura

    /// Il binario di un pacchetto, o il file stesso se binario lo è già.
    static func info(perBundleOFile url: URL) -> Info? {
        if let exe = eseguibile(di: url) { return info(diBinario: exe) }
        return file(url) ? info(diBinario: url) : nil
    }

    /// L'eseguibile dentro un pacchetto.
    ///
    /// I pacchetti macOS hanno due forme, e tutte e due sono in uso:
    ///
    /// - **applicazioni e plug-in**: `Contents/MacOS/<CFBundleExecutable>`;
    /// - **framework**: `Versions/Current/<Nome>`, senza `Contents`, con
    ///   l'`Info.plist` in `Versions/Current/Resources`. È la forma del 1989 e
    ///   i framework la usano ancora tutti, compresi quelli di Apple.
    ///
    /// Il nome si chiede all'`Info.plist` e non si indovina dalla cartella:
    /// quasi sempre coincide col nome del pacchetto, ma «quasi sempre» qui
    /// vuol dire che ogni tanto il pannello resterebbe vuoto senza dire perché.
    static func eseguibile(di bundle: URL) -> URL? {
        let fm = FileManager.default
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)

        if fm.fileExists(atPath: contents.path) {
            let nome = nomeEseguibile(contents.appendingPathComponent("Info.plist"))
                    ?? bundle.deletingPathExtension().lastPathComponent
            let exe = contents.appendingPathComponent("MacOS/\(nome)")
            return file(exe) ? exe : nil
        }

        let versioni = bundle.appendingPathComponent("Versions/Current", isDirectory: true)
        if fm.fileExists(atPath: versioni.path) {
            let nome = nomeEseguibile(versioni.appendingPathComponent("Resources/Info.plist"))
                    ?? bundle.deletingPathExtension().lastPathComponent
            let exe = versioni.appendingPathComponent(nome)
            return file(exe) ? exe : nil
        }
        return nil
    }

    private static func nomeEseguibile(_ plist: URL) -> String? {
        (NSDictionary(contentsOf: plist) as? [String: Any])?["CFBundleExecutable"] as? String
    }

    /// Un file vero, non una cartella.
    ///
    /// Il controllo non è una cortesia: aprire una **cartella** con
    /// `FileHandle` riesce, e la lettura che viene dopo fa morire il processo.
    /// Misurato su `/System/Library/Frameworks/AppKit.framework`, che di
    /// `Contents` non ne ha: si finiva a leggere la cartella del pacchetto, e
    /// l'anteprima moriva invece di dire che il binario non l'aveva trovato.
    private static func file(_ url: URL) -> Bool {
        var cartella: ObjCBool = false
        let esiste = FileManager.default.fileExists(atPath: url.path, isDirectory: &cartella)
        return esiste && !cartella.boolValue
    }

    static func info(diBinario url: URL) -> Info? {
        guard file(url), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let intestazione = handle.readData(ofLength: 4096)
        guard intestazione.count >= 8 else { return nil }

        var architetture: [String] = []
        var minOS: String?, sdk: String?, piattaforma: String?

        var per: [String: (String?, String?, String?)] = [:]
        for fetta in fette(intestazione: intestazione, lunghezzaFile: dimensione(url)) {
            guard let (nome, versioni) = leggiFetta(handle, a: fetta) else { continue }
            architetture.append(nome)
            per[nome] = versioni
        }

        guard !architetture.isEmpty else { return nil }
        let ordinate = inOrdine(architetture)

        // Il sistema minimo si prende dalla fetta che il Mac di chi guarda
        // userebbe davvero. Non è pignoleria: le fette dello stesso file
        // dichiarano minimi diversi — /bin/ls chiede 11.0 su Apple Silicon e
        // 10.14 su Intel — e la riga risponde a «gira sul mio Mac?».
        if let prima = ordinate.first, let v = per[prima] {
            (minOS, sdk, piattaforma) = v
        }
        return Info(architetture: ordinate, minOS: minOS, sdk: sdk, piattaforma: piattaforma)
    }

    /// Prima quella su cui gira il Mac di chi guarda.
    ///
    /// Nell'intestazione grassa le fette stanno nell'ordine in cui il
    /// compilatore le ha messe, che di solito è Intel per prima per ragioni
    /// storiche. Chi legge il pannello però vuole sapere una cosa sola — «gira
    /// nativo da me?» — e la risposta deve stare sulla prima riga.
    private static func inOrdine(_ nomi: [String]) -> [String] {
        func peso(_ n: String) -> Int {
            if n.hasPrefix("Apple Silicon") { return 0 }
            if n.hasPrefix("Intel") { return 1 }
            if n.hasPrefix("PowerPC") { return 2 }
            return 3
        }
        // Senza il `distinti`, un binario con due fette arm64e — arm64e e
        // arm64e.x1 — mostrerebbe due righe identiche.
        var visti = Set<String>()
        let distinti = nomi.filter { visti.insert($0).inserted }
        return distinti.enumerated()
            .sorted { (peso($0.element), $0.offset) < (peso($1.element), $1.offset) }
            .map { $0.element }
    }

    private static func dimensione(_ url: URL) -> UInt64 {
        UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    // MARK: - Le fette

    private struct Fetta { let offset: UInt64; let cpu: UInt32; let sub: UInt32 }

    /// Un binario universale è un indice di fette; uno normale è una fetta
    /// sola, che comincia a zero.
    private static func fette(intestazione d: Data, lunghezzaFile: UInt64) -> [Fetta] {
        guard let magia = d.be32(0) else { return [] }

        if magia == FAT_MAGIC || magia == FAT_MAGIC_64 {
            let larga = magia == FAT_MAGIC_64
            guard let quante = d.be32(4), quante < 64 else { return [] }
            let passo = larga ? 32 : 20
            var out: [Fetta] = []
            for k in 0..<Int(quante) {
                let e = 8 + k * passo
                guard let cpu = d.be32(e), let sub = d.be32(e + 4) else { break }
                let off: UInt64
                if larga {
                    guard let hi = d.be32(e + 8), let lo = d.be32(e + 12) else { break }
                    off = UInt64(hi) << 32 | UInt64(lo)
                } else {
                    guard let o = d.be32(e + 8) else { break }
                    off = UInt64(o)
                }
                guard off < lunghezzaFile else { continue }
                out.append(Fetta(offset: off, cpu: cpu, sub: sub))
            }
            return out
        }

        if [MH_MAGIC_64, MH_MAGIC_32, MH_CIGAM_64, MH_CIGAM_32].contains(magia) {
            return [Fetta(offset: 0, cpu: 0, sub: 0)]
        }
        return []
    }

    /// Nome dell'architettura e versioni dichiarate, da una fetta sola.
    private static func leggiFetta(_ handle: FileHandle, a fetta: Fetta)
        -> (String, (String?, String?, String?))? {

        handle.seek(toFileOffset: fetta.offset)
        let d = handle.readData(ofLength: testa)
        // La magia si legge sempre come sta sul disco: sono i suoi stessi byte
        // a dire in che ordine è scritto il resto. CF FA ED FE apre un binario
        // little-endian — gli x86 e gli ARM di oggi — FE ED FA CF uno
        // big-endian, cioè i PowerPC dei Mac di ieri, che sono ancora in giro.
        guard d.count >= 32, let magia = d.be32(0) else { return nil }
        let piccolo = magia == MH_CIGAM_64 || magia == MH_CIGAM_32
        let grande  = magia == MH_MAGIC_64 || magia == MH_MAGIC_32
        guard piccolo || grande else { return nil }
        let a64 = magia == MH_CIGAM_64 || magia == MH_MAGIC_64

        func num(_ o: Int) -> UInt32? { piccolo ? d.le32(o) : d.be32(o) }

        guard let cpu = num(4), let sub = num(8), let ncmds = num(16) else { return nil }
        let nome = architettura(cpu: cpu, sub: sub)

        var versioni: (String?, String?, String?) = (nil, nil, nil)
        var at = a64 ? 32 : 28
        for _ in 0..<min(ncmds, 4096) {
            guard let cmd = num(at), let size = num(at + 4), size >= 8 else { break }
            switch cmd {
            case LC_BUILD_VERSION:
                if let p = num(at + 8), let minos = num(at + 12), let s = num(at + 16) {
                    versioni = (versione(minos), versione(s), piattaformaNome(p))
                }
            case LC_VERSION_MIN_MACOSX, LC_VERSION_MIN_IPHONEOS:
                if versioni.0 == nil, let minos = num(at + 8), let s = num(at + 12) {
                    versioni = (versione(minos), versione(s),
                                cmd == LC_VERSION_MIN_MACOSX ? "macOS" : "iOS")
                }
            default: break
            }
            at += Int(size)
            if at + 8 > d.count { break }
        }
        return (nome, versioni)
    }

    // MARK: - Traduzioni

    /// I nomi come li scrive Apple nelle sue finestre, non `arm64`/`x86_64`:
    /// il pannello lo legge chi vuole sapere se il programma gira sul suo Mac.
    static func architettura(cpu: UInt32, sub: UInt32) -> String {
        let a64: UInt32 = 0x0100_0000     // CPU_ARCH_ABI64
        switch cpu {
        // Il sottotipo porta in alto dei bit di capacità — l'arm64e nelle
        // intestazioni grasse si presenta come 0x8000_0002 — che vanno tolti
        // prima di guardare quale variante è. Senza la maschera, l'arm64e dei
        // programmi di sistema passava per un arm64 qualunque.
        //
        // Le varianti di arm64e non sono una sola: su macOS 27 `/bin/ls` ha una
        // terza fetta con sottotipo 0x8000_000c, che `lipo` chiama
        // «arm64e.x1» e di cui dice «unknown arm64 cpusubtype». A distinguerle
        // in due righe si guadagna niente — chi legge il pannello vuole sapere
        // se gira nativo — quindi vale il bit di capacità: se c'è, è arm64e.
        case 12 | a64:
            let autenticato = (sub & 0x8000_0000) != 0 || (sub & 0xFF) == 2
            return autenticato ? "Apple Silicon — 64-bit (arm64e)" : "Apple Silicon — 64-bit"
        case 12:        return "ARM — 32-bit"
        case 7 | a64:   return "Intel — 64-bit"
        case 7:         return "Intel — 32-bit"
        case 18 | a64:  return "PowerPC — 64-bit"
        case 18:        return "PowerPC"
        case 0:         return "sconosciuta"
        default:        return "cpu \(cpu)"
        }
    }

    /// I numeri di versione stanno impacchettati in trentadue bit: XXXX.YY.ZZ.
    static func versione(_ v: UInt32, completa: Bool = false) -> String? {
        guard v != 0 else { return nil }
        let x = v >> 16, y = (v >> 8) & 0xFF, z = v & 0xFF
        return (z == 0 && !completa) ? "\(x).\(y)" : "\(x).\(y).\(z)"
    }

    static func piattaformaNome(_ p: UInt32) -> String? {
        switch p {
        case 1:  return "macOS"
        case 2:  return "iOS"
        case 3:  return "tvOS"
        case 4:  return "watchOS"
        case 6:  return "Mac Catalyst"
        case 7:  return "iOS Simulator"
        case 11: return "DriverKit"
        case 13: return "visionOS"
        default: return nil
        }
    }
}

private extension Data {
    func be32(_ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= count else { return nil }
        let b = startIndex + o
        return UInt32(self[b]) << 24 | UInt32(self[b+1]) << 16 | UInt32(self[b+2]) << 8 | UInt32(self[b+3])
    }

    func le32(_ o: Int) -> UInt32? {
        guard o >= 0, o + 4 <= count else { return nil }
        let b = startIndex + o
        return UInt32(self[b]) | UInt32(self[b+1]) << 8 | UInt32(self[b+2]) << 16 | UInt32(self[b+3]) << 24
    }
}
