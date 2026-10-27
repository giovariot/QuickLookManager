import Foundation
import os // OSLog

private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.giovariot.QuickLookManager",
                        category: "ForkBackup")

/// Il fork originale di ogni file toccato, conservato fuori dal file.
///
/// **Perché non dentro il file.** Prima la copia stava in un attributo esteso
/// sul file stesso, ed è la soluzione più ovvia: il backup viaggia con ciò che
/// protegge. Ma due cose non funzionano. Su un volume montato da un driver FUSE
/// quell'attributo non sopravvive — il driver ne espone due soli, `FinderInfo`
/// e `ResourceFork` — quindi la scrittura diventava irreversibile proprio dove
/// serviva di più. E non c'è modo di dire «rimetti a posto tutto questo disco»
/// senza percorrerlo file per file cercando chi ha l'attributo.
///
/// Da cui un magazzino unico per volume: un file nella radice, invisibile, con
/// dentro tutti i fork originali. Da lì il ripristino di un disco intero è una
/// scelta in un pannello, non una battuta di caccia.
///
/// **Il formato.** Record in coda, uno dopo l'altro:
///
///     "OFBK" versione(4)
///     [ lunghezza percorso(4) | percorso UTF-8 | lunghezza fork(4) | fork | data(8) ]
///     [ … ]
///
/// Aggiungere è scrivere in fondo, e basta. Un formato che vada riscritto per
/// intero a ogni aggiunta — un plist, per dire — costerebbe, dopo cento file da
/// mezzo megabyte, cinquanta megabyte riscritti per ogni icona nuova. Qui costa
/// il record.
///
/// Un percorso può comparire più volte: vince l'ultimo, perché è l'ultimo stato
/// noto prima delle nostre modifiche. Un fork di lunghezza zero vuol dire «prima
/// non ce l'aveva», ed è un'informazione, non un vuoto: al ripristino quel fork
/// va tolto, non riscritto vuoto.
enum ForkBackup {

    /// Il nome del magazzino. Il punto iniziale lo nasconde al Finder di oggi;
    /// per i Mac di ieri serve altro — vedi `nascondi(_:)`.
    static let nome = ".OldForksBackup"

    private static let magia = Data("OFBK".utf8)
    private static let versione: UInt32 = 1

    // MARK: - Dove

    /// Il magazzino del volume che contiene questo file.
    ///
    /// Nella radice del volume, se ci si può scrivere. Se no — il caso del disco
    /// di avvio, dove `/` non è nostro — in una cartella dell'app, con il nome
    /// preso dall'identificativo del volume: così due dischi diversi non si
    /// mescolano e il ripristino sa sempre a chi appartiene ciò che trova.
    static func percorso(perVolumeDi url: URL) -> URL? {
        guard let radice = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
        else { return nil }

        let nella = radice.appendingPathComponent(nome)
        if FileManager.default.isWritableFile(atPath: radice.path) {
            return nella
        }
        return dentroLApp(perVolume: radice)
    }

    /// La cartella di ripiego, **la stessa per tutti e due**.
    ///
    /// Qui chi scrive e chi ripristina sono due programmi diversi: l'agente e
    /// l'applicazione, tutti e due in sandbox. E
    /// `FileManager.urls(for: .applicationSupportDirectory…)` a un programma in
    /// sandbox non risponde con la cartella di sistema ma con quella dentro il
    /// suo contenitore — `~/Library/Containers/…/Data/Library/Application
    /// Support`, e due programmi hanno due contenitori. Usandolo, l'agente
    /// conserverebbe i fork in un posto che l'applicazione non guarda mai:
    /// l'utente chiederebbe il ripristino e si sentirebbe rispondere che non
    /// c'è niente da rimettere a posto, con i suoi file modificati.
    ///
    /// Da cui la home vera, chiesta a `getpwuid` invece che a Foundation: nella
    /// sandbox `NSHomeDirectory()` è redirezionato al contenitore, `getpwuid`
    /// no. Scriverci è permesso perché l'agente ha l'eccezione su `/` e
    /// l'applicazione quella sulla cartella di supporto di QLAppBundle.
    private static func dentroLApp(perVolume radice: URL) -> URL? {
        guard let casa = homeVera() else { return nil }

        let cartella = casa.appendingPathComponent("Library/Application Support/QLAppBundle/ForkBackup",
                                                   isDirectory: true)
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)

        let id = (try? radice.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
              ?? radice.lastPathComponent
        return cartella.appendingPathComponent("\(id).forks")
    }

