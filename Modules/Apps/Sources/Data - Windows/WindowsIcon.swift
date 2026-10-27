import Foundation

/// L'icona che un eseguibile Windows si porta dentro.
///
/// Un `.exe` o una `.dll` sono file PE, e le loro icone stanno nella sezione
/// risorse, in due tipi che vanno letti insieme:
///
///     RT_GROUP_ICON (14) ──▶ l'indice: per ogni misura disponibile, quanto è
///       │                    grande e con che id sta altrove
///       └─ RT_ICON (3) ────▶ i bitmap veri, uno per id
///
/// È la stessa separazione fra indice e dati del `BNDL` classico, e per la
/// stessa ragione: così più eseguibili possono condividere le stesse immagini
/// senza duplicarle.
///
/// **Il risultato è un `.ico`, non un `.icns`.** Sembra una scorciatoia e non
/// lo è: rimettere insieme indice e bitmap nel formato ICO è esattamente
/// l'operazione inversa di come li ha divisi il compilatore di risorse, mentre
/// convertire i pixel in un `icns` vorrebbe dire reimplementare la decodifica
/// dei DIB a 1, 4, 8, 24 e 32 bit, delle maschere, e del PNG che gli eseguibili
/// moderni ci mettono dentro per le icone grandi. macOS l'ICO lo legge già da
/// sé — è `com.microsoft.ico`, un tipo dichiarato — quindi quel lavoro è già
/// fatto e fatto meglio.
///
/// Il parser tratta ogni offset come ostile: questi file arrivano da dischi
/// vecchi e da rete, e un valore sballato non deve fare altro che restituire
/// `nil`.
enum WindowsIcon {

