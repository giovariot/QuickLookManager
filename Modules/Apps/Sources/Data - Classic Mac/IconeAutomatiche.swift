import Foundation
import os // OSLog

private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.giovariot.QuickLookManager",
                        category: "IconeAutomatiche")

/// Dare l'icona ai file classici di un volume intero.
///
/// È il lavoro che prima faceva l'estensione del Finder, una cartella alla
/// volta, e che adesso fanno due chiamanti: l'agente, quando un disco viene
/// montato, e l'applicazione, quando si sceglie un disco a mano. La logica sta
/// qui una volta sola perché è la stessa, e perché così si può provare senza
/// tirarsi dietro né il Finder né launchd.
enum IconeAutomatiche {

    /// Quanti file si guardano al massimo.
    ///
    /// I dischi per cui questo programma esiste sono piccoli — floppy, CD,
    /// immagini di dischi degli anni Novanta. Il tetto tiene fuori il caso del
    /// disco da due terabyte montato per sbaglio: meglio fermarsi e dirlo che
    /// tenerlo occupato per mezz'ora.
    static let tettoPredefinito = 50_000

    struct Esito {
        var guardati = 0
        var scritti = 0
        /// File per cui la scrittura è stata tentata ed è fallita (il fork
        /// ricostruito non tornava, il backup non si è riusciti a conservare…).
        /// Non sono «niente da fare»: l'utente deve poterlo sapere.
        var falliti = 0
        /// Il motivo del primo fallimento, per dirlo in chiaro.
        var primoErrore: String?
        /// Il tetto ha fermato la passeggiata prima della fine.
        var troncato = false
        /// Chi l'ha chiesta l'ha fermata prima della fine.
        var interrotto = false
    }

    /// Scrive l'icona di un file già riconosciuto come candidato, e conta
    /// com'è andata. Il database e l'icona arrivano da fuori: chi percorre li
    /// ha già calcolati, e rifarli per ogni file costerebbe — il database sono
    /// centinaia di kilobyte.
    private static func scrivi(_ file: URL, icona: Data, volume: URL,
                               scrivania: ClassicIcon.Fork?, esito: inout Esito) {
        let candidato = ClassicIconWriter.Candidate(url: file, iconBytes: icona.count, icon: icona)
        switch ClassicIconWriter.apply(to: volume, candidates: [candidato], desktop: scrivania) {
        case .written:
            esito.scritti += 1
        case .nothingToDo:
            break
        case .failed(let perche):
            esito.falliti += 1
            if esito.primoErrore == nil { esito.primoErrore = perche }
            os_log(.error, log: log, "icona non scritta: %{public}@", perche)
        }
    }

    /// Dà l'icona ai file **di una cartella sola**, senza scendere.
    ///
    /// È il gesto che serve davvero: quando una cartella viene aperta, si
    /// guarda quello che c'è dentro e basta. Scendere ricorsivamente vorrebbe
    /// dire, aprendo la radice di un disco, mettersi a leggerlo tutto — lavoro
    /// che nessuno ha chiesto e che si sente.
    ///
    /// La `scrivania` — il database delle icone del volume — si passa da fuori
    /// perché su un disco pieno sono centinaia di kilobyte di risorse: si legge
    /// una volta per volume, non una volta per cartella.
    @discardableResult
    static func cartella(_ url: URL, scrivania: ClassicIcon.Fork?, volume: URL) -> Esito {
        var esito = Esito()
        guard VolumeClassico.scrivibile(volume) else { return esito }

        let contenuto: [URL]
        do {
            contenuto = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        } catch {
            return esito
        }

        for file in contenuto {
            esito.guardati += 1
            // Il filtro è volutamente stretto: si guarda solo chi dichiara un
            // type classico e non ha già un'icona sua. Tutto il resto — e in
            // una cartella qualunque è il 99% — costa una lettura di xattr.
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  !ClassicIconWriter.giaFuoriFormato(file),
                  let icona = ClassicIconWriter.candidateIcon(at: file, desktop: scrivania)
            else { continue }

            scrivi(file, icona: icona, volume: volume, scrivania: scrivania, esito: &esito)
        }
        return esito
    }

    /// Scorre **tutto** il volume e dà l'icona a chi può averla e non ce l'ha.
    ///
    /// Questo lo fa solo chi l'ha chiesto: il comando «Dai le icone a un
    /// disco…» nell'applicazione. L'agente non percorre niente.
    ///
    /// `fermarsi` viene chiesto spesso: da un'interfaccia si deve poter
    /// interrompere, e da un agente si deve poter smettere quando il disco
    /// viene espulso.
    static func percorri(volume: URL,
                         tetto: Int = tettoPredefinito,
                         fermarsi: () -> Bool = { false },
                         avanzamento: ((Esito) -> Void)? = nil) -> Esito {
        var esito = Esito()
        guard VolumeClassico.scrivibile(volume) else { return esito }

        // Il database delle icone del disco, letto una volta sola: senza, i
        // documenti restano tutti fuori, ed è la maggioranza dei file.
        let scrivania = ClassicIcon.desktopDatabase(ofVolume: volume)
        guard let passeggiata = FileManager.default.enumerator(
            at: volume, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        else { return esito }

        var ultimoAvviso = Date.distantPast
        for caso in passeggiata {
            if fermarsi() { esito.interrotto = true; break }
            guard let file = caso as? URL else { continue }

            esito.guardati += 1
            if esito.guardati > tetto {
                esito.troncato = true
                break
            }
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  !ClassicIconWriter.giaFuoriFormato(file),
                  let icona = ClassicIconWriter.candidateIcon(at: file, desktop: scrivania)
            else { continue }

            scrivi(file, icona: icona, volume: volume, scrivania: scrivania, esito: &esito)
            if Date().timeIntervalSince(ultimoAvviso) > 0.2 {
                ultimoAvviso = Date()
                avanzamento?(esito)
            }
        }
        avanzamento?(esito)
        return esito
    }
}
