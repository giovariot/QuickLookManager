import Foundation
import AppKit
import os // OSLog

private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.giovariot.QuickLookManager",
                        category: "ClassicIconWriter")

/// Scrive nei file l'icona che le applicazioni classiche si portano già dentro,
/// nella forma che macOS legge ancora.
///
/// Serve per i volumi che **non** monta FuseMac — un HFS+ di Mac OS 9 aperto dal
/// driver di Apple, per dire. Lì il driver non è nostro: non si può inventare
/// niente al momento della lettura, e perché il Finder trovi l'icona l'icona
/// deve esserci davvero.
///
/// Quindi questo **scrive**, e non è un dettaglio da nascondere in una nota. Il
/// gesto è però il meno invasivo che si possa fare:
///
/// - **è un'aggiunta.** La sezione dati del fork viene ricopiata intatta e la
///   risorsa nuova accodata dopo, così ogni offset che la mappa già contiene
///   resta valido. Verificato su applicazioni vere: 643 e 716 risorse tornano
///   byte per byte.
/// - **si controlla prima di scrivere.** Il fork nuovo si ricostruisce in
///   memoria, si rilegge, e se una sola risorsa originale non torna identica il
///   file non viene toccato.
/// - **è reversibile.** Il fork originale resta in un attributo di servizio, e
///   `revert` lo rimette esattamente com'era.
/// - **la data non cambia.** La `mtime` viene ripristinata dopo la scrittura:
///   su file del 1992 è metadato storico, e perderlo silenziosamente sarebbe un
///   danno più duraturo dell'icona guadagnata.
///
/// Quello che invece non fa mai: toccare un file che ha già un'icona
/// personalizzata sua. Quella è la scelta di chi possiede il file.
/// **Nota: questo non è un aggiramento, è il meccanismo di Apple.**
/// `NSWorkspace.setIcon(_:forFile:)` -- l'API documentata per dare un'icona a
/// un file -- fa esattamente questo. Misurato chiamandola su una copia dello
/// stesso programma: accoda una risorsa `icns` al fork, accende il bit
/// dell'icona personalizzata nel FinderInfo, e lascia `type` e `creator` dove
/// sono (`APPL`/`PNnu`, intatti). Quello che qui si fa in più è tenere da parte
/// il fork originale, per poter tornare indietro.
///
enum ClassicIconWriter {

    /// Dove si conserva il fork di partenza, per poter tornare indietro.
    static let backupAttribute = "it.local.classicicons.fork-originale"

    /// Il nome che aveva questo attributo quando il codice stava dentro
    /// MountedMenuBar. Si legge ancora, perché i file trattati allora se lo
    /// portano addosso e devono poter tornare indietro; si scrive solo quello
    /// nuovo.
    static let backupAttributeVecchio = "it.local.mountedmenubar.fork-originale"

    /// `kHasCustomIcon`: bit 10 dei flag del Finder, cioè `0x0400`, cioè il bit
    /// `0x04` del byte alto — che nel FinderInfo è il byte 8.
    private static let customIconFlagByte = 8
    private static let customIconFlagMask: UInt8 = 0x04

    /// I limiti del formato del fork di risorse, che non sono i limiti del file.
    ///
    /// Il fork di risorse è del 1984 e i suoi campi sono stretti: gli offset
    /// delle risorse dentro la sezione dati stanno in **tre byte**, e gli
    /// offset dentro la mappa in **due**. Il file può essere lungo quanto gli
    /// pare — il filesystem di oggi non se ne accorge — ma un fork che sfora
    /// quei campi non è più leggibile: i bit in eccesso si perdono e la mappa
    /// finisce per indirizzare il posto sbagliato.
    ///
    /// E qui il posto sbagliato non è un'icona storta: è un fork corrotto su un
    /// file che magari è l'unica copia rimasta di un programma del 1992. La
    /// scrittura si ferma prima, e il file resta com'è. Un'icona non vale
    /// questo.
    enum Limite {
        /// Offset di una risorsa nella sezione dati: 24 bit.
        static let dati = 0xFF_FFFF
        /// Offset dentro la mappa — lista dei tipi, lista dei nomi, liste dei
        /// riferimenti: 16 bit.
        static let mappa = 0xFFFF
        /// I conteggi (tipi, e risorse per tipo) stanno in 16 bit, meno uno.
        static let conteggio = 0x1_0000
    }

    /// Perché un fork non si può scrivere.
    enum Impedimento: Error {
        /// Il fork che c'è non si legge: non lo si tocca di sicuro.
        case illeggibile(String)
        /// Ci starebbe nel file, non ci sta nel formato. Il file si lascia
        /// stare e si va avanti con gli altri: non è un guasto, è un file più
        /// grande di quanto il formato sappia indirizzare.
        case oltreIlFormato(String)

