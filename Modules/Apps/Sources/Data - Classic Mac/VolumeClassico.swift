import Foundation

/// Su questo volume c'è qualcosa di Macintosh classico?
///
/// La domanda non è oziosa: l'agente ascolta i volumi per dare l'icona ai file
/// classici, ma **un volume ascoltato non è gratis** — un flusso di eventi per
/// disco, e scritture di attributi su file che nessuno ha chiesto di toccare.
/// Un disco esterno di tutti i giorni non ha niente da guadagnarci.
///
/// Quindi si prende in carico un volume solo se c'è ragione di farlo. Due
/// indizi, tutti e due alla radice e a costo di una lettura di directory:
///
/// - il **database delle icone** (`Desktop DB`, `Desktop DF`, o il `Desktop` dei
///   System 6), da cui vengono le icone dei documenti e che nessun disco moderno
///   ha;
/// - un file con **type e creator classici** nel FinderInfo, che è quello che
///   rende un file un candidato.
///
/// (Prima dell'agente l'ascolto lo faceva un'estensione del Finder, e c'era un
/// motivo in più: ogni volume dichiarato si ritrovava nella barra laterale
/// l'icona dell'applicazione al posto della sua. L'estensione non c'è più; la
/// regola di scelta è rimasta.)
enum VolumeClassico {

    /// I nomi del database delle icone, per le versioni che ci interessano.
    static let databaseIcone = ["Desktop DB", "Desktop DF", "Desktop"]

    /// Quanti file della radice si guardano prima di arrendersi.
    ///
    /// Su un disco con migliaia di file in radice, l'indizio o si trova fra i
    /// primi o il disco è moderno. Guardarli tutti vorrebbe dire leggere il
    /// FinderInfo di migliaia di file ogni volta che si aggiorna l'elenco dei
    /// volumi osservati.
    static let quantiGuardare = 400

    /// Su questo volume ha senso scrivere?
    ///
    /// Due casi in cui la risposta è no, e per motivi diversi.
    ///
    /// **Sola lettura**: non si può scrivere, e non è un errore.
    ///
    /// **Volumi montati dai driver FUSE** (`macfuse_hfs`, `macfuse_mfs`): lì
    /// l'icona il driver la sintetizza già da sé, costruendo il fork in memoria
    /// quando il Finder lo chiede e senza scrivere un byte sull'immagine.
    /// Scriverci sopra sarebbe inutile, e sarebbe anche **irreversibile**: quei
    /// driver espongono due soli attributi estesi, `com.apple.FinderInfo` e
    /// `com.apple.ResourceFork`, quindi la copia del fork originale non
    /// verrebbe conservata. Misurato su un'immagine vera: dopo la scrittura il
    /// file aveva l'icona ma nessun backup, e il ripristino non aveva più
    /// niente a cui attingere.
    ///
    /// La regola generale è quella: non si scrive dove non si può tornare
    /// indietro.
    static func scrivibile(_ url: URL) -> Bool {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return false }
        if (fs.f_flags & UInt32(MNT_RDONLY)) != 0 { return false }

        let tipo = withUnsafeBytes(of: fs.f_fstypename) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        // "macfuse_hfs" e "macfuse_mfs" sono i nostri; il prefisso copre anche
        // gli altri filesystem FUSE, dove comunque non sappiamo cosa
        // sopravvive.
        if tipo.hasPrefix("macfuse") || tipo.hasPrefix("fuse") { return false }
        return true
    }

    /// Vale la pena occuparsi di questo volume?
    static func daTrattare(volume: URL) -> Bool {
        scrivibile(volume) && consentitoAutomaticamente(volume) && contiene(volume: volume)
    }

    // MARK: - Volumi di rete

    /// Il volume è montato da un server (SMB, AFP, NFS, WebDAV…) e non è un
    /// disco di questo Mac?
    ///
    /// `MNT_LOCAL` è il flag con cui il kernel dice che il filesystem sta su
    /// un'unità locale: i volumi di rete non ce l'hanno. Immagini disco e dischi
    /// esterni sì.
    static func eDiRete(_ url: URL) -> Bool {
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return false }
        return (fs.f_flags & UInt32(MNT_LOCAL)) == 0
    }

    /// L'impostazione «Includi i volumi di rete». Spenta di default: scrivere
    /// attributi in background su un server condiviso è una cosa che l'utente
    /// deve aver chiesto.
    ///
    /// Vale per il lavoro **automatico** (l'agente). Il comando «Dai le icone a
    /// un disco…» l'utente lo dà scegliendo il disco, e quella scelta basta.
    static var includeVolumiDiRete: Bool {
        guard let url = fileDellaPreferenza(),
              let testo = try? String(contentsOf: url, encoding: .utf8)
        else { return false }
        return testo.trimmingCharacters(in: .whitespacesAndNewlines) == "si"
    }

    /// Scrive l'impostazione e avvisa l'agente, che altrimenti la rileggerebbe
    /// solo al montaggio successivo. `false` se non si è riusciti a scrivere.
    @discardableResult
    static func impostaVolumiDiRete(_ valore: Bool) -> Bool {
        guard let url = fileDellaPreferenza() else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard (try? (valore ? "si" : "no").write(to: url, atomically: true, encoding: .utf8)) != nil
        else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            notificaPreferenze, object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    /// L'agente può occuparsi di questo volume senza che nessuno glielo chieda?
    static func consentitoAutomaticamente(_ url: URL) -> Bool {
        !eDiRete(url) || includeVolumiDiRete
    }

    /// Arriva all'agente quando una preferenza cambia.
    static let notificaPreferenze = Notification.Name("com.giovariot.QuickLookManager.preferenzeCambiate")

    /// Nella home vera e non nel contenitore della sandbox: l'applicazione
    /// scrive, l'agente legge, e sono due sandbox diverse.
    private static func fileDellaPreferenza() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
            .appendingPathComponent("Library/Application Support/QLAppBundle/volumi-di-rete.txt")
    }

    static func contiene(volume: URL) -> Bool {
        let fm = FileManager.default
        guard let nomi = try? fm.contentsOfDirectory(atPath: volume.path) else { return false }

        if nomi.contains(where: databaseIcone.contains) { return true }

        for nome in nomi.prefix(quantiGuardare) {
            let file = volume.appendingPathComponent(nome)

            // Solo file veri. Una cartella può avere un FinderInfo con dentro
            // type e creator — un pacchetto `.app` ce l'ha — e contarla vorrebbe
            // dire scambiare per «disco Macintosh classico» ogni immagine disco
            // moderna che contiene un programma. Misurato su un `.dmg` scaricato
            // ieri: il solo `.app` dentro bastava a farlo passare per classico.
            var st = stat()
            guard lstat(file.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { continue }

            let type = ClassicIcon.fileType(of: file)
            if ClassicIcon.isApplication(type) { return true }
            if let type, !type.isEmpty,
               let creator = ClassicIcon.fileCreator(of: file), !creator.isEmpty {
                return true
            }
        }
        return false
    }
}
