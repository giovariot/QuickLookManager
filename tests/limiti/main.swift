import Foundation

// La guardia di formato: quando il fork nuovo non ci starebbe nei campi del
// formato, non si scrive niente.
//
// Il fork di risorse è del 1984: gli offset delle risorse stanno in tre byte,
// quelli dentro la mappa in due. Superarli non dà nessun errore — i bit in
// eccesso spariscono in silenzio e la mappa finisce per indirizzare il posto
// sbagliato. Su un programma del 1992 che magari è l'unica copia rimasta, un
// fork corrotto vale molto più di un'icona.

var errori: [String] = []
func pretendi(_ condizione: Bool, _ cosa: String) {
    if !condizione { errori.append(cosa) }
}

func oltreIlFormato(_ esito: Result<Data, ClassicIconWriter.Impedimento>) -> Bool {
    if case .failure(.oltreIlFormato) = esito { return true }
    return false
}

// Un'icona finta ma di misura vera: quello che conta qui sono i byte.
func icona(_ byte: Int) -> Data { Data(repeating: 0x2A, count: byte) }

// 1. Il caso normale continua a funzionare. Una guardia che rifiuta tutto
//    sarebbe passata inosservata: i file semplicemente non avrebbero più
//    l'icona, e nessuno lo saprebbe.
let piccolo = ClassicIconWriter.forkWithOnlyIcon(icona(2_320))
switch piccolo {
case .success(let fork):
    pretendi(fork.count > 2_320, "il fork costruito è più corto dell'icona che contiene")
    if case .failure = ClassicIconWriter.appendCustomIcon(to: fork, icns: icona(2_320)) {
        errori.append("un fork normale viene rifiutato: la guardia è troppo stretta")
    }
case .failure(let perche):
    errori.append("un'icona normale non si riesce a impacchettare: \(perche.descrizione)")
}

// 2. La sezione dati oltre i 16 MB che gli offset a 24 bit sanno indirizzare.
//    Si parte da un fork legittimo che ci arriva quasi, e gli si accoda
//    l'icona che lo fa sforare.
let quasi = ClassicIconWriter.forkWithOnlyIcon(icona(ClassicIconWriter.Limite.dati - 64))
guard case .success(let forkGrosso) = quasi else {
    FileHandle.standardError.write(Data("un fork da quasi 16 MB non si costruisce\n".utf8))
    exit(1)
}
pretendi(oltreIlFormato(ClassicIconWriter.appendCustomIcon(to: forkGrosso, icns: icona(2_320))),
         "i dati oltre i 16 MB non vengono fermati: l'offset a 24 bit verrebbe troncato")

// E nemmeno da zero: un'icona più grande di quanto il formato indirizzi non
// diventa un fork.
pretendi(oltreIlFormato(ClassicIconWriter.forkWithOnlyIcon(icona(ClassicIconWriter.Limite.dati + 1))),
         "un'icona oltre i 16 MB viene impacchettata lo stesso")

// 3. La mappa oltre i 64 KB che gli offset a 16 bit sanno indirizzare.
//    Si allunga la lista dei nomi di un fork vero: è la parte della mappa che
//    passa di là così com'è, quindi cresce con lei.
guard case .success(var conNomi) = ClassicIconWriter.forkWithOnlyIcon(icona(512)) else {
    FileHandle.standardError.write(Data("il fork di prova non si costruisce\n".utf8))
    exit(1)
}
func be32(_ d: Data, _ o: Int) -> Int {
    Int(d[d.startIndex + o]) << 24 | Int(d[d.startIndex + o + 1]) << 16
  | Int(d[d.startIndex + o + 2]) << 8 | Int(d[d.startIndex + o + 3])
}
let mapOff = be32(conNomi, 4), mapLen = be32(conNomi, 12)
let nomi = 70_000
conNomi.append(Data(repeating: 0x41, count: nomi))
for (k, b) in [UInt8(truncatingIfNeeded: (mapLen + nomi) >> 24),
               UInt8(truncatingIfNeeded: (mapLen + nomi) >> 16),
               UInt8(truncatingIfNeeded: (mapLen + nomi) >> 8),
               UInt8(truncatingIfNeeded: mapLen + nomi)].enumerated() {
    conNomi[conNomi.startIndex + 12 + k] = b
}
pretendi(mapOff + mapLen + nomi == conNomi.count, "il fork di prova non torna nelle misure")
pretendi(oltreIlFormato(ClassicIconWriter.appendCustomIcon(to: conNomi, icns: icona(2_320))),
         "una mappa oltre i 64 KB non viene fermata: gli offset a 16 bit verrebbero troncati")

// 4. Un fork illeggibile resta un caso a parte: non è «troppo grande», è «non
//    si capisce», e chi chiama deve poterli distinguere — uno si salta, l'altro
//    è un guasto da raccontare.
if case .failure(.illeggibile) = ClassicIconWriter.appendCustomIcon(to: Data(repeating: 0, count: 8),
                                                                    icns: icona(64)) {
} else {
    errori.append("un fork illeggibile non viene riconosciuto come tale")
}

if errori.isEmpty {
    print("ok")
} else {
    errori.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    exit(1)
}
