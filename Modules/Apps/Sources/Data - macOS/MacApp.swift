import Foundation

/// Un programma macOS: cos'è, per quali processori, e cosa dice la sua firma.
///
/// Il resto del pannello queste cose le ha già per gli `.ipa` — nome, versione,
/// bundle id vengono tutti dall'`Info.plist` e li legge `Plist_Info`. Qui c'è
/// solo quello che di un programma macOS si può dire **in più**, e che viene da
/// due posti dove l'`Info.plist` non arriva: il binario (architetture, sistema
/// minimo) e la firma (sandbox, hardening, notarizzazione).
enum MacApp {

    /// Che cosa è questo file, in una parola.
    ///
    /// Si guarda il tipo dichiarato e non l'estensione del nome, perché è la
    /// stessa cosa che guarda il Finder quando decide a chi chiedere
    /// l'anteprima: se lui ci ha mandato qui un `.prefPane`, il pannello deve
    /// dire «pannello di preferenze» e non «applicazione».
    static func genere(uti: String, plist: PlistDict?) -> String {
        // Un'estensione dichiara a cosa si attacca, ed è più preciso del tipo:
        // «estensione QuickLook» dice molto più di «bundle».
        if let punto = (plist?["NSExtension"] as? PlistDict)?["NSExtensionPointIdentifier"] as? String {
            return String(localized: "Estensione \(nomePunto(punto))", bundle: QLMBundle.framework)
        }
        switch uti {
        case "com.apple.application-bundle":        return String(localized: "Applicazione", bundle: QLMBundle.framework)
        case "com.apple.framework":                 return "Framework"
        case "com.apple.xpc-service":               return String(localized: "Servizio XPC", bundle: QLMBundle.framework)
        case "com.apple.systempreference.prefpane": return String(localized: "Pannello di preferenze", bundle: QLMBundle.framework)
        case "com.apple.system-extension":          return String(localized: "Estensione di sistema", bundle: QLMBundle.framework)
        case "com.apple.driver-extension":          return String(localized: "Estensione driver", bundle: QLMBundle.framework)
        case "com.apple.kernel-extension":          return String(localized: "Estensione del kernel", bundle: QLMBundle.framework)
        case "com.apple.plugin":                    return "Plug-in"
        case "com.apple.mach-o-dylib":              return String(localized: "Libreria dinamica", bundle: QLMBundle.framework)
        case "public.unix-executable":              return String(localized: "Eseguibile Unix", bundle: QLMBundle.framework)
        default:                                    return String(localized: "Bundle macOS", bundle: QLMBundle.framework)
        }
    }

    private static func nomePunto(_ id: String) -> String {
        switch id {
        case "com.apple.quicklook.preview":     return "QuickLook (anteprima)"
        case "com.apple.quicklook.thumbnail":   return "QuickLook (miniature)"
        case "com.apple.fileprovider-nonui":    return "File Provider"
        case "com.apple.FinderSync":            return "Finder Sync"
        case "com.apple.share-services":        return "di condivisione"
        case "com.apple.widgetkit-extension":   return "widget"
        case "com.apple.networkextension.packet-tunnel": return "di rete"
        default:
            // Meglio l'identificatore vero che una parola inventata: chi legge
            // il pannello di un'estensione sa cosa farsene.
            return "(\(id))"
        }
    }

