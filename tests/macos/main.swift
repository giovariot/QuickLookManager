import Foundation

// Quello che il pannello dice di un programma macOS, confrontato con gli
// strumenti di sistema che dicono la stessa cosa.
//
// Non è un test sul testo del codice: si leggono binari veri e si pretende che
// architetture e sistema minimo coincidano con `lipo` e `otool`, e che una
// firma manomessa venga vista come manomessa. È l'unico modo di accorgersi se
// una di queste letture smette di funzionare — un campo spostato, un ordine di
// byte sbagliato — perché il pannello continuerebbe a comparire, solo con
// dentro dei numeri finti.
//
// Argomenti: <binario> <architetture attese, da lipo> <minos atteso, da otool>
//            <copia ad hoc firmata> <la stessa copia, manomessa>

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

let binario = URL(fileURLWithPath: CommandLine.arguments[1])
// `lipo` su macOS 27 elenca anche «arm64e.x1», una variante di arm64e di cui
// lui stesso dice «unknown arm64 cpusubtype». Per il pannello è sempre Apple
// Silicon: qui si confrontano gli insiemi, non le targhette.
let atteseLipo = CommandLine.arguments[2].split(separator: " ").map {
    $0.hasPrefix("arm64e") ? "arm64e" : String($0)
}
let minosAtteso = CommandLine.arguments[3]
let firmata = URL(fileURLWithPath: CommandLine.arguments[4])
let manomessa = URL(fileURLWithPath: CommandLine.arguments[5])

// 1. Le architetture, tradotte come le scrive Apple.
guard let info = MachO.info(diBinario: binario) else {
    FileHandle.standardError.write(Data("il binario non si legge affatto\n".utf8))
    exit(1)
}
let nostre = Set(info.architetture.map { nome -> String in
    if nome.contains("arm64e") { return "arm64e" }
    if nome.hasPrefix("Apple Silicon") { return "arm64" }
    if nome == "Intel — 64-bit" { return "x86_64" }
    if nome == "Intel — 32-bit" { return "i386" }
    return nome
})
pretendi(nostre == Set(atteseLipo),
         "architetture \(nostre.sorted()) invece di \(atteseLipo.sorted()) (lipo)")

// 2. Il sistema minimo, quello che il compilatore ha scritto nel binario.
pretendi(info.minOS == minosAtteso,
         "sistema minimo \(info.minOS ?? "nessuno") invece di \(minosAtteso) (otool)")
pretendi(info.piattaforma == "macOS",
         "piattaforma \(info.piattaforma ?? "nessuna") invece di macOS")

// 3. Una firma intatta è intatta.
if let f = FirmaCodice.leggi(firmata) {
    if case .buona = f.valida {} else {
        errori.append("una copia appena firmata risulta non valida: \(f.valida)")
    }
    pretendi(f.firmato, "una copia firmata risulta non firmata")
} else {
    errori.append("della copia firmata non si legge niente")
}

// 4. Una firma manomessa si vede. È la riga per cui vale la pena mostrare
//    una firma: se qui dicessimo «valida» staremmo rassicurando a torto.
if let f = FirmaCodice.leggi(manomessa) {
    if case .rotta = f.valida {} else {
        errori.append("un binario manomesso dopo la firma risulta \(f.valida)")
    }
} else {
    errori.append("del binario manomesso non si legge niente")
}

// 5. Il verdetto di Gatekeeper si deduce dalla catena dei certificati, e le
//    regole sono quelle di macOS: senza notarizzazione un Developer ID non
//    basta più, una firma di sviluppo vale solo dove è nata.
pretendi(FirmaCodice.verdetto(autorita: ["Developer ID Application: Tizio (ABC)",
                                         "Developer ID Certification Authority", "Apple Root CA"],
                              notarizzato: true, adHoc: false, firmato: true)
         == "Developer ID notarizzato", "un Developer ID notarizzato non viene riconosciuto")
pretendi(FirmaCodice.verdetto(autorita: ["Developer ID Application: Tizio (ABC)",
                                         "Developer ID Certification Authority", "Apple Root CA"],
                              notarizzato: false, adHoc: false, firmato: true)
         == "Developer ID, senza biglietto incollato",
         "un Developer ID senza biglietto passa per notarizzato")
pretendi(FirmaCodice.verdetto(autorita: [], notarizzato: false, adHoc: false, firmato: false)
         == "Non firmato", "un programma non firmato non viene detto tale")

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    exit(1)
}
