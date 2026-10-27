import Foundation
import Security

/// Chi ha firmato un programma macOS, e cosa quella firma promette.
///
/// Sono le righe che in Apparency stanno in fondo — sandbox, hardening,
/// notarizzazione, Gatekeeper, chi ha firmato — e vengono tutte da una chiamata
/// sola, `SecCodeCopySigningInformation`, che è l'API pubblica per leggere una
/// firma senza lanciare `codesign`.
///
/// **Il verdetto di Gatekeeper è dedotto, non chiesto.** Chiederlo vorrebbe
/// dire `SecAssessment`, che nel SDK pubblico non c'è — l'unico modo sarebbe
/// un'API privata o un processo `spctl`, e nessuna delle due sta bene dentro
/// un'estensione QuickLook in sandbox. Quello che si può dire con certezza è
/// cosa contiene la firma, e da lì il verdetto si legge: un Developer ID con il
/// biglietto di notarizzazione incollato è quello che macOS chiama «Notarized
/// Developer ID». Dove il dubbio resta, il pannello lo dice invece di
/// inventarsi una spunta verde.
enum FirmaCodice {

    struct Info {
        let firmato: Bool
        let adHoc: Bool
        /// La catena, dal certificato del firmatario in su.
        let autorita: [String]
        /// Il firmatario come lo scrive Apple: «Randy Saldinger (936EB786NH)».
        let firmatario: String?
        let team: String?
        let identificatore: String?
        let sandbox: Bool
        let hardening: Bool
        /// La versione del runtime irrigidito, per esempio «26.2.0».
        let hardeningVersione: String?
        let notarizzato: Bool
        /// Cosa ne direbbe Gatekeeper, dedotto da quello che la firma contiene.
        let gatekeeper: String
        /// La firma regge? Controllato senza rifare il conto di ogni risorsa,
        /// che su un programma da un gigabyte vorrebbe dire far aspettare chi
        /// ha premuto la barra spaziatrice.
        let valida: Validita
    }

    /// I due bit di `kSecCodeInfoFlags` che interessano, da `<Security/CSCommon.h>`.
    ///
    /// Si riscrivono qui perché quelle costanti Swift non le importa: nell'header
    /// stanno in un enum anonimo, e dall'altra parte del ponte non arriva niente.
    private enum Bandiera {
        static let adHoc: UInt32 = 0x0002     // kSecCodeSignatureAdhoc
        static let runtime: UInt32 = 0x1_0000 // kSecCodeSignatureRuntime
    }

    // MARK: - Lettura

    static func leggi(_ url: URL) -> Info? {
        var codice: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &codice) == errSecSuccess,
              let codice
        else { return nil }

        var grezzo: CFDictionary?
        let flag = SecCSFlags(rawValue: kSecCSSigningInformation
                                      | kSecCSRequirementInformation
                                      | kSecCSContentInformation)
        guard SecCodeCopySigningInformation(codice, flag, &grezzo) == errSecSuccess,
              let info = grezzo as? [String: Any]
        else { return nil }

        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adHoc = flags & Bandiera.adHoc != 0
        let certificati = (info[kSecCodeInfoCertificates as String] as? [SecCertificate]) ?? []
        let nomi = certificati.compactMap { nomeComune($0) }

        // Il biglietto di notarizzazione incollato al pacchetto. È una chiave
        // pubblica dell'API (`kSecCodeInfoStapledNotarizationTicket`), quindi
        // non c'è bisogno di andare a cercare il file a mano.
        let biglietto = info[kSecCodeInfoStapledNotarizationTicket as String] as? Data

        let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let sandbox = entitlements?["com.apple.security.app-sandbox"] as? Bool ?? false

        let firmato = !certificati.isEmpty || adHoc
        let hardening = flags & Bandiera.runtime != 0

