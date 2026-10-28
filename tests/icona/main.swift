// Le icone classiche, come macOS finisce per disegnarle.
//
// Non basta che esca un `.icns`: conta *cosa* esce. Le risorse classiche
// vanno decodificate e riconfezionate, non copiate dentro. Copiarle dentro è
// quello che si faceva prima, e produceva l'icona nei colori sbagliati su un
// quadrato bianco opaco — perché fra `icl4` e `icl8`, una volta decodificate
// in RGBA, macOS ne sceglie una a caso, e la maschera che sta in `ICN#` non la
// applica a nessuna delle due.

import AppKit
import Foundation

var falliti = 0

func controlla(_ cosa: String, _ ok: Bool) {
    print(ok ? "  \u{001B}[32m✓\u{001B}[0m \(cosa)" : "  \u{001B}[31m✗\u{001B}[0m \(cosa)")
    if !ok { falliti += 1 }
}

/// Un fork di risorse costruito a mano, con dentro solo quello che serve.
func forkConRisorse(_ risorse: [(tipo: String, id: Int16, dati: [UInt8])]) -> Data {
    var dati = Data()
    var offsets: [Int] = []
    for r in risorse {
        offsets.append(dati.count)
        dati.be32(UInt32(r.dati.count))
        dati.append(contentsOf: r.dati)
    }

    // Raggruppate per tipo, nell'ordine in cui sono arrivate.
    var tipi: [String] = []
    for r in risorse where !tipi.contains(r.tipo) { tipi.append(r.tipo) }

    var typeList = Data()
    typeList.appendBE16(UInt16(tipi.count - 1))
    var refList = Data()
    var refOffset = 2 + tipi.count * 8
    for tipo in tipi {
        let dello = risorse.enumerated().filter { $0.element.tipo == tipo }
        typeList.append(contentsOf: Array(tipo.utf8))
        typeList.appendBE16(UInt16(dello.count - 1))
        typeList.appendBE16(UInt16(refOffset))
        for (indice, r) in dello {
            refList.appendBE16(UInt16(bitPattern: r.id))
            refList.appendBE16(0xFFFF)                 // niente nome
            refList.be32(UInt32(offsets[indice]))
            refList.be32(0)
        }
        refOffset += dello.count * 12
    }

    var mappa = Data(repeating: 0, count: 24)
    mappa.appendBE16(28)                               // dove comincia la lista dei tipi
    mappa.appendBE16(UInt16(28 + typeList.count + refList.count))
    mappa.append(typeList)
    mappa.append(refList)

    var fork = Data()
    fork.be32(256)
    fork.be32(UInt32(256 + dati.count))
    fork.be32(UInt32(dati.count))
    fork.be32(UInt32(mappa.count))
    fork.append(Data(repeating: 0, count: 256 - 16))
    fork.append(dati)
    fork.append(mappa)
    return fork
}

private extension Data {
    mutating func appendBE16(_ v: UInt16) {
        append(contentsOf: [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)])
    }
    mutating func be32(_ v: UInt32) {
        append(contentsOf: [UInt8(truncatingIfNeeded: v >> 24), UInt8(truncatingIfNeeded: v >> 16),
                            UInt8(truncatingIfNeeded: v >> 8),  UInt8(truncatingIfNeeded: v)])
    }
}

print("── Icone classiche ───────────────────────────────────")

// Una famiglia 32×32: maschera accesa sui primi sedici pixel di ogni riga,
// `icl8` tutta nell'indice 35 — rosso pieno — e `icl4` tutta nell'indice 6, che
// nella tavolozza a sedici colori è blu. Se il blu arriva all'uscita, ha vinto
// il membro sbagliato.
var mono = [UInt8](repeating: 0, count: 256)
for riga in 0..<32 {
    mono[riga * 4] = 0xFF
    mono[128 + riga * 4] = 0xFF
    mono[128 + riga * 4 + 1] = 0xFF
}
let fork = forkConRisorse([("ICN#", -16455, mono),
                           ("icl8", -16455, [UInt8](repeating: 35, count: 1024)),
                           ("icl4", -16455, [UInt8](repeating: 0x66, count: 512))])

guard let letto = ClassicIcon.Fork(fork) else {
    print("  \u{001B}[31m✗\u{001B}[0m il fork di prova non si rilegge")
    exit(1)
}
controlla("il fork di prova si rilegge", letto.data(type: "icl8", id: -16455)?.count == 1024)

guard let icns = ClassicIcon.icns(from: letto, id: -16455) else {
    print("  \u{001B}[31m✗\u{001B}[0m non esce nessuna icona")
    exit(1)
}
controlla("esce un'icona", icns.count > 8 && icns.prefix(4) == Data("icns".utf8))

// Le voci: devono essere PNG, non le risorse classiche ricopiate.
var voci: [String] = []
var at = 8
while at + 8 <= icns.count {
    let tipo = String(bytes: icns[icns.startIndex + at ..< icns.startIndex + at + 4], encoding: .macOSRoman) ?? "?"
    let n = Int(icns[icns.startIndex + at + 4]) << 24 | Int(icns[icns.startIndex + at + 5]) << 16
          | Int(icns[icns.startIndex + at + 6]) << 8  | Int(icns[icns.startIndex + at + 7])
    if n < 8 { break }
    voci.append(tipo)
    at += n
}
controlla("nessuna risorsa classica ricopiata dentro",
          !voci.contains("ICN#") && !voci.contains("icl8") && !voci.contains("icl4"))

guard let immagine = NSImage(data: icns),
      let rep = immagine.representations.compactMap({ $0 as? NSBitmapImageRep })
                       .first(where: { $0.pixelsWide == 32 })
else {
    print("  \u{001B}[31m✗\u{001B}[0m l'icona non si riapre a 32 pixel")
    exit(1)
}

// La maschera era accesa sui primi sedici pixel di ogni riga.
let dentro = rep.colorAt(x: 2, y: 2)
let fuori  = rep.colorAt(x: 30, y: 2)
controlla("opaca dove la maschera era accesa", (dentro?.alphaComponent ?? 0) > 0.9)
controlla("trasparente dove era spenta",       (fuori?.alphaComponent ?? 1) < 0.1)

let r = (dentro?.usingColorSpace(.deviceRGB)?.redComponent ?? 0)
let b = (dentro?.usingColorSpace(.deviceRGB)?.blueComponent ?? 1)
controlla("rossa dove il membro a 256 colori diceva rosso", r > 0.9 && b < 0.1)

print(falliti == 0 ? "  tutto a posto" : "  \(falliti) falliti")
exit(falliti == 0 ? 0 : 1)
