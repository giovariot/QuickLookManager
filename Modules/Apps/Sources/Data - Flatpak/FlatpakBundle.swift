import Foundation

/// Un pacchetto Flatpak: `.flatpak`, il formato con cui un'applicazione Linux
/// viaggia in un file solo.
///
/// **Com'è fatto.** Non è un archivio: è un *static delta* di OSTree — la
/// differenza fra «niente» e la revisione che contiene l'applicazione — con in
/// testa dei metadati aggiunti da Flatpak. Tutto il file è un unico valore
/// GVariant di tipo `(a{sv}tayay(a{sv}aya(say)sstayay)aya(uayttay)a(yaytt))`,
/// e il primo figlio di quella tupla è il dizionario dei metadati. È così che
/// lo legge Flatpak stesso (`flatpak_bundle_load`), e qui si fa lo stesso.
///
/// Dentro quel dizionario, fra le altre cose, ci sono **due PNG**: `icon-64` e
/// `icon-128`, messi lì da `flatpak build-bundle` perché i negozi di
/// applicazioni possano mostrare l'icona senza scompattare niente. È l'unica
/// ragione per cui macOS può disegnare l'icona di un pacchetto pensato per
/// Linux.
///
/// **Quanto si legge.** Due pezzi e basta: gli ultimi byte, che dicono dove
/// finiscono i metadati, e i metadati stessi, che stanno in testa. Un pacchetto
/// da mezzo gigabyte non viene toccato per il resto — che è quello che serve a
/// una miniatura, che deve comparire subito.
enum FlatpakBundle {

    struct Info {
        /// `app/org.gnome.Dictionary/x86_64/stable`.
        let ref: String?
        /// Da quale deposito viene.
        let origine: String?
        let runtimeRepo: String?
        /// Il file `metadata` dell'applicazione, che è un INI.
        let metadata: String?
        /// Quanto occuperà una volta installata.
        let pesoInstallato: UInt64?
        /// Il PNG più grande fra quelli che si porta dietro.
        let icona: Data?
    }

    /// Oltre questo, i metadati non si leggono: un `.flatpak` ne ha per
    /// qualche decina di kilobyte, e un numero più grande vorrebbe dire un
    /// file che non è quello che dice di essere.
    private static let metadatiMax = 8 * 1024 * 1024

    static func leggi(_ url: URL) -> Info? {
        guard let dizionario = metadati(url) else { return nil }

        func testo(_ chiave: String) -> String? { dizionario[chiave]?.testo }

        return Info(
            ref: testo("ref"),
            origine: testo("origin"),
            runtimeRepo: testo("runtime-repo"),
            metadata: testo("metadata"),
            pesoInstallato: dizionario["installed-size"]?.intero,
            icona: dizionario["icon-128"]?.byte ?? dizionario["icon-64"]?.byte)
    }

    /// Solo l'icona, per chi deve disegnare una miniatura e basta.
    static func icona(_ url: URL) -> Data? {
        guard let dizionario = metadati(url) else { return nil }
        return dizionario["icon-128"]?.byte ?? dizionario["icon-64"]?.byte
    }

    /// Il dizionario dei metadati, letto senza toccare il resto del file.
    private static func metadati(_ url: URL) -> [String: GVariant.Valore]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let dimensione = Int((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard dimensione > 16 else { return nil }

        handle.seek(toFileOffset: UInt64(dimensione - 8))
        let coda = handle.readData(ofLength: 8)
        guard let fine = GVariant.fineDelPrimoFiglio(tuplaLunga: dimensione, coda: coda),
              fine <= metadatiMax
        else { return nil }

        handle.seek(toFileOffset: 0)
        let testa = handle.readData(ofLength: fine)
        guard testa.count == fine else { return nil }

        let dizionario = GVariant.dizionario(testa)
        // Un dizionario vuoto vuol dire che non è un pacchetto Flatpak: il
        // formato non lo garantisce nessun numero magico, e l'unica prova che
        // si può portare è che i metadati si leggano e dicano qualcosa.
        return dizionario.isEmpty ? nil : dizionario
    }

    // MARK: - Il file `metadata`, che è un INI

    /// Una chiave del file `metadata`, per esempio `name` o `runtime` nella
    /// sezione `[Application]`.
    static func campo(_ nome: String, in metadata: String?) -> String? {
        guard let metadata else { return nil }
        for riga in metadata.components(separatedBy: .newlines) {
            let r = riga.trimmingCharacters(in: .whitespaces)
            guard let uguale = r.firstIndex(of: "="), r.hasPrefix(nome) else { continue }
            let chiave = r[r.startIndex..<uguale].trimmingCharacters(in: .whitespaces)
            guard chiave == nome else { continue }
            return String(r[r.index(after: uguale)...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Le righe da mostrare nel pannello.
    static func righe(_ info: Info) -> [Riga] {
        var out: [Riga] = []

        // Il `ref` dice tutto in una riga sola: tipo, identificativo,
        // architettura e ramo, separati da barre.
        if let ref = info.ref {
            let pezzi = ref.components(separatedBy: "/")
            if pezzi.count == 4 {
                out.append(Riga(String(localized: "Identificatore", bundle: QLMBundle.framework), pezzi[1]))
                out.append(Riga(String(localized: "Architettura", bundle: QLMBundle.framework), pezzi[2]))
                out.append(Riga(String(localized: "Ramo", bundle: QLMBundle.framework), pezzi[3]))
            } else {
                out.append(Riga(String(localized: "Riferimento", bundle: QLMBundle.framework), ref))
            }
        }
        if let runtime = campo("runtime", in: info.metadata) {
            out.append(Riga("Runtime", runtime))
        }
        if let sdk = campo("sdk", in: info.metadata) {
            out.append(Riga("SDK", sdk))
        }
        if let comando = campo("command", in: info.metadata) {
            out.append(Riga(String(localized: "Comando", bundle: QLMBundle.framework), comando))
        }
        if let peso = info.pesoInstallato, peso > 0 {
            let f = ByteCountFormatter()
            f.countStyle = .file
            out.append(Riga(String(localized: "Una volta installato", bundle: QLMBundle.framework), f.string(fromByteCount: Int64(peso))))
        }
        if let origine = info.origine {
            out.append(Riga(String(localized: "Deposito d'origine", bundle: QLMBundle.framework), origine))
        }
        return out
    }
}