    private static func homeVera() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }

    // MARK: - Percorsi non fidati

    /// Il file del volume a cui un percorso del magazzino si riferisce, o `nil`
    /// se il percorso non sta dentro il volume.
    ///
    /// Il magazzino vive sul disco, e un disco può arrivare da chiunque: i suoi
    /// percorsi sono dati non fidati. Un `..`, un percorso assoluto o un
    /// collegamento simbolico che punta fuori farebbero togliere e riscrivere
    /// attributi di file che col disco non c'entrano.
    static func urlSicuro(percorso: String, radice: URL) -> URL? {
        guard !percorso.isEmpty, !percorso.hasPrefix("/"), !percorso.contains("\0") else { return nil }
        guard !percorso.split(separator: "/", omittingEmptySubsequences: false).contains("..") else { return nil }

        let base = radice.resolvingSymlinksInPath().path
        let prefisso = base.hasSuffix("/") ? base : base + "/"
        let url = radice.appendingPathComponent(percorso)
        guard url.resolvingSymlinksInPath().path.hasPrefix(prefisso) else { return nil }

        // Il file stesso deve essere un file vero, non un collegamento.
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return url
    }

    // MARK: - Dopo un ripristino

    /// Il segno che un ripristino è stato fatto su questo volume, e quando.
    ///
    /// Serve all'agente: il ripristino scrive sui file, le scritture producono
    /// eventi sul disco, e l'agente — che li ascolta — rimetterebbe le icone
    /// pochi secondi dopo. Per questo l'agente tace mentre il ripristino lavora
    /// e subito dopo, e su un disco già ripristinato aspetta che sia il Finder
    /// ad aprire una cartella, invece di rifare la radice appena montato.
    static func segnaRipristino(delVolumeDi url: URL) {
        guard let file = fileDelSegno(url) else { return }
        try? String(Date().timeIntervalSince1970).write(to: file, atomically: true, encoding: .utf8)
    }

    /// Quando è stato fatto l'ultimo ripristino su questo volume, se è stato fatto.
    static func ultimoRipristino(delVolumeDi url: URL) -> Date? {
        guard let file = fileDelSegno(url),
              let testo = try? String(contentsOf: file, encoding: .utf8),
              let secondi = TimeInterval(testo.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: secondi)
    }

    /// Toglie il segno. Serve ai test, che non devono lasciare file nella
    /// cartella dell'utente per ogni volume di prova.
    static func dimenticaRipristino(delVolumeDi url: URL) {
        guard let file = fileDelSegno(url) else { return }
        try? FileManager.default.removeItem(at: file)
    }

    private static func fileDelSegno(_ url: URL) -> URL? {
        guard let casa = homeVera() else { return nil }
        let radice = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? url
        let cartella = casa.appendingPathComponent("Library/Application Support/QLAppBundle/Ripristini",
                                                   isDirectory: true)
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let id = (try? radice.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
              ?? radice.lastPathComponent
        return cartella.appendingPathComponent("\(id).txt")
    }

    // MARK: - Scrivere

    /// Mette da parte il fork originale di un file. Torna `false` solo se non
    /// si è riusciti a scrivere, e allora il file non va toccato.
    @discardableResult
    static func conserva(fork: Data, di url: URL) -> Bool {
        guard let magazzino = percorso(perVolumeDi: url) else { return false }

        let fm = FileManager.default
        if !fm.fileExists(atPath: magazzino.path) {
            var intestazione = magia
            intestazione.appendBE32(versione)
            guard (try? intestazione.write(to: magazzino)) != nil else { return false }
            nascondi(magazzino)
        }

        // `write(contentsOf:)` e non `write(_:)`: il secondo, se la scrittura
        // fallisce (disco pieno, volume che sparisce), solleva un'eccezione di
        // Objective-C che Swift non intercetta e che uccide l'agente. Qui un
        // errore diventa `false`, e `false` vuol dire «il file non si tocca».
        guard let handle = try? FileHandle(forWritingTo: magazzino) else { return false }
        defer { try? handle.close() }
        do {
            let inizio = try handle.seekToEnd()
            do {
                try handle.write(contentsOf: record(fork: fork, percorso: relativo(url)))
                try handle.synchronize()
            } catch {
                // Un record scritto a metà fa fermare la lettura, e con lei
                // tutti i record che verrebbero dopo: si toglie.
                try? handle.truncate(atOffset: inizio)
                os_log(.error, log: log, "magazzino: scrittura non riuscita: %{public}@",
                       error.localizedDescription)
                return false
            }
        } catch {
            return false
        }
        return true
    }

    private static func record(fork: Data, percorso: String) -> Data {
        let bytes = Data(percorso.utf8)
        var r = Data()
        r.appendBE32(UInt32(bytes.count))
        r.append(bytes)
        r.appendBE32(UInt32(fork.count))
        r.append(fork)
        var quando = UInt64(Date().timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: &quando) { r.append(contentsOf: $0) }
        return r
    }

    /// Il percorso dentro il volume, senza il punto di montaggio: così il
    /// magazzino resta valido se il disco viene montato altrove, che è la
    /// norma — `/Volumes/Disco 1` la seconda volta.
    private static func relativo(_ url: URL) -> String {
        guard let radice = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
        else { return url.path }
        let r = radice.path.hasSuffix("/") ? radice.path : radice.path + "/"
        return url.path.hasPrefix(r) ? String(url.path.dropFirst(r.count)) : url.path
    }

    /// Accende il bit che rende un file invisibile al Finder — **anche a quello
    /// del 1992**.
    ///
    /// Il punto davanti al nome è una convenzione Unix: macOS la rispetta, un
    /// Mac OS classico non la conosce e il file lo vedrebbe eccome. Lì
    /// l'invisibilità è un bit nel FinderInfo, `kIsInvisible`, il 14° dei flag
    /// del Finder. Si accendono tutti e due, così il magazzino resta fuori dai
    /// piedi su qualunque sistema legga il disco.
    private static func nascondi(_ url: URL) {
        var info = [UInt8](repeating: 0, count: 32)
        info[8] |= 0x40                              // kIsInvisible, byte alto dei flag
        _ = url.withUnsafeFileSystemRepresentation { path in
            setxattr(path, "com.apple.FinderInfo", info, 32, 0, 0)
        }
        // E il flag di macOS, per il Finder di oggi.
        var valori = URLResourceValues()
        valori.isHidden = true
        var u = url
        try? u.setResourceValues(valori)
    }

    // MARK: - Leggere

    /// Tutto quello che il magazzino di questo volume contiene, con l'ultima
    /// versione di ogni percorso.
    static func contenuto(delVolumeDi url: URL) -> [(percorso: String, fork: Data, quando: Date)] {
        guard let magazzino = percorso(perVolumeDi: url),
              let d = try? Data(contentsOf: magazzino),
              d.count >= 8, d.prefix(4) == magia
        else { return [] }

        var ultimo: [String: (Data, Date)] = [:]
        var ordine: [String] = []
        var at = 8

        while at + 8 <= d.count {
            guard let lp = d.be32(at) else { break }
            let inizioPercorso = at + 4
            guard inizioPercorso + lp + 4 <= d.count,
                  let percorso = String(data: d.slice(inizioPercorso, lp), encoding: .utf8),
                  let lf = d.be32(inizioPercorso + lp)
            else { break }

            let inizioFork = inizioPercorso + lp + 4
            guard inizioFork + lf + 8 <= d.count else { break }

            let fork = d.slice(inizioFork, lf)
            let quando = Date(timeIntervalSince1970: TimeInterval(d.be64(inizioFork + lf) ?? 0))

            if ultimo[percorso] == nil { ordine.append(percorso) }
            ultimo[percorso] = (fork, quando)
            at = inizioFork + lf + 8
        }

        return ordine.compactMap { p in
            ultimo[p].map { (percorso: p, fork: $0.0, quando: $0.1) }
        }
    }

    /// Il fork conservato per un singolo file, se c'è.
    static func fork(di url: URL) -> Data? {
        let cercato = relativo(url)
        return contenuto(delVolumeDi: url).last { $0.percorso == cercato }?.fork
    }

    /// Quanti file risultano toccati su questo volume.
    static func quanti(sulVolumeDi url: URL) -> Int {
        contenuto(delVolumeDi: url).count
    }

    /// Butta via il magazzino, a ripristino finito.
    static func svuota(ilVolumeDi url: URL) {
        guard let magazzino = percorso(perVolumeDi: url) else { return }
        try? FileManager.default.removeItem(at: magazzino)
    }
}

private extension Data {
    mutating func appendBE32(_ v: UInt32) {
        append(contentsOf: [UInt8(truncatingIfNeeded: v >> 24), UInt8(truncatingIfNeeded: v >> 16),
                            UInt8(truncatingIfNeeded: v >> 8),  UInt8(truncatingIfNeeded: v)])
    }

    func be32(_ o: Int) -> Int? {
        guard o >= 0, o + 4 <= count else { return nil }
        let b = startIndex + o
        return Int(self[b]) << 24 | Int(self[b+1]) << 16 | Int(self[b+2]) << 8 | Int(self[b+3])
    }

    func be64(_ o: Int) -> UInt64? {
        guard o >= 0, o + 8 <= count else { return nil }
        var v: UInt64 = 0
        for k in 0..<8 { v = v << 8 | UInt64(self[startIndex + o + k]) }
        return v
    }

    func slice(_ o: Int, _ n: Int) -> Data {
        Data(self[(startIndex + o)..<(startIndex + o + n)])
    }
}
