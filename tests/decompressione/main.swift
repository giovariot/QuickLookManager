// Prova della decompressione delle risorse (dcmp 0 e 1). Il campione è la icl4 128 dell'Installer del
// CD-ROM Setup 4.04, ancora compressa; il risultato atteso è l'uscita di resource_dasm sullo stesso file.
import Foundation
var guasti: [String] = []
func controlla(_ ok: Bool, _ msg: String) { if !ok { guasti.append(msg) } }
func da(_ hex: String) -> Data { var d = Data(); var i = hex.startIndex; while i < hex.endIndex { let j = hex.index(i, offsetBy: 2); d.append(UInt8(hex[i..<j], radix: 16)!); i = j }; return d }
let compressa = da("a89f657200120801000002006503000000001300000000000097232312000000fc15f00000000000000000001200000000110fc013cf0000000000234b11fc0c120cf0000023120000000f12c0c0c0cf23261200fc0c0c120c0cf000234b2712cfffffc0282629120fffff0c2a269713c0c0cfffffc012c0cf0000262d302e26273111c0c02829010cff12ffffffff292a972c342c24120c0c0c0c6c5b3511f0002712c0c0c0c02f3711cf002935010cff2935010cf0273701c0cf3733382d35352e9737372c2629010c0f34010c0c2a4b2701c0fc12cccccccc01f0c0281100fc030cfceeeeeeec2913f000000000009701c0fc12e0d0d0cc01f0cf234b04fcfced0d0d0cfcf0234b010ffc3c9a232401dc0c2e232439253a018ccc16ccccf00000000000000000003a013ccf5b253a392597342326973423ff")
let attesa = da("000000000000000f000000000000000000000000000000fcf0000000000000000000000000000fc0cf00000000000000000000000000fc0c0cf000000000000000000000000fc0c0c0cf0000000000000000000000fc0c0c0c0cf00000000000000000000fc0cfffffc0cf000000000000000000fc0c0fffff0c0cf0000000000000000fc0c0cfffffc0c0cf00000000000000fc0c0c0fffff0c0c0cf000000000000fc0c0c0cfffffc0c0c0cf0000000000fc0c0cfffffffffffc0c0cf00000000fc0c0c0cfffffffffc0c0c0cf000000fc0c0c0c0cfffffffc0c0c0c0cf0000fc0c0c0c0c0cfffffc0c0c0c0c0cf00fc0c0c0c0c0c0cfffc0c0c0c0c0c0cf00fc0c0c0c0c0c0cfc0c0c0c0c0c0cf0000fc0c0c0c0c0c0c0c0c0c0c0c0cf000000fc0c0c0c0c0c0c0c0c0c0c0cf00000000fc0c0c0fffffffff0c0c0cf0000000000fc0c0fcccccccccf0c0cf000000000000fc0cfceeeeeeecfc0cf00000000000000fc0fce0d0d0ccf0cf0000000000000000fcfced0d0d0cfcf000000000000000000ffce0d0d0ccff00000000000000000000fcdc0c0c0cf000000000000000000000fcccccccccf000000000000000000000fc8cccccccf000000000000000000000fc3ccffffcf000000000000000000000fcccccccccf0000000000000000000000fffffffff00000000000000000000000fffffffff000000000000")

controlla(ClassicDecompress.isCompressed(compressa), "la risorsa campione si riconosce come compressa")
let fuori = ClassicDecompress.decompress(compressa)
controlla(fuori == attesa, "dcmp 0: l'icl4 dell'Installer deve uscire identica a resource_dasm (\(fuori?.count ?? -1) byte, attesi \(attesa.count))")
controlla(fuori?.count == 512, "una icl4 decompressa pesa 512 byte")

// Flussi fatti a mano. Intestazione versione 8: firma, lunghezza 18, versione 8, attributi 1, dimensione, 6 byte.
func risorsa(dcmp: UInt8, size: Int, _ corpo: [UInt8]) -> Data {
    var h: [UInt8] = [0xA8, 0x9F, 0x65, 0x72, 0, 18, 8, 1,
                      UInt8(size >> 24 & 255), UInt8(size >> 16 & 255), UInt8(size >> 8 & 255), UInt8(size & 255),
                      0, 0, 0, dcmp, 0, 0]
    h += corpo
    return Data(h)
}
// dcmp 0: 0x02 = 2 parole letterali, 0x4B = parola costante 0x0000, 0xFF = fine.
controlla(ClassicDecompress.decompress(risorsa(dcmp: 0, size: 6, [0x02, 1, 2, 3, 4, 0x4B, 0xFF])) == Data([1, 2, 3, 4, 0, 0]),
          "dcmp 0: parole letterali e parola costante")
// dcmp 0: la stringa memorizzata si riusa (0x11 = 1 parola memorizzata, 0x23 = la riscrive).
controlla(ClassicDecompress.decompress(risorsa(dcmp: 0, size: 4, [0x11, 9, 8, 0x23, 0xFF])) == Data([9, 8, 9, 8]),
          "dcmp 0: stringa memorizzata riusata")
// dcmp 1: 0x03 = 4 byte letterali, 0x20 non esiste ancora in memoria -> guasto; 0xFF = fine.
controlla(ClassicDecompress.decompress(risorsa(dcmp: 1, size: 4, [0x03, 5, 6, 7, 8, 0xFF])) == Data([5, 6, 7, 8]),
          "dcmp 1: byte letterali")
// Flussi rotti o non gestiti non devono né bloccarsi né inventare dati.
controlla(ClassicDecompress.decompress(risorsa(dcmp: 0, size: 4, [0x23, 0xFF])) == nil, "memo inesistente: nil")
controlla(ClassicDecompress.decompress(risorsa(dcmp: 0, size: 4, [0x02, 1, 2])) == nil, "flusso troncato: nil")
controlla(ClassicDecompress.decompress(risorsa(dcmp: 2, size: 4, [0xFF])) == nil, "decompressore non gestito: nil")
controlla(ClassicDecompress.decompress(Data([1, 2, 3])) == nil, "dati non compressi: nil")

if guasti.isEmpty { print("ok"); exit(0) }
for g in guasti { print("✗ \(g)") }
exit(1)