    /// Le righe che stanno sotto il nome, in aggiunta a quelle che l'`Info.plist`
    /// dà già a tutti.
    static func righe(url: URL, uti: String, plist: PlistDict?) -> [Riga] {
        var out: [Riga] = []

        if let m = MachO.info(perBundleOFile: url) {
            // Senza etichetta una riga per architettura, come le scrive
            // Apparency: chi legge vuole sapere se gira nativo, e in mezzo a
            // una virgola si perde. Con l'etichetta stanno su una riga sola,
            // che in tabella è quello che ci si aspetta.
            out.append(Riga(String(localized: "Architetture", bundle: QLMBundle.framework), m.architetture.joined(separator: ", "),
                            disteso: m.architetture.joined(separator: "\n")))
            if let min = m.minOS {
                let dove = m.piattaforma ?? "macOS"
                out.append(Riga(String(localized: "Richiede", bundle: QLMBundle.framework), String(localized: "\(dove) \(min) o successivo", bundle: QLMBundle.framework)))
            }
        } else if let min = plist?["LSMinimumSystemVersion"] as? String {
            // Nessun binario leggibile (un bundle senza eseguibile, per dire):
            // resta quello che l'Info.plist dichiara.
            out.append(Riga(String(localized: "Richiede", bundle: QLMBundle.framework), String(localized: "macOS \(min) o successivo", bundle: QLMBundle.framework)))
        }

        if let c = plist?["NSHumanReadableCopyright"] as? String, !c.isEmpty {
            out.append(Riga("Copyright", c, disteso: c))
        }
        return out
    }

    /// Come sta messa una riga della firma.
    ///
    /// Le tre facce di Apparency, con le stesse regole: **verde** quando la
    /// cosa c'è ed è quella giusta, **grigio** quando in questo caso non è
    /// richiesta, **rosso** quando manca e dovrebbe esserci. Il grigio non è un
    /// mezzo rosso: la sandbox su un programma fuori dal Mac App Store non è un
    /// difetto, e dipingerla di rosso vorrebbe dire allarmare per niente.
    enum Segno: String {
        case buono, neutro, grave, nessuno
    }

    struct RigaFirma {
        let etichetta: String
        let valore: String
        let segno: Segno
    }

    /// Le righe della firma, etichetta per etichetta.
    ///
    /// Il testo dice sempre **cosa è stato guardato**. «Firma valida» senza
    /// dire cosa si è verificato è la mezza verità che fa credere a chi legge
    /// di aver ricevuto una garanzia: qui la validità è quella dell'eseguibile,
    /// perché rifare il conto di ogni risorsa di un programma da un gigabyte
    /// vorrebbe dire un'anteprima che arriva dopo mezzo minuto.
    static func righeFirma(_ f: FirmaCodice.Info, annidato: Bool = false) -> [RigaFirma] {
        var out: [RigaFirma] = []
        let developerID = f.autorita.first?.hasPrefix("Developer ID Application") == true

        // Fuori dal Mac App Store la sandbox non è richiesta: la sua assenza è
        // una scelta, non un difetto.
        out.append(RigaFirma(etichetta: "Sandbox", valore: f.sandbox ? String(localized: "sì", bundle: QLMBundle.framework) : "no",
                             segno: f.sandbox ? .buono : .neutro))

        // Senza runtime irrigidito un Developer ID non si può nemmeno
        // notarizzare: lì l'assenza è un guaio vero.
        out.append(RigaFirma(
            etichetta: "Hardened runtime",
            valore: f.hardening ? (f.hardeningVersione.map { String(localized: "sì, versione \($0)", bundle: QLMBundle.framework) } ?? String(localized: "sì", bundle: QLMBundle.framework)) : "no",
            segno: f.hardening ? .buono : (developerID ? .grave : .neutro)))

        out.append(RigaFirma(
            etichetta: String(localized: "Notarizzazione", bundle: QLMBundle.framework),
            valore: f.notarizzato
                ? String(localized: "biglietto incollato al pacchetto", bundle: QLMBundle.framework)
                : (annidato ? String(localized: "nessun biglietto qui: per i componenti lo porta il pacchetto che li contiene", bundle: QLMBundle.framework)
                            : String(localized: "nessun biglietto incollato", bundle: QLMBundle.framework)),
            segno: f.notarizzato ? .buono : ((developerID && !annidato) ? .grave : .neutro)))

        out.append(RigaFirma(etichetta: "Gatekeeper", valore: f.gatekeeper,
                             segno: segnoGatekeeper(f, developerID: developerID, annidato: annidato)))

        if let chi = f.firmatario {
            // Il nome del certificato quasi sempre finisce con «(TEAM)»: in
            // quel caso aggiungere «— team TEAM» scrive due volte la stessa
            // cosa sulla stessa riga.
            let nome = ripulisci(chi)
            let team = f.team.flatMap { nome.contains($0) ? nil : " — team \($0)" } ?? ""
            out.append(RigaFirma(etichetta: String(localized: "Firmato da", bundle: QLMBundle.framework), valore: nome + team, segno: .nessuno))
        }
        if f.autorita.count > 1 {
            out.append(RigaFirma(etichetta: String(localized: "Catena", bundle: QLMBundle.framework),
                                 valore: f.autorita.dropFirst().joined(separator: " › "),
                                 segno: .nessuno))
        }
        if let id = f.identificatore {
            out.append(RigaFirma(etichetta: String(localized: "Identificatore", bundle: QLMBundle.framework), valore: id, segno: .nessuno))
        }
        switch f.valida {
        case .buona(let tutte):
            out.append(RigaFirma(etichetta: String(localized: "Firma", bundle: QLMBundle.framework), valore: tutte
                ? String(localized: "valida (controllato l'eseguibile in tutte le architetture, non ogni risorsa)", bundle: QLMBundle.framework)
                : String(localized: "valida (controllata la sola architettura nativa: l'eseguibile è troppo grande per guardarle tutte senza far aspettare)", bundle: QLMBundle.framework), segno: .buono))
        case .rotta(let perche):
            out.append(RigaFirma(etichetta: String(localized: "Firma", bundle: QLMBundle.framework), valore: String(localized: "non torna: \(perche)", bundle: QLMBundle.framework), segno: .grave))
        case .nonSiSaDire(let codice):
            // Non è un'accusa: è un controllo che non si è potuto fare.
            out.append(RigaFirma(etichetta: String(localized: "Firma", bundle: QLMBundle.framework),
                                 valore: String(localized: "non si è potuta controllare (errore \(codice))", bundle: QLMBundle.framework),
                                 segno: .neutro))
        case .nonFirmato:
            break   // l'ha già detto la riga di Gatekeeper
        }
        return out
    }

