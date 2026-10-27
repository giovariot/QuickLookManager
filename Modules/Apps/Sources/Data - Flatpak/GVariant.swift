import Foundation

/// Quel tanto di GVariant che serve a leggere un pacchetto Flatpak.
///
/// GVariant è il formato con cui GLib serializza dati strutturati, e un
/// `.flatpak` è esattamente questo: un valore GVariant, senza intestazioni
/// proprie, scritto su disco. Non c'è un numero magico da riconoscere né campi
/// a posizione fissa — dove sta ogni cosa lo dice la **forma** del valore.
///
/// Le regole che contano, dalla specifica del formato:
///
/// - i valori di lunghezza variabile dentro un contenitore non portano la loro
///   lunghezza: in coda al contenitore c'è una **tabella di scostamenti**, e da
///   lì si ricava dove finisce ciascuno;
/// - quanto è grande ogni voce della tabella lo decide la **misura del
///   contenitore**: un byte fino a 255, due fino a 65 535, quattro fino a
///   quattro gigabyte, otto oltre;
/// - in una **tupla** gli scostamenti stanno in ordine **inverso** (il primo
///   figlio ha l'ultima voce), e l'ultimo figlio non ce l'ha: finisce dove
///   finisce il contenitore;
/// - in un **array** stanno in ordine normale, e quanti sono lo si ricava
///   dall'ultimo: punta all'inizio della tabella stessa;
/// - un **variant** è i byte del valore, uno zero, e la stringa del tipo.
///
/// Qui non c'è un lettore generale: c'è il pezzo che serve, cioè arrivare al
/// primo figlio della tupla di testa e leggere un dizionario `a{sv}`. Un
/// lettore generale vorrebbe dire interpretare le firme dei tipi — un
/// linguaggio a sé — per una cosa che questo programma non fa.
enum GVariant {

    /// Un valore dentro un dizionario: la sua firma di tipo e i suoi byte.
    struct Valore {
        /// Per esempio `s`, `ay`, `t`.
        let tipo: String
        let byte: Data

        /// Il testo, se il valore è una stringa (`s`): NUL in fondo, tolto.
        var testo: String? {
            guard tipo == "s" else { return nil }
            var b = byte
            if b.last == 0 { b = b.dropLast() }
            return String(data: b, encoding: .utf8)
        }

        /// Il numero, se il valore è un intero a 64 bit (`t`).
        var intero: UInt64? {
            guard tipo == "t", byte.count == 8 else { return nil }
            return byte.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }.littleEndian
        }
    }

    /// Quanto è grande una voce della tabella degli scostamenti.
    static func misuraScostamento(_ dimensione: Int) -> Int {
        if dimensione <= 0xFF { return 1 }
        if dimensione <= 0xFFFF { return 2 }
        if dimensione <= 0xFFFF_FFFF { return 4 }
        return 8
    }

    private static func scostamento(_ d: Data, a: Int, misura: Int) -> Int? {
        guard a >= 0, a + misura <= d.count else { return nil }
        var v = 0
        for k in stride(from: misura - 1, through: 0, by: -1) {   // little-endian
            v = v << 8 | Int(d[d.startIndex + a + k])
        }
        return v
    }

    /// Dove finisce il primo figlio di una tupla, sapendo solo la misura del
    /// valore intero.
    ///
    /// Non serve conoscere il resto della firma: in una tupla il primo figlio
    /// comincia a zero, e il suo scostamento è **l'ultima** voce della tabella,
    /// cioè gli ultimi byte del valore. È quello che permette di leggere i
    /// metadati di un `.flatpak` da mezzo gigabyte leggendone due pezzi: la
    /// coda e la testa.
    static func fineDelPrimoFiglio(tuplaLunga dimensione: Int, coda: Data) -> Int? {
        let misura = misuraScostamento(dimensione)
        guard coda.count >= misura else { return nil }
        let fine = scostamento(coda, a: coda.count - misura, misura: misura)
        guard let fine, fine > 0, fine <= dimensione else { return nil }
        return fine
    }

    /// Un dizionario `a{sv}`: chiavi stringa, valori di tipo qualunque.
    ///
    /// L'array ha elementi di lunghezza variabile, quindi in coda ha la tabella
    /// dei loro scostamenti; ogni elemento è una coppia chiave/valore allineata
    /// a otto byte, con la chiave che finisce dove dice il suo scostamento e il
    /// valore che occupa tutto il resto.
    static func dizionario(_ d: Data) -> [String: Valore] {
        guard !d.isEmpty else { return [:] }
        let misura = misuraScostamento(d.count)

        // L'ultima voce della tabella punta all'inizio della tabella stessa:
        // da lì si sa quante voci ci sono, e quindi quanti elementi.
        guard let inizioTabella = scostamento(d, a: d.count - misura, misura: misura),
              inizioTabella <= d.count - misura,
              (d.count - inizioTabella) % misura == 0
        else { return [:] }

        let quanti = (d.count - inizioTabella) / misura
        var out: [String: Valore] = [:]
        var inizio = 0

        for k in 0..<quanti {
            guard let fine = scostamento(d, a: inizioTabella + k * misura, misura: misura),
                  fine <= inizioTabella, inizio <= fine
            else { break }
            // Gli elementi di un a{sv} sono allineati a otto byte.
            let da = (inizio + 7) & ~7
            if da < fine, let (chiave, valore) = coppia(d.slice(da, fine - da)) {
                out[chiave] = valore
            }
            inizio = fine
        }
        return out
    }

    /// Una coppia `{sv}`: la chiave è una stringa, il valore un variant.
    private static func coppia(_ d: Data) -> (String, Valore)? {
        guard !d.isEmpty else { return nil }
        let misura = misuraScostamento(d.count)
        // Una coppia è una tupla di due: solo la chiave ha uno scostamento,
        // perché il valore è l'ultimo e finisce dove finisce la coppia.
        guard let fineChiave = scostamento(d, a: d.count - misura, misura: misura),
              fineChiave > 0, fineChiave <= d.count - misura
        else { return nil }

        var byteChiave = d.slice(0, fineChiave)
        if byteChiave.last == 0 { byteChiave = byteChiave.dropLast() }
        guard let chiave = String(data: byteChiave, encoding: .utf8) else { return nil }

        let da = (fineChiave + 7) & ~7          // il variant è allineato a otto
        let a = d.count - misura
        guard da <= a else { return nil }
        guard let valore = variant(d.slice(da, a - da)) else { return nil }
        return (chiave, valore)
    }

    /// Un `v`: i byte del valore, uno zero, e la firma del tipo.
    static func variant(_ d: Data) -> Valore? {
        guard let zero = d.lastIndex(of: 0) else { return nil }
        let tipo = String(data: d.slice(zero - d.startIndex + 1, d.endIndex - zero - 1),
                          encoding: .utf8) ?? ""
        guard !tipo.isEmpty else { return nil }
        return Valore(tipo: tipo, byte: d.slice(0, zero - d.startIndex))
    }
}

private extension Data {
    func slice(_ o: Int, _ n: Int) -> Data {
        guard o >= 0, n >= 0, o + n <= count else { return Data() }
        return Data(self[(startIndex + o)..<(startIndex + o + n)])
    }
}
