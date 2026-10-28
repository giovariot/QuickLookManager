import Foundation

// Il ripristino dei fork, provato su un volume vero.
//
// Non è un test sul testo del codice: qui si scrive davvero un fork, lo si
// sostituisce come fa l'agente, e si pretende che `restoreAll` riporti
// ogni file al byte di partenza. Il guasto da cui nasce è concreto — un
// `setxattr` più corto non accorcia il fork — e si vede solo su un filesystem.
//
// Vuole come argomento la radice di un volume montato in scrittura.

let volume = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

func xattr(_ url: URL, _ nome: String) -> Data? {
    let n = url.withUnsafeFileSystemRepresentation { getxattr($0, nome, nil, 0, 0, 0) }
    guard n >= 0 else { return nil }
    var buf = [UInt8](repeating: 0, count: n)
    let letti = url.withUnsafeFileSystemRepresentation { getxattr($0, nome, &buf, n, 0, 0) }
    guard letti == n else { return nil }
    return Data(buf)
}

@discardableResult
func scrivi(_ url: URL, _ nome: String, _ valore: Data) -> Bool {
    url.withUnsafeFileSystemRepresentation { path in
        // setxattr con un valore piu' corto non accorcia il fork: si toglie
        // prima, come fa il prodotto, o il test prepara un fork che non e' quello voluto.
        _ = removexattr(path, nome, 0)
        return valore.withUnsafeBytes { b in
            setxattr(path, nome, b.baseAddress, b.count, 0, 0) == 0
        }
    } 
}

// Un fork valido con una sola risorsa, di un tipo qualunque. Il ripristino
// distingue «il fork è ancora quello scritto da noi» da «qualcuno lo ha salvato
// di nuovo», e per farlo lo legge come un fork: un mucchio di byte a caso non
// basta più.
func forkCon(tipo: String, id: Int16, dati: Data) -> Data {
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
    put32(nd, dati.count)
    out.replaceSubrange((nd + 4)..<(nd + 4 + dati.count), with: dati)
    let tl = 28
    put16(nm + 24, tl); put16(nm + 26, tl + 2 + 8 + 12)
    put16(nm + tl, 0)
    for (k, c) in Array(tipo.utf8).enumerated() { out[nm + tl + 2 + k] = c }
    put16(nm + tl + 6, 0); put16(nm + tl + 8, 2 + 8)
    let ref = nm + tl + 2 + 8
    put16(ref, Int(UInt16(bitPattern: id))); put16(ref + 2, 0xFFFF)
    return out
}

func accendiBit(_ f: URL) {
    var info = xattr(f, "com.apple.FinderInfo") ?? Data(repeating: 0, count: 32)
    if info.count != 32 { info = Data(repeating: 0, count: 32) }
    info[8] |= 0x04
    scrivi(f, "com.apple.FinderInfo", info)
}

// Un fork di partenza: al ripristino deve tornare identico, byte per
// byte. Non serve che sia un fork valido — serve che sia *quello*.
let forkOriginale = forkCon(tipo: "TEST", id: 128, dati: Data((0..<4096).map { UInt8($0 % 251) }))
let iconaNostra = Data("icns".utf8) + Data(repeating: 0x42, count: 2000)

let conFork = volume.appendingPathComponent("con-fork")
let senzaFork = volume.appendingPathComponent("senza-fork")
let modificato = volume.appendingPathComponent("modificato")
FileManager.default.createFile(atPath: conFork.path, contents: Data("dati".utf8))
FileManager.default.createFile(atPath: senzaFork.path, contents: Data("dati".utf8))
FileManager.default.createFile(atPath: modificato.path, contents: Data("dati".utf8))
scrivi(conFork, "com.apple.ResourceFork", forkOriginale)
scrivi(modificato, "com.apple.ResourceFork", forkOriginale)

