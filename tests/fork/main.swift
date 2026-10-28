import Foundation

// Quando si accoda l'icona a un fork, tutto il resto del fork passa intatto:
// l'area riservata fra intestazione e dati (in SimpleText erano venti byte non
// vuoti), la copia dell'intestazione in testa alla mappa, gli attributi del
// file e ogni risorsa originale. Sostituisce un controllo che cercava due
// chiamate a `memcpy` nel testo del codice.

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

/// Un fork valido con una risorsa 'TEST', un'area riservata non vuota e
/// attributi di mappa diversi da zero.
func forkDiProva(dati: Data) -> Data {
    let dataLen = 4 + dati.count
    let mapLen = 28 + 2 + 8 + 12
    let nd = 256, nm = nd + dataLen
    var out = Data(count: nd + dataLen + mapLen)
    func put32(_ at: Int, _ v: Int) {
        for k in 0..<4 { out[at + k] = UInt8(truncatingIfNeeded: v >> (24 - 8 * k)) }
    }
    func put16(_ at: Int, _ v: Int) {
        out[at] = UInt8(truncatingIfNeeded: v >> 8); out[at + 1] = UInt8(truncatingIfNeeded: v)
    }
    put32(0, nd); put32(4, nm); put32(8, dataLen); put32(12, mapLen)
    for k in 16..<nd { out[k] = UInt8(truncatingIfNeeded: k * 7 + 3) }      // area riservata
    put32(nd, dati.count)
    out.replaceSubrange((nd + 4)..<(nd + 4 + dati.count), with: dati)
    out[nm + 22] = 0x12; out[nm + 23] = 0x34                                  // attributi
    let tl = 28
    put16(nm + 24, tl); put16(nm + 26, tl + 2 + 8 + 12)
    put16(nm + tl, 0)
    for (k, c) in Array("TEST".utf8).enumerated() { out[nm + tl + 2 + k] = c }
    put16(nm + tl + 6, 0); put16(nm + tl + 8, 2 + 8)
    let ref = nm + tl + 2 + 8
    put16(ref, 128); put16(ref + 2, 0xFFFF)
    return out
}

let blob = Data((0..<500).map { UInt8($0 % 251) })
let originale = forkDiProva(dati: blob)
let icona = Data("icns".utf8) + Data(repeating: 0x42, count: 300)

guard case .success(let nuovo) = ClassicIconWriter.appendCustomIcon(to: originale, icns: icona) else {
    FileHandle.standardError.write(Data("l'icona non si accoda a un fork valido\n".utf8))
    exit(1)
}

// Ogni risorsa originale c'è, identica, e la nostra icona è dove deve stare.
guard let letto = ClassicIcon.Fork(nuovo), let prima = ClassicIcon.Fork(originale) else {
    FileHandle.standardError.write(Data("il fork risultante non si legge\n".utf8))
    exit(1)
}
pretendi(ClassicIconWriter.verify(original: prima, rebuilt: nuovo), "una risorsa originale non torna identica")
pretendi(letto.data(type: "TEST", id: 128) == blob, "la risorsa di prova non è passata intatta")
pretendi(letto.data(type: "icns", id: -16455) == icona, "l'icona accodata non si ritrova")

// L'area riservata passa tale e quale.
pretendi(nuovo.subdata(in: 16..<256) == originale.subdata(in: 16..<256),
         "l'area riservata fra intestazione e dati è stata alterata")

// La mappa: copia dell'intestazione in testa, attributi del file portati di là.
func be32(_ d: Data, _ o: Int) -> Int {
    (Int(d[o]) << 24) | (Int(d[o+1]) << 16) | (Int(d[o+2]) << 8) | Int(d[o+3])
}
let nm = be32(nuovo, 4)
pretendi(nuovo.subdata(in: nm..<(nm + 16)) == nuovo.subdata(in: 0..<16),
         "la testa della mappa non è una copia dell'intestazione")
pretendi(nuovo[nm + 22] == 0x12 && nuovo[nm + 23] == 0x34, "gli attributi della mappa sono stati azzerati")

// Il fork con la sola icona (per i documenti) si legge e contiene solo quella.
guard case .success(let solo) = ClassicIconWriter.forkWithOnlyIcon(icona),
      let soloLetto = ClassicIcon.Fork(solo) else {
    FileHandle.standardError.write(Data("il fork con la sola icona non si costruisce\n".utf8))
    exit(1)
}
pretendi(soloLetto.resources.count == 1 && soloLetto.data(type: "icns", id: -16455) == icona,
         "il fork con la sola icona contiene altro")

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    exit(1)
}
