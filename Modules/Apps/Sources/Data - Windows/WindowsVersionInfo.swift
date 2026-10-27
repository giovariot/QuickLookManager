import Foundation

/// Quel che un eseguibile Windows dichiara di sé.
///
/// Nella sezione risorse, accanto alle icone, sta `RT_VERSION` (tipo 16): una
/// struttura `VS_VERSIONINFO` che contiene i numeri di versione e una tabella
/// di stringhe — nome del prodotto, azienda, descrizione, copyright. È
/// l'equivalente Windows di quello che per un bundle `.app` sta nell'Info.plist,
/// ed è roba che il Finder di un Mac non mostra da nessuna parte.
///
/// Il formato è una sequenza di blocchi annidati, ciascuno con lunghezza
/// propria e allineato a quattro byte, con le chiavi in UTF-16. Il parser
/// scende fino alla tabella delle stringhe e ignora tutto il resto: la
/// struttura completa ha rami che a mostrare un'anteprima non servono.
enum WindowsVersionInfo {

    /// Le coppie chiave/valore dichiarate dall'eseguibile, nell'ordine in cui
    /// conviene mostrarle.
    static func read(from file: Data) -> [(chiave: String, valore: String)] {
        guard let raw = WindowsIcon.resource(in: file, type: 16) else { return [] }
        var trovate: [String: String] = [:]
        scan(raw, into: &trovate)

        // Un ordine che ha senso per chi legge, non quello in cui capitano.
        let ordine = [
            ("FileDescription", String(localized: "Descrizione", bundle: QLMBundle.framework)), ("ProductName", String(localized: "Prodotto", bundle: QLMBundle.framework)),
            ("CompanyName", String(localized: "Azienda", bundle: QLMBundle.framework)), ("FileVersion", String(localized: "Versione", bundle: QLMBundle.framework)),
            ("ProductVersion", String(localized: "Versione del prodotto", bundle: QLMBundle.framework)),
            ("LegalCopyright", "Copyright"), ("OriginalFilename", String(localized: "Nome originale", bundle: QLMBundle.framework)),
            ("InternalName", String(localized: "Nome interno", bundle: QLMBundle.framework)), ("Comments", String(localized: "Note", bundle: QLMBundle.framework)),
        ]
        var out: [(String, String)] = []
        for (chiave, etichetta) in ordine {
            if let v = trovate[chiave]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                out.append((etichetta, v))
            }
        }
        return out
    }

    /// Cammina i blocchi annidati raccogliendo le coppie della tabella stringhe.
    ///
    /// Ogni blocco è: lunghezza(2), lunghezza del valore(2), tipo(2), chiave in
    /// UTF-16 terminata da zero, riempimento fino a quattro byte, poi il valore
    /// e i figli. Le coppie che interessano sono quelle in cui il valore è
    /// testo, cioè tipo 1.
    private static func scan(_ d: Data, into out: inout [String: String], at start: Int = 0, depth: Int = 0) {
        guard depth < 6, start + 6 <= d.count else { return }

        var at = start
        while at + 6 <= d.count {
            let length = Int(le16(d, at))
            let valueLength = Int(le16(d, at + 2))
            let type = Int(le16(d, at + 4))
            guard length >= 6, at + length <= d.count else { return }

            var p = at + 6
            var key = ""
            while p + 1 < d.count {
                let u = le16(d, p)
                p += 2
                if u == 0 { break }
                key.append(Character(UnicodeScalar(u) ?? " "))
            }
            p = (p + 3) & ~3                       // allineamento a quattro byte

            if type == 1, valueLength > 0, p + valueLength * 2 <= d.count, !key.isEmpty {
                var value = ""
                for i in 0..<valueLength {
                    let u = le16(d, p + i * 2)
                    if u == 0 { break }
                    value.append(Character(UnicodeScalar(u) ?? " "))
                }
                if out[key] == nil { out[key] = value }
            }

            // I figli stanno dopo il valore, sempre allineati.
            let afterValue = (p + valueLength * (type == 1 ? 2 : 1) + 3) & ~3
            if afterValue < at + length {
                scan(d, into: &out, at: afterValue, depth: depth + 1)
            }

            at += (length + 3) & ~3
            if length == 0 { return }
        }
    }

    private static func le16(_ d: Data, _ o: Int) -> UInt16 {
        guard o >= 0, o + 1 < d.count else { return 0 }
        return UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8
    }
}
