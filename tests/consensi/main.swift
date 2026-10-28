import Foundation

// I permessi disco per disco: si scrivono, si rileggono, si dimenticano, e un
// file illeggibile vale come vuoto (meglio richiedere che fidarsi di un file
// che nessuno sa leggere).

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

let fm = FileManager.default
let cartella = fm.temporaryDirectory.appendingPathComponent("consensi-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: cartella, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: cartella) }
ConsensiDischi.cartellaDiProva = cartella

pretendi(ConsensiDischi.tutti().isEmpty, "senza file ci sono già dei permessi")

pretendi(ConsensiDischi.imposta(.consentito, id: "AAA", nome: "Disco A"), "il permesso non si scrive")
pretendi(ConsensiDischi.imposta(.rifiutato, id: "BBB", nome: "Beta"), "il rifiuto non si scrive")

let tutti = ConsensiDischi.tutti()
pretendi(tutti.count == 2, "i permessi sono \(tutti.count) invece di 2")
pretendi(tutti.first?.voce.nome == "Beta", "i dischi non sono in ordine di nome")
pretendi(tutti.first(where: { $0.id == "AAA" })?.voce.stato == .consentito, "il permesso non torna com'era")
pretendi(tutti.first(where: { $0.id == "BBB" })?.voce.stato == .rifiutato, "il rifiuto non torna com'era")

// Un volume vero: il permesso si lega al suo identificativo, e lo stesso volume
// lo ritrova.
let radice = URL(fileURLWithPath: "/")
pretendi(!ConsensiDischi.identificativo(radice).isEmpty, "il volume di avvio non ha identificativo")
pretendi(ConsensiDischi.stato(radice) == nil, "un volume mai visto ha già un permesso")
pretendi(ConsensiDischi.imposta(.consentito, per: radice), "il permesso per un volume non si scrive")
pretendi(ConsensiDischi.stato(radice) == .consentito, "lo stesso volume non ritrova il suo permesso")

// Dimenticare toglie la risposta: la volta dopo si richiede.
pretendi(ConsensiDischi.imposta(nil, id: "AAA", nome: ""), "il permesso non si dimentica")
pretendi(ConsensiDischi.tutti().first(where: { $0.id == "AAA" }) == nil, "il permesso dimenticato c'è ancora")

// Il file è JSON leggibile da chi lo vuole guardare.
let dati = try Data(contentsOf: cartella.appendingPathComponent("dischi.json"))
pretendi((try? JSONSerialization.jsonObject(with: dati)) != nil, "dischi.json non è JSON")

// Un file illeggibile vale come vuoto.
try Data("non e' json".utf8).write(to: cartella.appendingPathComponent("dischi.json"))
pretendi(ConsensiDischi.tutti().isEmpty, "un file illeggibile viene letto come se avesse permessi")

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    try? fm.removeItem(at: cartella)
    exit(1)
}
