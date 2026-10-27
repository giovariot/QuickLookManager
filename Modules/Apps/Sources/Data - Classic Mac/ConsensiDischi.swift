import Foundation

/// Su quali dischi l'agente può scrivere le icone: il permesso, disco per disco.
///
/// Un disco con programmi dei vecchi Mac sopra è un disco di qualcuno, e
/// scriverci degli attributi senza che nessuno l'abbia chiesto non è una cosa
/// che un programma in background deve fare da sé. Quindi la prima volta che
/// l'agente ne incontra uno **chiede**: «dare le icone ai file di questo
/// disco?». La risposta — sì, o mai — si ricorda, ed è legata al disco e non al
/// momento: riattaccando lo stesso disco, anche mesi dopo, non si richiede.
///
/// **Come si riconosce «lo stesso disco».** Dall'UUID del volume, che sta nel
/// volume e viaggia con lui: un disco spostato in un'altra porta, o montato con
/// un altro nome, è sempre lo stesso. Dove l'UUID non c'è (alcuni volumi di rete,
/// certi dischi molto vecchi) si ripiega sul nome, che è meno solido ma è
/// quello che c'è.
///
/// **Dove sta scritto.** Nella cartella di supporto di QLAppBundle, nella home
/// vera, in un file solo (`dischi.json`) che leggono e scrivono l'applicazione
/// (che chiede e mostra l'elenco) e l'agente (che consulta). Sono due
/// processi, quindi il file si riscrive intero a ogni modifica e di rado.
enum ConsensiDischi {

    enum Stato: String, Codable {
        case consentito
        case rifiutato
    }

    struct Voce: Codable {
        var nome: String
        var stato: Stato
        var data: Date
    }

    /// L'identificativo dell'applicazione, per ritrovarla se l'agente deve aprirla.
    static let identificativoApp = "com.giovariot.QuickLookManager"

    /// L'agente chiede all'applicazione di domandare il permesso per un disco.
    static let notificaRichiesta = Notification.Name("com.giovariot.QuickLookManager.consensoRichiesto")
    /// L'elenco dei permessi è cambiato: l'agente riguarda i dischi montati.
    static let notifica = Notification.Name("com.giovariot.QuickLookManager.consensiCambiati")

    /// Solo per i test: una cartella al posto di quella dell'utente.
    static var cartellaDiProva: URL?

    // MARK: - Chi è un disco

    static func identificativo(_ volume: URL) -> String {
        let valori = try? volume.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey])
        if let uuid = valori?.volumeUUIDString, !uuid.isEmpty { return uuid }
        return "nome:" + (valori?.volumeName ?? volume.lastPathComponent)
    }

    static func nome(_ volume: URL) -> String {
        (try? volume.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? volume.lastPathComponent
    }

    // MARK: - Leggere

    /// Il permesso dato per questo disco, o `nil` se non è mai stato chiesto.
    static func stato(_ volume: URL) -> Stato? {
        carica()[identificativo(volume)]?.stato
    }

    /// Tutti i dischi ricordati, in ordine di nome.
    static func tutti() -> [(id: String, voce: Voce)] {
        carica().map { (id: $0.key, voce: $0.value) }
            .sorted { $0.voce.nome.localizedCaseInsensitiveCompare($1.voce.nome) == .orderedAscending }
    }

    // MARK: - Scrivere

    /// Dà o toglie il permesso. `nil` dimentica il disco: alla prossima volta si richiede.
    @discardableResult
    static func imposta(_ stato: Stato?, id: String, nome: String) -> Bool {
        var tutte = carica()
        if let stato {
            tutte[id] = Voce(nome: nome, stato: stato, data: Date())
        } else {
            tutte.removeValue(forKey: id)
        }
        guard salva(tutte) else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            notifica, object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    @discardableResult
    static func imposta(_ stato: Stato?, per volume: URL) -> Bool {
        imposta(stato, id: identificativo(volume), nome: nome(volume))
    }

    // MARK: - Il file

    private static func fileDeiConsensi() -> URL? {
        let base: URL
        // `QLAPPBUNDLE_CONSENSI_PROVA` fa lo stesso per i test che lanciano
        // l'agente come programma a parte.
        if let prova = cartellaDiProva
            ?? ProcessInfo.processInfo.environment["QLAPPBUNDLE_CONSENSI_PROVA"]
                .map({ URL(fileURLWithPath: $0, isDirectory: true) }) {
            base = prova
        } else {
            guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
            base = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
                .appendingPathComponent("Library/Application Support/QLAppBundle", isDirectory: true)
        }
        return base.appendingPathComponent("dischi.json")
    }

    private static func carica() -> [String: Voce] {
        guard let url = fileDeiConsensi(), let dati = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        // Un file illeggibile vale come vuoto: meglio richiedere i permessi che
        // tenerli in uno stato che nessuno sa leggere.
        return (try? decoder.decode([String: Voce].self, from: dati)) ?? [:]
    }

    private static func salva(_ tutte: [String: Voce]) -> Bool {
        guard let url = fileDeiConsensi() else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let dati = try? encoder.encode(tutte) else { return false }
        return (try? dati.write(to: url, options: .atomic)) != nil
    }
}