// Quello che fa l'agente: conserva il fork di partenza, poi scrive il
// suo. Per il file che un fork non ce l'aveva si conserva un valore vuoto, che
// è un'informazione e non un vuoto.
pretendi(ForkBackup.conserva(fork: forkOriginale, di: conFork), "il fork non si è conservato")
pretendi(ForkBackup.conserva(fork: Data(), di: senzaFork), "il fork vuoto non si è conservato")
pretendi(ForkBackup.conserva(fork: forkOriginale, di: modificato), "il fork del file modificato non si è conservato")

// Il magazzino c'è, è invisibile ai due Finder, e sa contare.
let magazzino = ForkBackup.percorso(perVolumeDi: conFork)!
pretendi(magazzino.lastPathComponent == ".OldForksBackup", "il magazzino ha un altro nome")
pretendi(FileManager.default.fileExists(atPath: magazzino.path), "il magazzino non esiste")
if let info = xattr(magazzino, "com.apple.FinderInfo"), info.count == 32 {
    pretendi(info[8] & 0x40 != 0, "il magazzino non ha il bit kIsInvisible: su Mac OS 9 si vedrebbe")
} else {
    errori.append("il magazzino non ha nessun FinderInfo: su Mac OS 9 si vedrebbe")
}
pretendi((try? magazzino.resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true,
         "il magazzino non è nascosto al Finder di oggi")
pretendi(ForkBackup.quanti(sulVolumeDi: volume) == 3,
         "il magazzino conta \(ForkBackup.quanti(sulVolumeDi: volume)) file invece di 3")

// E adesso la modifica, come la fa il writer: al file che un fork ce l'aveva si
// accoda la nostra icona (un fork più lungo dell'originale è il caso che fa
// male, perché scriverci sopra quello corto non lo accorcia); al file che non
// ce l'aveva si dà un fork con la sola icona. In tutti si accende il bit.
func costruisci(_ r: Result<Data, ClassicIconWriter.Impedimento>) -> Data {
    switch r {
    case .success(let d): return d
    case .failure: fatalError("il fork di prova non si costruisce")
    }
}
let conIcona = costruisci(ClassicIconWriter.appendCustomIcon(to: forkOriginale, icns: iconaNostra))
let soloIcona = costruisci(ClassicIconWriter.forkWithOnlyIcon(iconaNostra))
scrivi(conFork, "com.apple.ResourceFork", conIcona)
scrivi(senzaFork, "com.apple.ResourceFork", soloIcona)

// Il terzo è stato salvato di nuovo da qualcuno DOPO la nostra icona: una sua
// risorsa è cambiata. Il ripristino non deve cancellargli il lavoro.
let forkDiChiLoHaModificato = forkCon(tipo: "TEST", id: 128, dati: Data("lavoro dell'utente".utf8))
scrivi(modificato, "com.apple.ResourceFork", forkDiChiLoHaModificato)
for f in [conFork, senzaFork, modificato] { accendiBit(f) }

let esito = ClassicIconWriter.restoreAll(onVolume: volume)
pretendi(esito.fatti == 2 && esito.falliti == 0 && esito.lasciati == 1,
         "ripristinati \(esito.fatti), falliti \(esito.falliti), lasciati \(esito.lasciati): dovevano essere 2, 0 e 1")

// Il file modificato dopo di noi resta com'è, byte per byte: il suo fork è
// roba di qualcun altro. Si spegne soltanto il bit, che è l'unica cosa nostra.
pretendi(xattr(modificato, "com.apple.ResourceFork") == forkDiChiLoHaModificato,
         "il ripristino ha toccato il fork di un file modificato dopo l'icona")
if let info = xattr(modificato, "com.apple.FinderInfo"), info.count == 32 {
    pretendi(info[8] & 0x04 == 0, "il file modificato ha ancora il bit dell'icona acceso")
}

// I percorsi del magazzino stanno su un disco che può essere di chiunque: non
// devono poter uscire dal volume.
pretendi(ForkBackup.urlSicuro(percorso: "../fuori", radice: volume) == nil, "un percorso con .. esce dal volume")
pretendi(ForkBackup.urlSicuro(percorso: "a/../../fuori", radice: volume) == nil, "un .. in mezzo esce dal volume")
pretendi(ForkBackup.urlSicuro(percorso: "/etc/hosts", radice: volume) == nil, "un percorso assoluto è accettato")
pretendi(ForkBackup.urlSicuro(percorso: "", radice: volume) == nil, "un percorso vuoto è accettato")

// Dopo il ripristino c'è il segno, e l'agente lo vede.
pretendi(ForkBackup.ultimoRipristino(delVolumeDi: volume) != nil, "il ripristino non ha lasciato il segno per l'agente")

// Il file che un fork ce l'aveva torna esattamente quello di prima. Non «più o
// meno»: la stessa lunghezza e gli stessi byte.
let riletto = xattr(conFork, "com.apple.ResourceFork")
pretendi(riletto?.count == forkOriginale.count,
         "il fork è lungo \(riletto?.count ?? -1) invece di \(forkOriginale.count): non si è accorciato")
pretendi(riletto == forkOriginale, "il fork ripristinato non è quello di partenza")

// Quello che non ce l'aveva resta senza: un fork vuoto vuol dire assente, non
// presente e lungo zero.
pretendi(xattr(senzaFork, "com.apple.ResourceFork") == nil,
         "al file senza fork ne è rimasto uno addosso")

// Il bit dell'icona si spegne, se no il Finder continua a cercare un'icona che
// non c'è più.
for f in [conFork, senzaFork, modificato] {
    if let info = xattr(f, "com.apple.FinderInfo"), info.count == 32 {
        pretendi(info[8] & 0x04 == 0, "\(f.lastPathComponent): il bit dell'icona è rimasto acceso")
    }
}

// A ripristino riuscito il magazzino si butta: tenerlo vorrebbe dire proporre
// all'utente un ripristino che non ha più niente da fare.
pretendi(!FileManager.default.fileExists(atPath: magazzino.path),
         "il magazzino è rimasto anche se il ripristino è riuscito")

// Il ripiego, per i volumi in cui la radice non è nostra — il disco di avvio.
// Deve cadere nella home vera e non nel contenitore della sandbox: se no chi
// scrive (l'estensione, in sandbox) e chi ripristina (l'applicazione, fuori)
// guardano due posti diversi, e il ripristino risponde che non c'è niente da
// fare mentre i file sono stati modificati.
let casa = String(cString: getpwuid(getuid())!.pointee.pw_dir!)
if let ripiego = ForkBackup.percorso(perVolumeDi: URL(fileURLWithPath: "/usr/bin/true")) {
    pretendi(ripiego.path.hasPrefix(casa + "/Library/Application Support/QLAppBundle/ForkBackup"),
             "il ripiego del disco di avvio finisce in \(ripiego.path), non nella home vera")
    pretendi(!ripiego.path.contains("/Library/Containers/"),
             "il ripiego finisce nel contenitore della sandbox: l'applicazione non lo troverebbe")
} else {
    errori.append("per il disco di avvio non viene fuori nessun magazzino")
}

// La cartella di ripiego l'ha creata la prova chiedendo il percorso: se è
// rimasta vuota, non deve restare in giro dopo un test.
if let ripiego = ForkBackup.percorso(perVolumeDi: URL(fileURLWithPath: "/usr/bin/true")) {
    let cartella = ripiego.deletingLastPathComponent()
    if (try? FileManager.default.contentsOfDirectory(atPath: cartella.path))?.isEmpty == true {
        try? FileManager.default.removeItem(at: cartella)
    }
}

try? FileManager.default.removeItem(at: conFork)
try? FileManager.default.removeItem(at: senzaFork)
try? FileManager.default.removeItem(at: modificato)
ForkBackup.dimenticaRipristino(delVolumeDi: volume)

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    exit(1)
}