    /// Il verdetto vale verde solo se quel programma, così com'è, si apre su un
    /// altro Mac senza che Gatekeeper lo fermi.
    private static func segnoGatekeeper(_ f: FirmaCodice.Info,
                                        developerID: Bool, annidato: Bool) -> Segno {
        if !f.firmato { return .grave }
        if f.adHoc && f.autorita.isEmpty { return .grave }
        if developerID { return (f.notarizzato || annidato) ? .buono : .grave }
        if f.autorita.first?.hasPrefix("Apple Development") == true
            || f.autorita.first?.hasPrefix("Mac Developer") == true {
            // Vale sul Mac di chi l'ha firmata: non è un difetto del programma,
            // è quello che quella firma promette.
            return .neutro
        }
        return .buono
    }


    /// «Developer ID Application: Tizio (TEAM)» → «Tizio (TEAM)».
    ///
    /// Il prefisso dice che tipo di certificato è, e quello sta già nella riga
    /// di Gatekeeper: ripeterlo qui ruba spazio al nome, che è la cosa che si
    /// cerca.
    private static func ripulisci(_ nome: String) -> String {
        for prefisso in ["Developer ID Application: ", "Apple Development: ",
                         "Mac Developer: ", "3rd Party Mac Developer Application: ",
                         "Apple Distribution: "] {
            if nome.hasPrefix(prefisso) { return String(nome.dropFirst(prefisso.count)) }
        }
        return nome
    }
}


extension MetaInfo {
    /// L'`Info.plist` così com'è, senza passare da `Plist_Info`.
    ///
    /// `Plist_Info` tiene le chiavi che servono a un `.ipa`, e di un programma
    /// macOS ne servono altre — il copyright, il punto di estensione. Invece di
    /// allargare quella struttura con campi che a un `.ipa` non dicono niente,
    /// qui si legge il dizionario e basta.
    func plistGrezzo() -> PlistDict? {
        readPayloadFile("Info.plist", osxSubdir: nil)?.asPlistOrNil()
    }
}
