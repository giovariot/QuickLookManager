import AppKit
import CoreServices
import os // OSLog

private let log = OSLog(subsystem: "com.giovariot.QuickLookManager", category: "agente")

/// L'agente che dà l'icona ai file dei vecchi dischi Macintosh.
///
/// **Perché non è più un'estensione del Finder.** Lo era, e il mestiere era lo
/// stesso: il Finder avvisava l'estensione delle cartelle aperte e lei dava
/// l'icona a quello che c'era dentro. Ma un'estensione Finder Sync, per ricevere
/// quegli avvisi, deve dichiarare le cartelle che osserva — e il Finder mette
/// nella barra laterale **l'icona dell'applicazione a cui l'estensione
/// appartiene, al posto di quella del disco**. È una funzione documentata e non
/// ha interruttore: o si osserva il disco e gli si cambia l'icona, o non lo si
/// osserva.
///
/// **Come fa senza il Finder.** Non percorre niente: ascolta il filesystem.
/// Ogni volume che vale la pena si prende un `FSEventStream`, e quando in una
/// cartella succede qualcosa — e aprire una cartella nel Finder è qualcosa: il
/// Finder ci scrive dentro il `.DS_Store` con la posizione delle icone — si
/// guarda **quella cartella e basta**, un livello solo.
///
/// Così il lavoro è lo stesso di prima: nessuna passeggiata sul disco, nessun
/// costo per le cartelle che nessuno apre.
public enum Agente {

    /// Quanto aspettare prima di riguardare la stessa cartella.
    ///
    /// Aprendo una cartella il Finder scrive, riscrive e risistema: gli eventi
    /// arrivano a raffica, e senza questo freno si rileggerebbe la stessa
    /// cartella dieci volte in due secondi.
    static let respiro: TimeInterval = 5

    private static let coda = DispatchQueue(label: "com.giovariot.QuickLookManager.agente", qos: .utility)
    private static let lucchetto = NSLock()

    /// Un flusso di eventi per volume, e il database delle icone di quel volume
    /// letto una volta sola.
    private static var flussi: [String: FSEventStreamRef] = [:]
    private static var scrivanie: [String: ClassicIcon.Fork?] = [:]
    private static var viste: [String: Date] = [:]
    /// I volumi che si stanno prendendo in carico: tra la richiesta e il
    /// momento in cui il flusso è registrato passa del tempo, e una seconda
    /// richiesta in mezzo creerebbe un secondo flusso, il primo mai fermato.
    private static var inCorso: Set<String> = []

    /// Quanto tacere su un volume dopo un ripristino. Le scritture del
    /// ripristino producono eventi che arrivano con un po' di ritardo
    /// (latenza del flusso più respiro): senza questa pausa l'agente
    /// rimetterebbe le icone appena tolte.
    static let silenzioDopoRipristino: TimeInterval = 15

    /// I dischi per cui si è già chiesto il permesso in questa sessione: si
    /// chiede una volta, non a ogni evento. «Più tardi» vuol dire che si
    /// richiede al prossimo montaggio, non subito dopo.
    private static var richiesti: Set<String> = []

    /// Oltre questo numero le cartelle ricordate in `viste` si potano.
    private static let massimoViste = 1000

    // MARK: - Avvio

    /// Avvia l'agente e non torna: lo chiama il programma `IconeAgent`.
    public static func esegui() -> Never {
        avvia()
        RunLoop.main.run()
        exit(0)
    }

    static func avvia() {
        for volume in volumiMontati() { prendiInCarico(volume) }

        let centro = NSWorkspace.shared.notificationCenter
        centro.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { avviso in
            guard let url = avviso.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            // Un attimo di respiro: appena montato, il volume può non aver
            // ancora finito di comparire.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { prendiInCarico(url) }
        }
        centro.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { avviso in
            guard let url = avviso.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            lascia(url)
        }
        // L'utente accende «Includi i volumi di rete» o risponde a una richiesta
        // di permesso: i volumi già montati si guardano adesso, non al prossimo
        // montaggio. (Spegnere o togliere un permesso non richiede niente:
        // `guarda` li controlla a ogni evento.)
        for nome in [VolumeClassico.notificaPreferenze, ConsensiDischi.notifica] {
            DistributedNotificationCenter.default().addObserver(
                forName: nome, object: nil, queue: .main) { _ in
                for volume in volumiMontati() { prendiInCarico(volume) }
            }
        }
        os_log(.info, log: log, "agente avviato")
    }

