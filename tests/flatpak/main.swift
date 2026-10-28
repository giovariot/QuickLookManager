import Foundation

// Il lettore dei pacchetti Flatpak, provato su byte prodotti da GLib.
//
// Il file di prova lo costruisce `finto-bundle.c` con l'implementazione di
// riferimento di GVariant: se avessimo capito male la specifica, qui si vede,
// mentre un file costruito da noi ci darebbe ragione per sbaglio.
//
// Argomenti: <finto.flatpak> <la stessa icona che ci è stata messa dentro>

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
let icona = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))

guard let info = FlatpakBundle.leggi(bundle) else {
    FileHandle.standardError.write(Data("il pacchetto non si legge affatto\n".utf8))
    exit(1)
}

pretendi(info.ref == "app/org.gnome.Dictionary/x86_64/stable",
         "ref \(info.ref ?? "nessuno")")
pretendi(info.origine == "https://dl.flathub.org/repo/", "origine \(info.origine ?? "nessuna")")
pretendi(info.runtimeRepo?.hasSuffix("flathub.flatpakrepo") == true,
         "runtime-repo \(info.runtimeRepo ?? "nessuno")")
pretendi(info.pesoInstallato == 12_345_678,
         "peso installato \(info.pesoInstallato.map(String.init) ?? "nessuno")")

// L'icona è il motivo per cui tutto questo esiste: dev'essere quel PNG, byte
// per byte, e non «un PNG qualunque».
pretendi(info.icona == icona,
         "l'icona è \(info.icona?.count ?? 0) byte invece di \(icona.count), o non è la stessa")

// Il file `metadata` è un INI, e da lì vengono runtime, sdk e comando.
pretendi(FlatpakBundle.campo("name", in: info.metadata) == "org.gnome.Dictionary",
         "name: \(FlatpakBundle.campo("name", in: info.metadata) ?? "nessuno")")
pretendi(FlatpakBundle.campo("runtime", in: info.metadata) == "org.gnome.Platform/x86_64/45",
         "runtime: \(FlatpakBundle.campo("runtime", in: info.metadata) ?? "nessuno")")
pretendi(FlatpakBundle.campo("sdk", in: info.metadata) == "org.gnome.Sdk/x86_64/45",
         "sdk: \(FlatpakBundle.campo("sdk", in: info.metadata) ?? "nessuno")")
// `sdk` non deve farsi trovare da chi cerca `sd`, e `name` non deve rispondere
// a chi cerca `runtime`: le chiavi si confrontano intere.
pretendi(FlatpakBundle.campo("sd", in: info.metadata) == nil,
         "una chiave parziale trova lo stesso qualcosa")

// Le righe del pannello, che è quello che l'utente vede.
let righe = FlatpakBundle.righe(info)
let etichette = righe.compactMap { $0.etichetta }
for attesa in ["Identificatore", "Architettura", "Ramo", "Runtime", "SDK", "Comando"] {
    pretendi(etichette.contains(attesa), "manca la riga «\(attesa)»")
}

// Un file che Flatpak non è non deve passare per tale.
let finto = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nonflatpak.bin")
try? Data(repeating: 0x41, count: 4096).write(to: finto)
pretendi(FlatpakBundle.leggi(finto) == nil, "un file qualunque viene letto come pacchetto Flatpak")
try? FileManager.default.removeItem(at: finto)

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    exit(1)
}