    /// L'icona principale di un eseguibile, come file `.ico`.
    ///
    /// «Principale» è il gruppo con l'id più basso, che è la convenzione con
    /// cui Windows sceglie l'icona da mostrare per il programma.
    static func ico(at url: URL, limit: Int = 64 * 1024 * 1024) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // `readData(ofLength:)` e non `read(upToCount:)`: il secondo esiste
        // solo da macOS 10.15.4, e questo progetto arriva fino a 10.15.
        let file = handle.readData(ofLength: limit)
        guard file.count > 0x40 else { return nil }
        return ico(from: file)
    }

    static func ico(from file: Data) -> Data? {
        guard let pe = PE(file) else { return nil }
        guard let groupID = pe.resourceIDs(type: 14).min(),
              let group = pe.resource(type: 14, id: groupID),
              group.count >= 6
        else { return nil }

        // GRPICONDIR: riservato(2), tipo(2), quante(2)
        let count = Int(le16(group, 4))
        guard count > 0, group.count >= 6 + count * 14 else { return nil }

        // Le due strutture differiscono solo in coda. Gli otto byte iniziali —
        // larghezza, altezza, numero di colori, riservato, piani e bit per
        // pixel — sono identici; poi il gruppo dice la dimensione e **l'id**
        // della risorsa (14 byte in tutto), mentre il file ICO dice la
        // dimensione e **l'offset** del bitmap (16 byte). Rimetterli insieme è
        // l'operazione inversa di come li ha divisi il compilatore di risorse.
        var images: [(head: Data, data: Data)] = []
        for i in 0..<count {
            let at = 6 + i * 14
            let id = Int(le16(group, at + 12))
            guard let image = pe.resource(type: 3, id: id), !image.isEmpty else { continue }
            let head = Data(group[(group.startIndex + at)..<(group.startIndex + at + 8)])
            images.append((head, image))
        }
        guard !images.isEmpty else { return nil }

        var ico = Data()
        ico.appendLE16(0)                    // riservato
        ico.appendLE16(1)                    // tipo: icona
        ico.appendLE16(UInt16(images.count))

        // Gli offset si calcolano sul numero di icone effettivamente trovate,
        // che può essere minore di quello dichiarato se un bitmap mancava.
        var at = 6 + images.count * 16
        for entry in images {
            ico.append(entry.head)
            ico.appendLE32(UInt32(entry.data.count))
            ico.appendLE32(UInt32(at))
            at += entry.data.count
        }
        for entry in images { ico.append(entry.data) }
        return ico
    }

    /// Una risorsa qualunque di un file PE, presa con l'id più basso.
    ///
    /// Serve a chi guarda dentro l'eseguibile per altri motivi — le
    /// informazioni di versione, per esempio — senza rifare il lettore.
    static func resource(in file: Data, type: Int) -> Data? {
        guard let pe = PE(file), let id = pe.resourceIDs(type: type).min() else { return nil }
        return pe.resource(type: type, id: id)
    }

    // MARK: - Il file PE, quel tanto che basta

    /// Solo la parte che serve a raggiungere le risorse: intestazioni, tabella
    /// delle sezioni e l'albero delle risorse. Nient'altro del formato PE viene
    /// interpretato.
    private struct PE {
        let file: Data
        let resourceBase: Int        // offset nel file della sezione risorse
        let resourceRVA: Int         // indirizzo virtuale della stessa
        let sections: [(rva: Int, size: Int, raw: Int)]

        init?(_ file: Data) {
            guard file.count > 0x40,
                  file[file.startIndex] == 0x4D, file[file.startIndex + 1] == 0x5A  // "MZ"
            else { return nil }

            let peAt = Int(le32(file, 0x3C))
            guard peAt > 0, peAt + 24 <= file.count,
                  le32(file, peAt) == 0x0000_4550                                   // "PE\0\0"
            else { return nil }

            let sectionCount = Int(le16(file, peAt + 6))
            let optionalSize = Int(le16(file, peAt + 20))
            let sectionTable = peAt + 24 + optionalSize
            guard sectionCount > 0, sectionCount < 96,
                  sectionTable + sectionCount * 40 <= file.count
            else { return nil }

            var found: [(rva: Int, size: Int, raw: Int)] = []
            var base = -1, rva = -1
            for s in 0..<sectionCount {
                let e = sectionTable + s * 40
                let name = file[(file.startIndex + e)..<(file.startIndex + e + 8)]
                let sRVA = Int(le32(file, e + 12))
                let sSize = Int(le32(file, e + 16))
                let sRaw = Int(le32(file, e + 20))
                guard sRaw >= 0, sRaw <= file.count else { continue }
                found.append((sRVA, sSize, sRaw))
                if Array(name.prefix(5)) == Array(".rsrc".utf8) {
                    base = sRaw
                    rva = sRVA
                }
            }
            guard base >= 0 else { return nil }

            self.file = file
            self.resourceBase = base
            self.resourceRVA = rva
            self.sections = found
        }

        /// Da indirizzo virtuale a posizione nel file, passando per la sezione
        /// che lo contiene.
        func fileOffset(rva: Int) -> Int? {
            for s in sections where rva >= s.rva && rva < s.rva + max(s.size, 1) {
                let at = s.raw + (rva - s.rva)
                return at < file.count ? at : nil
            }
            return nil
        }

        /// Gli id presenti sotto un tipo di risorsa.
        func resourceIDs(type: Int) -> [Int] {
            guard let dir = subdirectory(of: resourceBase, id: type) else { return [] }
            // Gli id negativi sono le risorse nominate con una stringa: le icone
            // per numero si trovano sempre, quindi si scartano.
            return entries(at: dir).map(\.id).filter { $0 >= 0 }
        }

        /// I byte di una risorsa, scendendo tipo → id → lingua.
        func resource(type: Int, id: Int) -> Data? {
            guard let byType = subdirectory(of: resourceBase, id: type),
                  let byID = subdirectory(of: byType, id: id)
            else { return nil }

            // Il terzo livello è la lingua: si prende la prima, perché un'icona
            // non è tradotta e averne più di una è un caso di scuola.
            guard let first = entries(at: byID).first, !first.isDirectory,
                  let dataEntry = absolute(first.offset)
            else { return nil }

            guard dataEntry + 16 <= file.count else { return nil }
            let rva = Int(le32(file, dataEntry))
            let size = Int(le32(file, dataEntry + 4))
            guard size > 0, size < 16 * 1024 * 1024,
                  let at = fileOffset(rva: rva), at + size <= file.count
            else { return nil }

            return Data(file[(file.startIndex + at)..<(file.startIndex + at + size)])
        }

        private struct Entry {
            let id: Int
            let offset: Int          // relativo alla base delle risorse
            let isDirectory: Bool
        }

        private func absolute(_ relative: Int) -> Int? {
            let at = resourceBase + relative
            return at < file.count ? at : nil
        }

        private func entries(at directory: Int) -> [Entry] {
            guard directory + 16 <= file.count else { return [] }
            let named = Int(le16(file, directory + 12))
            let ids = Int(le16(file, directory + 14))
            let total = named + ids
            guard total > 0, total < 4096,
                  directory + 16 + total * 8 <= file.count else { return [] }

            var out: [Entry] = []
            for i in 0..<total {
                let e = directory + 16 + i * 8
                let name = le32(file, e)
                let value = le32(file, e + 4)
                // Bit alto nel nome: è una stringa e non un numero, e le icone
                // per numero si trovano sempre. Bit alto nell'offset: punta a
                // un'altra directory invece che ai dati.
                let isNamed = (name & 0x8000_0000) != 0
                out.append(Entry(id: isNamed ? -1 : Int(name),
                                 offset: Int(value & 0x7FFF_FFFF),
                                 isDirectory: (value & 0x8000_0000) != 0))
            }
            return out
        }

        private func subdirectory(of directory: Int, id: Int) -> Int? {
            for e in entries(at: directory) where e.id == id && e.isDirectory {
                return absolute(e.offset)
            }
            return nil
        }
    }
}

// MARK: - Letture little-endian, che nel PE è l'ordine

private func le16(_ d: Data, _ o: Int) -> UInt16 {
    guard o >= 0, o + 1 < d.count else { return 0 }
    return UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8
}

private func le32(_ d: Data, _ o: Int) -> UInt32 {
    guard o >= 0, o + 3 < d.count else { return 0 }
    return UInt32(d[d.startIndex + o]) | UInt32(d[d.startIndex + o + 1]) << 8
         | UInt32(d[d.startIndex + o + 2]) << 16 | UInt32(d[d.startIndex + o + 3]) << 24
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) {
        append(contentsOf: [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)])
    }
    mutating func appendLE32(_ v: UInt32) {
        append(contentsOf: [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
                            UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)])
    }
}