    private static func volumiMontati() -> [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                              options: [.skipHiddenVolumes]) ?? []
    }

    // MARK: - Un volume alla volta

    static func prendiInCarico(_ volume: URL) {
        let chiave = volume.standardizedFileURL.path
        lucchetto.lock()
        let gia = flussi[chiave] != nil || inCorso.contains(chiave)
        if !gia { inCorso.insert(chiave) }
        lucchetto.unlock()
        guard !gia else { return }

        coda.async {
            defer {
                lucchetto.lock()
                inCorso.remove(chiave)
                lucchetto.unlock()
            }
            guard VolumeClassico.daTrattare(volume: volume) else {
                os_log(.debug, log: log, "%{public}@: niente di classico, lasciato stare",
                       volume.lastPathComponent)
                return
            }

            // Il permesso, disco per disco: sul disco di qualcuno non si scrive
            // senza che sia stato chiesto. Chiesto una volta, si ricorda.
            switch ConsensiDischi.stato(volume) {
            case .consentito?:
                break
            case .rifiutato?:
                os_log(.info, log: log, "%{public}@: permesso negato, lasciato stare",
                       volume.lastPathComponent)
                return
            case nil:
                chiediPermesso(volume)
                return
            }

            // Il database delle icone del disco, letto una volta sola: senza, i
            // documenti restano tutti fuori, ed è la maggioranza dei file.
            let scrivania = ClassicIcon.desktopDatabase(ofVolume: volume)
            lucchetto.lock()
            scrivanie[chiave] = scrivania
            lucchetto.unlock()

            // La radice si guarda subito: è la cartella che si apre per prima.
            // Salvo su un disco che l'utente ha ripristinato: lì le icone
            // tornano solo quando il Finder apre una cartella, non perché il
            // disco è stato rimontato.
            if ForkBackup.ultimoRipristino(delVolumeDi: volume) == nil {
                let esito = IconeAutomatiche.cartella(volume, scrivania: scrivania, volume: volume)
                os_log(.info, log: log, "%{public}@: radice, %d file guardati, %d con l'icona nuova, %d falliti",
                       volume.lastPathComponent, esito.guardati, esito.scritti, esito.falliti)
            } else {
                os_log(.info, log: log, "%{public}@: già ripristinato, aspetto il Finder",
                       volume.lastPathComponent)
            }

            ascolta(volume)
        }
    }

    static func lascia(_ volume: URL) {
        let chiave = volume.standardizedFileURL.path
        lucchetto.lock()
        richiesti.remove(ConsensiDischi.identificativo(volume))
        let flusso = flussi.removeValue(forKey: chiave)
        scrivanie.removeValue(forKey: chiave)
        // Le cartelle di questo volume: il volume stesso, o un percorso che ci
        // sta dentro. Un semplice prefisso toglierebbe anche `/Volumes/AB`
        // smontando `/Volumes/A`.
        let radice = chiave.hasSuffix("/") ? chiave : chiave + "/"
        viste = viste.filter { $0.key != chiave && !$0.key.hasPrefix(radice) }
        lucchetto.unlock()

        if let flusso {
            FSEventStreamStop(flusso)
            FSEventStreamInvalidate(flusso)
            FSEventStreamRelease(flusso)
            os_log(.debug, log: log, "%{public}@: smontato, smesso di ascoltare",
                   volume.lastPathComponent)
        }
    }

    // MARK: - Il permesso

    /// Chiede all'applicazione di domandare all'utente. L'agente non ha finestre:
    /// la domanda la fa l'applicazione, che se non è aperta si apre.
    private static func chiediPermesso(_ volume: URL) {
        let id = ConsensiDischi.identificativo(volume)
        lucchetto.lock()
        let nuovo = richiesti.insert(id).inserted
        lucchetto.unlock()
        guard nuovo else { return }

        let nome = ConsensiDischi.nome(volume)
        os_log(.info, log: log, "%{public}@: chiedo il permesso", nome)

        // Se l'applicazione è aperta, le arriva la notifica; se non lo è, la si
        // apre con la richiesta negli argomenti (la notifica andrebbe persa).
        DistributedNotificationCenter.default().postNotificationName(
            ConsensiDischi.notificaRichiesta, object: nil,
            userInfo: ["id": id, "nome": nome, "percorso": volume.path],
            deliverImmediately: true)

        let aperta = !NSRunningApplication.runningApplications(
            withBundleIdentifier: ConsensiDischi.identificativoApp).isEmpty
        guard !aperta, let app = urlDellApplicazione() else { return }

        let configurazione = NSWorkspace.OpenConfiguration()
        configurazione.activates = true
        configurazione.arguments = ["--consenso", id, nome, volume.path]
        NSWorkspace.shared.openApplication(at: app, configuration: configurazione) { _, errore in
            if let errore {
                os_log(.error, log: log, "non riesco ad aprire l'applicazione: %{public}@",
                       errore.localizedDescription)
            }
        }
    }

    /// L'agente sta in `QLAppBundle.app/Contents/MacOS/`: l'applicazione è tre
    /// livelli sopra l'eseguibile.
    private static func urlDellApplicazione() -> URL? {
        guard let eseguibile = Bundle.main.executableURL else { return nil }
        let app = eseguibile.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }

    // MARK: - Ascoltare invece di percorrere

    private static func ascolta(_ volume: URL) {
        let chiave = volume.standardizedFileURL.path
        var contesto = FSEventStreamContext()

        // I percorsi arrivano come un vettore di stringhe C: si legge alla
        // maniera di C, perché così li dà CoreServices.
        let richiamo: FSEventStreamCallback = { _, _, quanti, percorsi, _, _ in
            let elenco = percorsi.bindMemory(to: UnsafePointer<CChar>.self, capacity: quanti)
            for k in 0..<quanti {
                Agente.guarda(String(cString: elenco[k]))
            }
        }

        guard let flusso = FSEventStreamCreate(
            kCFAllocatorDefault, richiamo, &contesto,
            [chiave] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,   // un secondo di attesa: gli eventi arrivano a gruppi
            UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot))
        else {
            os_log(.error, log: log, "%{public}@: non riesco ad ascoltare il volume", chiave)
            return
        }

        FSEventStreamSetDispatchQueue(flusso, coda)
        FSEventStreamStart(flusso)

        lucchetto.lock()
        flussi[chiave] = flusso
        lucchetto.unlock()
        os_log(.info, log: log, "%{public}@: ascolto le cartelle che si aprono", chiave)
    }

    /// Un evento è arrivato: si guarda **quella cartella**, un livello solo.
    static func guarda(_ percorso: String) {
        var st = stat()
        guard lstat(percorso, &st) == 0 else { return }
        // L'evento può riguardare un file (il `.DS_Store` che il Finder scrive
        // aprendo la cartella, per esempio): la cartella è quella che lo
        // contiene.
        let cartella = (st.st_mode & S_IFMT) == S_IFDIR
            ? URL(fileURLWithPath: percorso, isDirectory: true)
            : URL(fileURLWithPath: percorso).deletingLastPathComponent()

        let chiaveCartella = cartella.standardizedFileURL.path
        guard let volume = (try? cartella.resourceValues(forKeys: [.volumeURLKey]))?.volume else { return }
        let chiaveVolume = volume.standardizedFileURL.path

        lucchetto.lock()
        let scrivania = scrivanie[chiaveVolume] ?? nil
        let vistaDiRecente = viste[chiaveCartella].map { Date().timeIntervalSince($0) < respiro } ?? false
        if !vistaDiRecente { viste[chiaveCartella] = Date() }
        // Su un agente che resta acceso per settimane l'elenco crescerebbe a
        // ogni cartella mai aperta: oltre il massimo si tengono solo le
        // cartelle viste da meno di un minuto.
        if viste.count > massimoViste {
            let limite = Date().addingTimeInterval(-60)
            viste = viste.filter { $0.value > limite }
        }
        let osservato = flussi[chiaveVolume] != nil
        lucchetto.unlock()

        guard osservato, !vistaDiRecente else { return }

        // Un volume di rete che l'utente non ha incluso: l'impostazione può
        // essere cambiata dopo che il flusso era partito.
        guard VolumeClassico.consentitoAutomaticamente(volume),
              ConsensiDischi.stato(volume) == .consentito else { return }

        // Dopo un ripristino si tace: questi eventi li ha prodotti il
        // ripristino stesso, non il Finder.
        if let ripristino = ForkBackup.ultimoRipristino(delVolumeDi: volume),
           Date().timeIntervalSince(ripristino) < silenzioDopoRipristino {
            return
        }

        let esito = IconeAutomatiche.cartella(cartella, scrivania: scrivania, volume: volume)
        if esito.scritti > 0 || esito.falliti > 0 {
            os_log(.info, log: log, "%{public}@: %d file con l'icona nuova, %d falliti (%{public}@)",
                   chiaveCartella, esito.scritti, esito.falliti, esito.primoErrore ?? "-")
        }
    }
}