        var descrizione: String {
            switch self {
            case .illeggibile(let p):     return p
            case .oltreIlFormato(let p):  return p
            }
        }
    }

    struct Candidate {
        let url: URL
        let iconBytes: Int
        /// L'icona già calcolata da chi ha scelto il candidato: `write` non la
        /// rifà.
        var icon: Data? = nil
    }

    enum Outcome {
        case written(Int)          // quanti file
        case nothingToDo
        case failed(String)
    }

    // MARK: - Guardare senza toccare

    /// I file su cui il comando interverrebbe, senza scrivere niente.
    ///
    /// È volutamente separato dall'applicazione: prima si dice all'utente
    /// quanti file si toccherebbero, poi lui decide.
    static func plan(volume: URL, limit: Int = 5000) -> [Candidate] {
        var found: [Candidate] = []
        // Il database delle icone del disco, letto una volta sola: senza, i
        // documenti restano tutti fuori, ed e' la maggioranza dei file.
        let desktop = ClassicIcon.desktopDatabase(ofVolume: volume)
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walk = FileManager.default.enumerator(
            at: volume, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        else { return [] }

        for case let url as URL in walk {
            if found.count >= limit { break }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            guard let icon = candidateIcon(at: url, desktop: desktop) else { continue }
            found.append(Candidate(url: url, iconBytes: icon.count))
        }
        return found
    }

    /// L'icona che questo file guadagnerebbe, o `nil` se non è un candidato.
    static func candidateIcon(at url: URL, desktop: ClassicIcon.Fork?) -> Data? {
        let type = ClassicIcon.fileType(of: url)
        let raw = ClassicIcon.resourceFork(of: url)
        let fork = raw.flatMap(ClassicIcon.Fork.init)

        // Chi ha già la sua icona personalizzata non si tocca, qualunque sia.
        if let fork, ClassicIcon.custom(fork: fork) != nil { return nil }

        // Un'applicazione porta la propria, ed è la risposta più precisa che ci
        // sia. Il controllo sul tipo non è una formalità: il `Desktop` di ogni
        // disco è pieno di BNDL — essere il database delle icone è il suo
        // mestiere — e senza si finisce per dargli l'icona del primo programma
        // che ci si trova dentro.
        //
        // Il confronto passa da `isApplication` e non da `"APPL"` diretto,
        // perché su un volume montato dal nostro driver le applicazioni il tipo
        // `APPL` non ce l'hanno: il driver gliene dà uno privato apposta per non
        // farsi disegnare il divieto dal Finder. Con il confronto secco qui si
        // saltavano tutte.
        if ClassicIcon.isApplication(type), let fork,
           let icon = ClassicIcon.forApplication(fork: fork) {
            return icon
        }

        // Un eseguibile Windows non si tocca, e non per timidezza: la sua icona
        // il Finder la mostra gia' come miniatura, perche' `com.microsoft.
        // windows-executable` quel filtro lo passa — misurato chiamando
        // `QLThumbnailSupportsContentUTIAtSize`, che risponde si' per lui e no
        // solo per le applicazioni. Scrivergli l'icona nel fork servirebbe
        // soltanto a farla vedere un po' piu' grande, e non vale modificare un
        // file che arriva da un altro sistema operativo.
        //
        // Qui dentro finiscono solo i file dei vecchi dischi Macintosh, che una
        // via alternativa non ce l'hanno.

        // Altrimenti il database del volume, per creator e tipo.
        guard let desktop, let type, let creator = ClassicIcon.fileCreator(of: url),
              !type.isEmpty, !creator.isEmpty
        else { return nil }
        return ClassicIcon.forDocument(desktop: desktop, creator: creator, type: type)
    }

    // MARK: - File che non ci stanno

    /// I file già scartati perché il fork non ci sta nel formato, con la data
    /// di modifica di quando sono stati scartati. Finché il file non cambia la
    /// risposta non cambia: senza questo, ogni volta che una cartella viene
    /// aperta si rileggerebbe un fork di megabyte, lo si ricostruirebbe e lo si
    /// scarterebbe di nuovo.
    private static var fuoriFormato: [String: Date] = [:]
    private static let lucchettoFuoriFormato = NSLock()

    private static func dataDiModifica(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func ricordaFuoriFormato(_ url: URL) {
        guard let data = dataDiModifica(url) else { return }
        lucchettoFuoriFormato.lock()
        fuoriFormato[url.path] = data
        lucchettoFuoriFormato.unlock()
    }

    /// Questo file è già stato scartato per il formato, e da allora non è cambiato?
    static func giaFuoriFormato(_ url: URL) -> Bool {
        lucchettoFuoriFormato.lock()
        defer { lucchettoFuoriFormato.unlock() }
        guard let visto = fuoriFormato[url.path] else { return false }
        return dataDiModifica(url) == visto
    }

    // MARK: - Scrivere

    static func apply(to volume: URL, candidates: [Candidate]) -> Outcome {
        guard !candidates.isEmpty else { return .nothingToDo }
        return apply(to: volume, candidates: candidates,
                     desktop: ClassicIcon.desktopDatabase(ofVolume: volume))
    }

    /// Come sopra, con il database delle icone già letto: chi scrive un file
    /// alla volta lo legge una volta per volume e lo passa qui, invece di
    /// rileggere centinaia di kilobyte a ogni file.
    static func apply(to volume: URL, candidates: [Candidate],
                      desktop: ClassicIcon.Fork?) -> Outcome {
        guard !candidates.isEmpty else { return .nothingToDo }

        var done = 0
        for candidate in candidates {
            switch write(at: candidate.url, desktop: desktop, icon: candidate.icon) {
            case .success:      done += 1
            case .skipped:      continue
            case .failure(let why):
                return .failed("\(candidate.url.lastPathComponent): \(why)"
                             + (done > 0 ? " — \(done) file già fatti restano fatti" : ""))
            }
        }
        return done > 0 ? .written(done) : .nothingToDo
    }

    private enum Step {
        case success
        case skipped
        case failure(String)
    }

    private static func write(at url: URL, desktop: ClassicIcon.Fork?, icon: Data? = nil) -> Step {
        guard let icns = icon ?? candidateIcon(at: url, desktop: desktop) else { return .skipped }

        let original = ClassicIcon.resourceFork(of: url)
        let parsed = original.flatMap(ClassicIcon.Fork.init)

        // Un documento di solito non ha nessun fork — la sua icona non è mai
        // stata nel file — quindi non c'è niente a cui accodare e il fork va
        // inventato per intero.
        let costruito: Result<Data, Impedimento>
        if let original, parsed != nil {
            costruito = appendCustomIcon(to: original, icns: icns)
        } else {
            costruito = forkWithOnlyIcon(icns)
        }

        let merged: Data
        switch costruito {
        case .success(let d):
            merged = d

        // Fuori dal formato non è un guasto: è un file più grande di quanto il
        // fork di risorse sappia indirizzare. Si lascia stare e si va avanti
        // con gli altri — fermare tutto il disco per uno vorrebbe dire togliere
        // l'icona anche a chi ce l'avrebbe potuta avere. Resta scritto nel
        // registro di sistema, perché un file saltato in silenzio non si
        // distingue da un file che non era un candidato.
        case .failure(.oltreIlFormato(let perche)):
            os_log(.info, log: log, "%{public}@: niente icona, %{public}@",
                   url.lastPathComponent, perche)
            ricordaFuoriFormato(url)
            return .skipped

        case .failure(let impedimento):
            return .failure(impedimento.descrizione)
        }

        // Il controllo che rende difendibile tutto il resto: si rilegge il fork
        // appena costruito e si pretende che ogni risorsa originale torni
        // identica. Se una sola non torna, il file non si tocca.
        if let parsed, !verify(original: parsed, rebuilt: merged) {
            return .failure(String(localized: "il fork ricostruito non corrisponde: non l'ho scritto", bundle: QLMBundle.framework))
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = attributes?[.modificationDate] as? Date

        // Il fork di partenza si conserva **prima** di toccare qualunque cosa, e
        // se non si riesce a conservarlo non si scrive: non si modifica ciò da
        // cui non si può tornare indietro.
        //
        // Per un documento che un fork non ce l'aveva si conserva un valore
        // vuoto. Non è un vuoto, è un'informazione: al ripristino quel fork va
        // tolto, non riscritto vuoto.
        if ForkBackup.fork(di: url) == nil,
           getxattrData(url, backupAttribute) == nil,
           getxattrData(url, backupAttributeVecchio) == nil {
            guard ForkBackup.conserva(fork: original ?? Data(), di: url) else {
                return .failure(String(localized: "non sono riuscito a conservare il fork originale", bundle: QLMBundle.framework))
            }
        }

        guard setxattrData(url, "com.apple.ResourceFork", merged) else {
            return .failure(String(localized: "scrittura del fork non riuscita", bundle: QLMBundle.framework))
        }

        // E adesso il controllo che conta più di tutti gli altri: si **rilegge
        // dal disco** quello che si è appena scritto, e si pretende che sia
        // quello che si voleva scrivere.
        //
        // Verificare il fork costruito in memoria non basta, ed è stato
        // misurato su file veri: quattro applicazioni di un Mac OS 9 sono
        // uscite dalla scrittura con la mappa delle risorse illeggibile da un
        // certo tipo in poi, mentre la stessa funzione, sugli stessi byte,
        // produceva un fork corretto che superava la verifica in memoria. Fra
        // «i byte giusti in mano» e «i byte giusti sul disco» c'è di mezzo il
        // filesystem, e lì qualcosa era andato storto.
        //
        // Se la rilettura non torna, il file viene rimesso com'era prima di
        // dire che è andata male: un'icona non vale un fork rovinato.
        var intatto = false
        if let riletto = ClassicIcon.resourceFork(of: url), riletto == merged,
           let rip = ClassicIcon.Fork(riletto) {
            // Byte per byte uguale a quello che volevamo, rileggibile come
            // fork, con dentro l'icona, e con ogni risorsa originale ancora al
            // suo posto.
            intatto = ClassicIcon.custom(fork: rip) != nil
                   && (parsed.map { verify(original: $0, rebuilt: riletto) } ?? true)
        }
        if !intatto {
            _ = revert(at: url)
            return .failure(String(localized: "riletto dal disco, il fork non corrisponde: l'ho rimesso com'era", bundle: QLMBundle.framework))
        }

        // E il flag che manda il Finder a cercarla. Un file che il FinderInfo
        // non ce l'ha — un `.exe`, per dire, che di classico non ha niente — se
        // lo vede creare: trentadue byte a zero con acceso quel bit e nient'
        // altro, che è il minimo per dire "l'icona guardala nel fork" senza
        // affermare un type o un creator che il file non ha.
        var info = getxattrData(url, "com.apple.FinderInfo") ?? Data(repeating: 0, count: 32)
        if info.count != 32 { info = Data(repeating: 0, count: 32) }
        info[customIconFlagByte] |= customIconFlagMask
        // Se il bit non si accende il Finder non cerca l'icona: il fork è già
        // scritto, ma per l'utente non è successo niente. Meglio dirlo e
        // rimettere il file com'era che contarlo fra quelli riusciti.
        guard setxattrData(url, "com.apple.FinderInfo", info) else {
            _ = revert(at: url)
            return .failure(String(localized: "non sono riuscito ad accendere il bit dell'icona: l'ho rimesso com'era", bundle: QLMBundle.framework))
        }

        if let mtime {
            try? FileManager.default.setAttributes([.modificationDate: mtime],
                                                   ofItemAtPath: url.path)
        }
        return .success
    }

    /// Rimette com'era tutto quello che è stato toccato su un volume.
    ///
    /// Il magazzino si legge una volta sola e poi si applica. Chiamare
    /// `revert(at:)` file per file rileggerebbe il magazzino intero a ogni file:
    /// su un disco con cento applicazioni sono diecimila letture di un file che
    /// pesa decine di megabyte.
    ///
    /// Torna quanti file sono tornati al loro stato e quanti no. Il magazzino si
    /// butta solo se non è rimasto indietro nessuno: finché un file non è
    /// tornato a posto, la sua copia serve ancora.
    ///
    /// Un file che qualcuno ha modificato **dopo** la nostra icona non si
    /// riporta indietro: ripristinare il fork di partenza cancellerebbe il suo
    /// lavoro. Di quel file si spegne soltanto il bit dell'icona personalizzata,
    /// che è l'unica cosa nostra, e si conta fra i `lasciati`.
    ///
    /// `avanzamento` riceve (fatti finora, totale) e `annullato` si chiede prima
    /// di ogni file: chi ha un'interfaccia può mostrare una barra e lasciare
    /// fermare il lavoro. Fermarsi non butta il magazzino: i file non ancora
    /// toccati ne hanno bisogno, e quelli già fatti si ripassano senza danno.
    static func restoreAll(onVolume volume: URL,
                           avanzamento: ((Int, Int) -> Void)? = nil,
                           annullato: (() -> Bool)? = nil)
        -> (fatti: Int, falliti: Int, lasciati: Int, interrotto: Bool) {
        let voci = ForkBackup.contenuto(delVolumeDi: volume)
        guard !voci.isEmpty else { return (0, 0, 0, false) }

        // L'agente tace mentre si lavora: le scritture di qui sono eventi sul
        // disco, e senza il segno rimetterebbe le icone appena tolte.
        ForkBackup.segnaRipristino(delVolumeDi: volume)
        defer { ForkBackup.segnaRipristino(delVolumeDi: volume) }

        let radice = (try? volume.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? volume
        var fatti = 0, falliti = 0, lasciati = 0
        var interrotto = false

        for (indice, voce) in voci.enumerated() {
            if annullato?() == true { interrotto = true; break }
            avanzamento?(indice, voci.count)
            // Il magazzino sta sul disco, e un disco può essere di chiunque.
            guard let url = ForkBackup.urlSicuro(percorso: voce.percorso, radice: radice) else {
                if !FileManager.default.fileExists(atPath: radice.appendingPathComponent(voce.percorso).path) {
                    // Sparito nel frattempo: non è un fallimento, non c'è più
                    // niente da rimettere a posto.
                    fatti += 1
                } else {
                    os_log(.error, log: log, "magazzino: percorso non valido, ignorato: %{public}@",
                           voce.percorso)
                }
                continue
            }
            switch rimetti(fork: voce.fork, in: url, soloSeNostro: true) {
            case .ripristinato:  fatti += 1
            case .soloMetadato:  lasciati += 1
            case .fallito:       falliti += 1
            }
        }

        avanzamento?(voci.count, voci.count)
        if falliti == 0 && !interrotto { ForkBackup.svuota(ilVolumeDi: volume) }
        return (fatti, falliti, lasciati, interrotto)
    }

    private enum Rimesso {
        /// Il fork è tornato quello di partenza.
        case ripristinato
        /// Il fork è stato modificato dopo di noi: non si è toccato, e si è
        /// spento soltanto il bit dell'icona.
        case soloMetadato
        case fallito
    }

    /// Il fork che c'è adesso è ancora quello che abbiamo scritto noi?
    ///
    /// Lo è se ogni risorsa dell'originale è al suo posto, identica, e l'unica
    /// risorsa in più è la nostra icona. Qualunque altra differenza vuol dire
    /// che il file è stato salvato di nuovo da qualcuno dopo di noi.
    private static func forkAncoraNostro(attuale: Data, originale: Data) -> Bool {
        guard let ora = ClassicIcon.Fork(attuale) else { return false }
        let prima = originale.isEmpty ? nil : ClassicIcon.Fork(originale)

        if let prima {
            for (tipo, voci) in prima.resources {
                for (id, blob) in voci {
                    guard ora.data(type: tipo, id: id) == blob else { return false }
                }
            }
        }
        for (tipo, voci) in ora.resources {
            for (id, blob) in voci {
                if tipo == "icns" && id == -16455 { continue }
                guard prima?.data(type: tipo, id: id) == blob else { return false }
            }
        }
        return true
    }

    /// Spegne il bit dell'icona personalizzata. `true` se non c'era niente da
    /// spegnere o se si è spento.
    private static func spegniBitIcona(_ url: URL) -> Bool {
        guard var info = getxattrData(url, "com.apple.FinderInfo"), info.count == 32 else { return true }
        guard info[customIconFlagByte] & customIconFlagMask != 0 else { return true }
        info[customIconFlagByte] &= ~customIconFlagMask
        return setxattrData(url, "com.apple.FinderInfo", info)
    }

    /// Rimette un fork al suo posto e spegne il bit dell'icona.
    ///
    /// Un fork vuoto vuol dire che prima non c'era: allora l'attributo va tolto,
    /// non riscritto vuoto.
    ///
    /// Con `soloSeNostro` — il ripristino chiesto dall'utente — il fork si
    /// rimette solo se è ancora quello scritto da noi. Senza — la marcia
    /// indietro di una scrittura appena fallita — si rimette comunque: il fork
    /// che c'è lo abbiamo appena scritto noi, ed è proprio quello da buttare.
    private static func rimetti(fork original: Data, in url: URL, soloSeNostro: Bool) -> Rimesso {
        let attuale = getxattrData(url, "com.apple.ResourceFork")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date

        if soloSeNostro {
            let nostro: Bool
            if let attuale, !attuale.isEmpty {
                nostro = forkAncoraNostro(attuale: attuale, originale: original)
            } else {
                // Nessun fork: se prima non c'era non c'è niente da rimettere;
                // se c'era, qualcuno lo ha tolto e non lo resuscitiamo.
                nostro = original.isEmpty
            }
            if !nostro {
                guard spegniBitIcona(url) else { return .fallito }
                _ = url.withUnsafeFileSystemRepresentation { removexattr($0, backupAttribute, 0) }
                _ = url.withUnsafeFileSystemRepresentation { removexattr($0, backupAttributeVecchio, 0) }
                return .soloMetadato
            }
        }

        // L'attributo si toglie sempre prima di riscriverlo. Scrivendoci sopra
        // un valore più corto il fork non si accorcia: restano in coda i byte
        // della versione precedente, e il file non torna quello di prima.
        // Misurato — dopo un ripristino il fork era ancora 237.123 byte invece
        // di 232.230, con 4.893 byte di avanzo.
        _ = url.withUnsafeFileSystemRepresentation { removexattr($0, "com.apple.ResourceFork", 0) }
        if !original.isEmpty, !setxattrData(url, "com.apple.ResourceFork", original) {
            // Il fork di prima non si riscrive: si rimette almeno quello che
            // c'era un momento fa, invece di lasciare il file senza.
            if let attuale { _ = setxattrData(url, "com.apple.ResourceFork", attuale) }
            return .fallito
        }
        guard spegniBitIcona(url) else { return .fallito }
        _ = url.withUnsafeFileSystemRepresentation { removexattr($0, backupAttribute, 0) }
        _ = url.withUnsafeFileSystemRepresentation { removexattr($0, backupAttributeVecchio, 0) }

        if let mtime {
            try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
        return .ripristinato
    }

    /// Rimette il file esattamente com'era, dal fork conservato.
    @discardableResult
    static func revert(at url: URL) -> Bool {
        // Il magazzino del volume prima di tutto; gli attributi sul file dopo,
        // perché i file trattati prima che il magazzino esistesse se li portano
        // ancora addosso e devono poter tornare indietro anche loro.
        guard let original = ForkBackup.fork(di: url)
                          ?? getxattrData(url, backupAttribute)
                          ?? getxattrData(url, backupAttributeVecchio) else { return false }
        return rimetti(fork: original, in: url, soloSeNostro: false) == .ripristinato
    }

    // MARK: - Il fork, per aggiunta

    /// Il fork con la risorsa `icns` −16455 accodata.
    ///
    /// Per aggiunta e non per ricostruzione, e la differenza è misurabile:
    /// ricostruendo da una rappresentazione parsificata i blocchi dati condivisi
    /// fra più risorse vengono duplicati, e un fork di 446 KB ne diventa 697 per
    /// un'icona da 2,6 KB. Accodando, cresce di 2.320 byte.
    static func appendCustomIcon(to fork: Data, icns: Data) -> Result<Data, Impedimento> {
        guard fork.count >= 16 + 30, !icns.isEmpty else {
            return .failure(.illeggibile("il fork è troppo corto per essere un fork"))
        }

        func be32(_ o: Int) -> Int {
            Int(fork[fork.startIndex + o]) << 24 | Int(fork[fork.startIndex + o + 1]) << 16
          | Int(fork[fork.startIndex + o + 2]) << 8 | Int(fork[fork.startIndex + o + 3])
        }
        func be16(_ o: Int) -> Int {
            Int(fork[fork.startIndex + o]) << 8 | Int(fork[fork.startIndex + o + 1])
        }

        let dataOff = be32(0), mapOff = be32(4), dataLen = be32(8), mapLen = be32(12)
        guard dataOff + dataLen <= fork.count, mapOff + mapLen <= fork.count,
              mapLen >= 30 else {
            return .failure(.illeggibile("l'intestazione del fork indirizza fuori dal fork"))
        }

        let typeListOff = be16(mapOff + 24), nameListOff = be16(mapOff + 26)
        let typeList = mapOff + typeListOff
        guard typeList + 2 <= fork.count else {
            return .failure(.illeggibile("la lista dei tipi cade fuori dal fork"))
        }
        let typeCount = be16(typeList) + 1

        // Tipi e conteggi, e se un tipo 'icns' c'è già.
        var types: [(type: [UInt8], count: Int, refOff: Int)] = []
        var icnsIndex: Int?
        for t in 0..<typeCount {
            let e = typeList + 2 + t * 8
            guard e + 8 <= fork.count else {
                return .failure(.illeggibile("la voce del tipo \(t) cade fuori dal fork"))
            }
            let raw = Array(fork[(fork.startIndex + e)..<(fork.startIndex + e + 4)])
            let count = be16(e + 4) + 1
            let refOff = be16(e + 6)
            if raw == Array("icns".utf8) { icnsIndex = t }
            types.append((raw, count, refOff))
        }

        let newTypeCount = typeCount + (icnsIndex == nil ? 1 : 0)
        let totalRefs = types.reduce(1) { $0 + $1.count }
        let namesLen = max(0, mapOff + mapLen - (mapOff + nameListOff))

        let typeArea = 2 + newTypeCount * 8
        let refArea = totalRefs * 12
        let newMapLen = 28 + typeArea + refArea + namesLen
        let newDataLen = dataLen + 4 + icns.count

        // La guardia di formato, prima di costruire qualunque cosa.
        //
        // Senza, i numeri troppo grandi non si lamentano: `emitIconRef` scrive
        // l'offset dell'icona in tre byte e `put16` gli offset della mappa in
        // due, e i bit in eccesso spariscono in silenzio. Il fork che ne esce si
        // scrive benissimo e punta al posto sbagliato — cioè esattamente il
        // guasto da cui questo file si difende con la rilettura dal disco, ma
        // stavolta prodotto da noi e per bene.
        if newDataLen > Limite.dati {
            return .failure(.oltreIlFormato(
                "i dati del fork arriverebbero a \(newDataLen) byte: gli offset delle "
              + "risorse ne indirizzano \(Limite.dati)"))
        }
        if newMapLen > Limite.mappa {
            return .failure(.oltreIlFormato(
                "la mappa del fork arriverebbe a \(newMapLen) byte: gli offset dentro "
              + "la mappa ne indirizzano \(Limite.mappa)"))
        }
        if newTypeCount > Limite.conteggio {
            return .failure(.oltreIlFormato(
                "il fork arriverebbe a \(newTypeCount) tipi di risorsa, e il conteggio "
              + "sta in sedici bit"))
        }
        if let icnsIndex, types[icnsIndex].count + 1 > Limite.conteggio {
            return .failure(.oltreIlFormato(
                "il tipo icns arriverebbe a \(types[icnsIndex].count + 1) risorse, e il "
              + "conteggio sta in sedici bit"))
        }

        // I dati restano dove stavano: si tiene l'offset del fork originale,
        // non un 256 di comodo, perché fra l'intestazione e i dati c'è un'area
        // riservata che in un file vero non è vuota — in SimpleText, venti byte
        // su duecentoquaranta — e va portata di là così com'è.
        var out = Data(count: dataOff + newDataLen + newMapLen)
        let nd = dataOff, nm = nd + newDataLen

        out.withUnsafeMutableBytes { rawOut in
            let o = rawOut.bindMemory(to: UInt8.self).baseAddress!
            func put32(_ at: Int, _ v: Int) {
                o[at] = UInt8(truncatingIfNeeded: v >> 24); o[at+1] = UInt8(truncatingIfNeeded: v >> 16)
                o[at+2] = UInt8(truncatingIfNeeded: v >> 8); o[at+3] = UInt8(truncatingIfNeeded: v)
            }
            func put16(_ at: Int, _ v: Int) {
                o[at] = UInt8(truncatingIfNeeded: v >> 8); o[at+1] = UInt8(truncatingIfNeeded: v)
            }

            put32(0, nd); put32(4, nm); put32(8, newDataLen); put32(12, newMapLen)

            fork.withUnsafeBytes { rawIn in
                let i = rawIn.bindMemory(to: UInt8.self).baseAddress!

                // L'area riservata fra intestazione e dati, tale e quale.
                if dataOff > 16 { memcpy(o + 16, i + 16, dataOff - 16) }

                memcpy(o + nd, i + dataOff, dataLen)

                put32(nd + dataLen, icns.count)
                icns.withUnsafeBytes { memcpy(o + nd + dataLen + 4, $0.baseAddress!, icns.count) }

                // I primi sedici byte della mappa sono una copia
                // dell'intestazione del fork, e il formato la vuole: chi legge
                // il fork con gli strumenti del 1984 se l'aspetta lì.
                memcpy(o + nm, o, 16)
                // Gli attributi della mappa sono del file, non nostri: si
                // portano di là come stanno.
                o[nm + 22] = i[mapOff + 22]
                o[nm + 23] = i[mapOff + 23]

                let ntl = 28, nnl = ntl + typeArea + refArea
                put16(nm + 24, ntl); put16(nm + 26, nnl)
                put16(nm + ntl, newTypeCount - 1)

                var entry = nm + ntl + 2
                var ref = nm + ntl + typeArea

                func emitIconRef() {
                    put16(ref, Int(UInt16(bitPattern: -16455)))
                    put16(ref + 2, 0xFFFF)
                    o[ref + 4] = 0
                    o[ref + 5] = UInt8(truncatingIfNeeded: dataLen >> 16)
                    o[ref + 6] = UInt8(truncatingIfNeeded: dataLen >> 8)
                    o[ref + 7] = UInt8(truncatingIfNeeded: dataLen)
                    ref += 12
                }

                for (t, info) in types.enumerated() {
                    for k in 0..<4 { o[entry + k] = info.type[k] }
                    let emit = info.count + (t == icnsIndex ? 1 : 0)
                    put16(entry + 4, emit - 1)
                    put16(entry + 6, ref - (nm + ntl))
                    entry += 8

                    // Le voci di riferimento passano verbatim: i loro offset
                    // indirizzano dati che non si sono mossi.
                    memcpy(o + ref, i + typeList + info.refOff, info.count * 12)
                    ref += info.count * 12
                    if t == icnsIndex { emitIconRef() }
                }

                if icnsIndex == nil {
                    for (k, c) in Array("icns".utf8).enumerated() { o[entry + k] = c }
                    put16(entry + 4, 0)
                    put16(entry + 6, ref - (nm + ntl))
                    emitIconRef()
                }

                if namesLen > 0 {
                    memcpy(o + nm + nnl, i + mapOff + nameListOff, namesLen)
                }
            }
        }
        return .success(out)
    }

    /// Un fork che contiene soltanto l'icona.
    ///
    /// Serve ai documenti, che un fork di risorse quasi mai ce l'hanno: la loro
    /// icona non e' mai stata nel file, stava nel Desktop del disco.
    static func forkWithOnlyIcon(_ icns: Data) -> Result<Data, Impedimento> {
        guard !icns.isEmpty else { return .failure(.illeggibile("icona vuota")) }

        let dataLen = 4 + icns.count
        let mapLen = 28 + 2 + 8 + 12            // intestazione, un tipo, un riferimento

        // Qui la mappa è di cinquanta byte fissi, quindi c'è un limite solo da
        // guardare: un'icona da più di sedici megabyte non sta negli offset a
        // ventiquattro bit della sezione dati.
        if dataLen > Limite.dati {
            return .failure(.oltreIlFormato(
                "i dati del fork sarebbero \(dataLen) byte: gli offset delle risorse "
              + "ne indirizzano \(Limite.dati)"))
        }
        var out = Data(count: 256 + dataLen + mapLen)
        let nd = 256, nm = nd + dataLen

        out.withUnsafeMutableBytes { raw in
            let o = raw.bindMemory(to: UInt8.self).baseAddress!
            func put32(_ at: Int, _ v: Int) {
                o[at] = UInt8(truncatingIfNeeded: v >> 24); o[at+1] = UInt8(truncatingIfNeeded: v >> 16)
                o[at+2] = UInt8(truncatingIfNeeded: v >> 8); o[at+3] = UInt8(truncatingIfNeeded: v)
            }
            func put16(_ at: Int, _ v: Int) {
                o[at] = UInt8(truncatingIfNeeded: v >> 8); o[at+1] = UInt8(truncatingIfNeeded: v)
            }
            put32(0, nd); put32(4, nm); put32(8, dataLen); put32(12, mapLen)
            put32(nd, icns.count)
            icns.withUnsafeBytes { memcpy(o + nd + 4, $0.baseAddress!, icns.count) }

            let tl = 28
            put16(nm + 24, tl)
            put16(nm + 26, tl + 2 + 8 + 12)     // lista dei nomi, vuota
            put16(nm + tl, 0)                   // un tipo
            for (k, c) in Array("icns".utf8).enumerated() { o[nm + tl + 2 + k] = c }
            put16(nm + tl + 6, 0)               // una risorsa
            put16(nm + tl + 8, 2 + 8)
            let ref = nm + tl + 2 + 8
            put16(ref, Int(UInt16(bitPattern: -16455)))
            put16(ref + 2, 0xFFFF)
            o[ref + 4] = 0                      // nessun attributo, offset 0
        }
        return .success(out)
    }

    /// Ogni risorsa dell'originale torna identica nel fork ricostruito?
    static func verify(original: ClassicIcon.Fork, rebuilt: Data) -> Bool {
        guard let after = ClassicIcon.Fork(rebuilt) else { return false }
        for (type, items) in original.resources {
            for (id, blob) in items {
                guard let now = after.data(type: type, id: id), now == blob else { return false }
            }
        }
        return true
    }

    // MARK: - xattr

    private static func getxattrData(_ url: URL, _ name: String) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            let n = getxattr(path, name, nil, 0, 0, 0)
            // Attenzione alla differenza fra «non c'è» e «c'è ed è vuoto»:
            // getxattr torna -1 nel primo caso e 0 nel secondo. Confonderli
            // rendeva irreversibile la scrittura proprio sui file che prima un
            // fork non ce l'avevano — l'attributo col fork originale era vuoto,
            // veniva letto come assente, e `--ripristina` rispondeva che non
            // c'era niente da ripristinare.
            guard n >= 0 else { return nil }
            guard n > 0 else { return Data() }
            var buf = [UInt8](repeating: 0, count: n)
            guard getxattr(path, name, &buf, n, 0, 0) == n else { return nil }
            return Data(buf)
        }
    }

    private static func setxattrData(_ url: URL, _ name: String, _ value: Data) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            value.withUnsafeBytes { raw in
                setxattr(path, name, raw.baseAddress, value.count, 0, 0) == 0
            }
        }
    }
}