        return Info(
            firmato: firmato,
            adHoc: adHoc,
            autorita: nomi,
            firmatario: nomi.first,
            team: info[kSecCodeInfoTeamIdentifier as String] as? String,
            identificatore: info[kSecCodeInfoIdentifier as String] as? String,
            sandbox: sandbox,
            hardening: hardening,
            // Per esteso, come la scrive `codesign -dv`: «26.2.0», non «26.2».
            hardeningVersione: MachO.versione(info[kSecCodeInfoRuntimeVersion as String] as? UInt32 ?? 0,
                                              completa: true),
            notarizzato: biglietto != nil,
            gatekeeper: verdetto(autorita: nomi, notarizzato: biglietto != nil,
                                 adHoc: adHoc, firmato: firmato),
            valida: valida(codice, eseguibile: MachO.eseguibile(di: url)))
    }

    /// L'esito del controllo, con la differenza che conta.
    ///
    /// «Non si è potuto controllare» non è «non è valida», e confonderle qui
    /// sarebbe grave: l'estensione gira in sandbox, e una lettura negata
    /// tornerebbe come un errore qualunque. Dire «il file è stato modificato
    /// dopo la firma» per un permesso mancante vorrebbe dire accusare un
    /// programma sano. Solo gli errori che parlano davvero della firma
    /// diventano un «non torna».
    enum Validita {
        /// `tutte` dice se si sono guardate tutte le architetture o solo quella
        /// nativa: su un eseguibile enorme il conto si ferma prima, e chi legge
        /// deve sapere fin dove è arrivato il controllo.
        case buona(tutte: Bool)
        case rotta(String)
        case nonFirmato
        case nonSiSaDire(Int32)
    }

    /// La firma regge, senza rifare il conto di ogni file dentro il pacchetto.
    ///
    /// `kSecCSDoNotValidateResources` salta proprio quel conto: su Xcode.app
    /// sono centinaia di migliaia di file, e un'anteprima che ci mette mezzo
    /// minuto non è un'anteprima. Quello che resta controllato è l'eseguibile —
    /// cioè il codice — ed è quello che conta per dire se la firma è intatta.
    /// Il pannello scrive cosa è stato controllato, non «tutto a posto».
    /// Oltre questa misura si guarda la sola fetta nativa.
    ///
    /// Controllare tutte le architetture vuol dire rifare il conto di ogni byte
    /// di ogni fetta. Misurato: l'eseguibile di Photoshop è 343 MB in due
    /// architetture, e il controllo completo costa 1,45 secondi — su
    /// un'anteprima che dovrebbe comparire subito è un'eternità. Sotto la
    /// soglia si fa tutto (Apparency: 0,01 s; BBEdit da 21 MB: 0,07 s).
    private static let sogliaTutteLeArchitetture = 100 * 1024 * 1024

    private static func valida(_ codice: SecStaticCode, eseguibile: URL?) -> Validita {
        let peso = eseguibile.flatMap {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        } ?? 0
        let tutte = peso <= sogliaTutteLeArchitetture
        // `kSecCSCheckAllArchitectures`: senza, si controlla la sola fetta
        // nativa. Misurato — manomettendo un byte nella fetta Intel di un
        // programma universale, `codesign --verify` diceva «invalid signature»
        // e noi «valida», perché su Apple Silicon avevamo guardato solo l'altra
        // metà del file. Su un pannello che parla di firme è la differenza fra
        // informare e rassicurare a torto.
        var flag = kSecCSDoNotValidateResources
        if tutte { flag |= kSecCSCheckAllArchitectures }
        let esito = SecStaticCodeCheckValidity(codice, SecCSFlags(rawValue: flag), nil)
        switch esito {
        case errSecSuccess:
            return .buona(tutte: tutte)
        case Codice.nonFirmato:
            return .nonFirmato
        case Codice.firmaFallita, Codice.infoPlistFallito:
            return .rotta(String(localized: "il file è stato modificato dopo la firma", bundle: QLMBundle.framework))
        case Codice.firmaNonValida, Codice.firmaNonSupportata:
            return .rotta(String(localized: "la firma è in un formato che non si sa leggere", bundle: QLMBundle.framework))
        default:
            // Compreso `errSecCSSignatureNotVerifiable`, che vuol dire «non
            // riesco a leggere il file»: in sandbox è il caso normale, non un
            // difetto del programma che si sta guardando.
            return .nonSiSaDire(esito)
        }
    }

    /// I codici di `<Security/CSCommon.h>` che servono qui. Swift non li
    /// importa: stanno in un enum anonimo.
    private enum Codice {
        static let nonFirmato: OSStatus = -67062        // errSecCSUnsigned
        static let firmaFallita: OSStatus = -67061      // errSecCSSignatureFailed
        static let firmaNonValida: OSStatus = -67045    // errSecCSSignatureInvalid
        static let firmaNonSupportata: OSStatus = -67059 // errSecCSSignatureUnsupported
        static let infoPlistFallito: OSStatus = -67030  // errSecCSInfoPlistFailed
    }

    /// Il nome comune di un certificato: «Developer ID Application: Tizio (TEAM)».
    private static func nomeComune(_ cert: SecCertificate) -> String? {
        var nome: CFString?
        guard SecCertificateCopyCommonName(cert, &nome) == errSecSuccess else { return nil }
        return nome as String?
    }

    // MARK: - Il verdetto

    /// Cosa direbbe Gatekeeper, letto da quello che la firma contiene.
    ///
    /// Le regole sono quelle di macOS, e stanno tutte nel nome del certificato
    /// che ha firmato: solo una firma **Developer ID** vale per un programma
    /// scaricato, e dal 2020 vale solo se è anche notarizzata. Una firma di
    /// sviluppo («Apple Development») funziona sul Mac di chi l'ha fatta e da
    /// nessun'altra parte — ed è il caso di questa stessa applicazione.
    static func verdetto(autorita: [String], notarizzato: Bool,
                         adHoc: Bool, firmato: Bool) -> String {
        guard firmato else { return String(localized: "Non firmato", bundle: QLMBundle.framework) }
        if adHoc && autorita.isEmpty { return String(localized: "Firma ad hoc (vale solo su questo Mac)", bundle: QLMBundle.framework) }

        let catena = autorita.joined(separator: " ")
        if catena.contains("Apple Root CA") || catena.contains("Software Signing")
            || catena.contains("Apple Code Signing Certification Authority") {
            if autorita.first?.hasPrefix("Apple Development") == true
                || autorita.first?.hasPrefix("Mac Developer") == true {
                return String(localized: "Firma di sviluppo: vale sul Mac di chi l'ha firmata", bundle: QLMBundle.framework)
            }
            if autorita.first?.hasPrefix("Developer ID Application") == true {
                return notarizzato ? String(localized: "Developer ID notarizzato", bundle: QLMBundle.framework)
                                   : String(localized: "Developer ID, senza biglietto incollato", bundle: QLMBundle.framework)
            }
            if autorita.first?.hasPrefix("Apple Mac OS Application Signing") == true {
                return String(localized: "Distribuito dal Mac App Store", bundle: QLMBundle.framework)
            }
            return String(localized: "Firmato da Apple", bundle: QLMBundle.framework)
        }
        if autorita.first?.hasPrefix("Developer ID Application") == true {
            return notarizzato ? String(localized: "Developer ID notarizzato", bundle: QLMBundle.framework)
                               : String(localized: "Developer ID, senza biglietto incollato", bundle: QLMBundle.framework)
        }
        return String(localized: "Firmato, ma non da un'autorità di Apple", bundle: QLMBundle.framework)
    }
}
