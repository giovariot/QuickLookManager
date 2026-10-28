import Foundation

// Quali volumi vale la pena prendere in carico con l'agente.
//
// Il guasto: si osservava **ogni** volume montato. Ma il Finder mette nella
// barra laterale l'icona dell'applicazione a cui l'estensione appartiene al
// posto dell'icona del disco — è scritto nella guida di Apple — e così ogni
// disco esterno si ritrovava la nostra icona, anche quando sul desktop la sua
// compariva giusta. Su un disco moderno, poi, non avevamo comunque niente da
// fare.
//
// Argomenti: <volume con roba classica> <volume moderno>

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

let classico = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let moderno = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

pretendi(VolumeClassico.contiene(volume: classico),
         "un volume con un file dal type classico non viene riconosciuto: l'estensione non lo guarderebbe")
pretendi(!VolumeClassico.contiene(volume: moderno),
         "un volume moderno viene osservato lo stesso: il Finder gli cambierebbe l'icona nella barra laterale")

// Il database delle icone basta da solo: su un disco di System 6 i file possono
// anche non avere un FinderInfo leggibile da qui, ma il `Desktop` c'è.
let conDatabase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("volume-finto-\(getpid())", isDirectory: true)
try? FileManager.default.createDirectory(at: conDatabase, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: conDatabase.appendingPathComponent("Desktop DB").path,
                               contents: Data([0x00]))
pretendi(VolumeClassico.contiene(volume: conDatabase),
         "il database delle icone non basta a far riconoscere un disco classico")
try? FileManager.default.removeItem(at: conDatabase)

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    exit(1)
}
