import Foundation

// Il giro del volume, la scelta dei volumi e i percorsi non fidati, provati su
// cartelle vere. Sostituisce i controlli che cercavano nel testo del codice
// parole come «tettoPredefinito» o «MNT_RDONLY»: un controllo sul testo passa
// anche con un tetto che non ferma niente.

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

let fm = FileManager.default
let base = fm.temporaryDirectory.appendingPathComponent("percorso-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: base) }

for k in 0..<10 {
    fm.createFile(atPath: base.appendingPathComponent("file\(k)").path, contents: Data("x".utf8))
}

// Il giro ha un tetto, e lo dice: oltre il tetto si ferma e segna «troncato».
let corto = IconeAutomatiche.percorri(volume: base, tetto: 3)
pretendi(corto.troncato, "con 10 file e tetto 3 il giro non risulta troncato")
pretendi(corto.guardati == 4, "il giro ha guardato \(corto.guardati) file invece di fermarsi al quarto")
pretendi(corto.scritti == 0 && corto.falliti == 0, "il giro ha scritto o fallito su file che non sono classici")

// Senza raggiungere il tetto li guarda tutti e non dice niente.
let intero = IconeAutomatiche.percorri(volume: base, tetto: 100)
pretendi(!intero.troncato, "con tetto 100 e 10 file il giro risulta troncato")
pretendi(intero.guardati == 10, "il giro ha guardato \(intero.guardati) file invece di 10")

// Chi lo ha chiesto lo può fermare, e il giro lo dice.
var chiamate = 0
let fermato = IconeAutomatiche.percorri(volume: base, fermarsi: { chiamate += 1; return chiamate > 2 })
pretendi(fermato.interrotto, "il giro fermato non risulta interrotto")
pretendi(fermato.guardati == 2, "il giro fermato ha guardato \(fermato.guardati) file invece di 2")

// Una cartella normale è scrivibile e non è un volume di rete; la radice del
// sistema, da macOS 11 in poi, è sigillata e di sola lettura.
pretendi(VolumeClassico.scrivibile(base), "una cartella temporanea risulta non scrivibile")
pretendi(!VolumeClassico.eDiRete(base), "una cartella locale risulta un volume di rete")
pretendi(!VolumeClassico.scrivibile(URL(fileURLWithPath: "/")), "la radice di sistema risulta scrivibile")

// I percorsi del magazzino stanno su un disco di chiunque: non devono poter
// uscire dal volume, nemmeno con un collegamento simbolico.
fm.createFile(atPath: base.appendingPathComponent("ok").path, contents: Data("x".utf8))
try fm.createSymbolicLink(at: base.appendingPathComponent("verso-fuori"),
                          withDestinationURL: URL(fileURLWithPath: "/etc", isDirectory: true))
try fm.createSymbolicLink(at: base.appendingPathComponent("a-file"),
                          withDestinationURL: base.appendingPathComponent("ok"))
pretendi(ForkBackup.urlSicuro(percorso: "ok", radice: base) != nil, "un file normale è rifiutato")
pretendi(ForkBackup.urlSicuro(percorso: "verso-fuori/hosts", radice: base) == nil,
         "un percorso che passa da un collegamento verso l'esterno è accettato")
pretendi(ForkBackup.urlSicuro(percorso: "a-file", radice: base) == nil,
         "un collegamento simbolico viene scambiato per un file")
pretendi(ForkBackup.urlSicuro(percorso: "../fuori", radice: base) == nil, "un percorso con .. è accettato")
pretendi(ForkBackup.urlSicuro(percorso: "/etc/hosts", radice: base) == nil, "un percorso assoluto è accettato")

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    try? fm.removeItem(at: base)
    exit(1)
}
