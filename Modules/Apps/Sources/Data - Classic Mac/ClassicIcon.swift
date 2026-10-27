import Foundation
import AppKit

/// L'icona vera di un file Macintosh classico, presa dal suo fork di risorse.
///
/// Sui dischi HFS e MFS l'icona di un'applicazione non è un file a parte: è una
/// risorsa dentro l'applicazione stessa, e per trovarla si segue una catena che
/// il Finder percorreva dal 1984.
///
///     BNDL ──▶ elenca, per tipo, le coppie (id locale → id risorsa)
///       │
///       ├─ FREF ─▶ una per tipo di documento gestito. Quella con fileType
///       │          'APPL' è l'applicazione stessa, e dice quale id *locale*
///       │          ha la sua icona.
///       │
///       └─ ICN# ─▶ l'id locale, ritradotto qui, dà l'id della risorsa vera.
///
/// Il doppio passaggio per gli id locali sembra un giro inutile e invece è il
/// punto: gli id locali sono privati del bundle, così due applicazioni potevano
/// numerare le proprie icone allo stesso modo senza pestarsi i piedi quando il
/// Finder le copiava entrambe nel Desktop file del disco.
///
/// Trovato l'id, l'icona è una *famiglia* di risorse con lo stesso id e tipi
/// diversi — bianco e nero, 16 e 256 colori, grande e piccola. Si impacchettano
/// tali e quali in un `.icns`: il formato contiene ancora quei tipi, e macOS li
/// disegna senza bisogno di convertire niente.
enum ClassicIcon {

    // MARK: - Il fork di risorse

    /// Le risorse di un fork, per tipo e per id.
    ///
    /// Il parser è volutamente diffidente: questi fork arrivano da floppy di
    /// quarant'anni, spesso con settori illeggibili, e un offset sballato non
    /// deve far altro che restituire `nil`.
    struct Fork {
        /// `["ICN#": [128: <dati>], …]`
        let resources: [String: [Int16: Data]]

        func data(type: String, id: Int16) -> Data? { resources[type]?[id] }
        func ids(ofType type: String) -> [Int16] { Array(resources[type]?.keys ?? [:].keys) }

        init?(_ fork: Data) {
            guard fork.count >= 16,
                  let dataOffset = fork.be32(0), let mapOffset = fork.be32(4),
                  let dataLength = fork.be32(8), let mapLength = fork.be32(12),
                  mapOffset + mapLength <= fork.count,
                  dataOffset + dataLength <= fork.count,
                  mapLength >= 30
            else { return nil }

            // Nella mappa: 16 byte di copia dell'intestazione, 4 di handle, 2 di
            // riferimento al file, 2 di attributi, poi i due offset che servono.
            guard let typeListOffset = fork.be16(mapOffset + 24) else { return nil }
            let typeList = mapOffset + typeListOffset
            guard typeList + 2 <= fork.count, let rawCount = fork.be16(typeList) else { return nil }

            var found: [String: [Int16: Data]] = [:]
            let typeCount = rawCount + 1          // il campo conta a partire da zero

            for index in 0..<typeCount {
                let entry = typeList + 2 + index * 8
                guard entry + 8 <= fork.count,
                      let type = fork.ostype(entry),
                      let rawRefs = fork.be16(entry + 4),
                      let refOffset = fork.be16(entry + 6)
                else { break }

                var byID: [Int16: Data] = [:]
                for ref in 0..<(rawRefs + 1) {
                    let r = typeList + refOffset + ref * 12
                    guard r + 12 <= fork.count,
                          let id = fork.be16(r),
                          let packed = fork.be32(r + 4)
                    else { break }

                    // Byte alto: attributi. I tre bassi: offset nei dati.
                    let at = dataOffset + (packed & 0x00FF_FFFF)
                    guard at + 4 <= fork.count, let length = fork.be32(at),
                          at + 4 + length <= fork.count
                    else { continue }

                    byID[Int16(bitPattern: UInt16(id))] = fork.slice(at + 4, length)
                }
                if !byID.isEmpty { found[type] = byID }
            }

            guard !found.isEmpty else { return nil }
            self.resources = found
        }
    }

    // MARK: - Dal fork all'icona

    /// I tipi che compongono una famiglia di icone classica, dal più ricco al
    /// più povero. Ci sono tutti perché un `.icns` può contenerli tutti, e più
    /// ce ne sono meglio l'icona regge agli ingrandimenti.
    static let familyTypes = ["ich#", "ich4", "ich8",   // 48×48
                              "ICN#", "icl4", "icl8",   // 32×32
                              "ics#", "ics4", "ics8"]   // 16×16

    /// L'icona di un'applicazione, se il suo fork la contiene.
    static func forApplication(fork: Fork) -> Data? {
        guard let iconID = applicationIconID(in: fork) else { return nil }
        return icns(from: fork, id: iconID)
    }

    /// L'icona personalizzata che un file si porta addosso.
    ///
    /// Sui file classici sta come famiglia con id −16455, lo stesso numero che
    /// macOS usa ancora oggi per le icone personalizzate. Vale per qualunque
    /// file, non solo per le applicazioni, ed è la strada più corta: se c'è,
    /// non serve consultare né il BNDL né il Desktop file.
    static func custom(fork: Fork) -> Data? {
        // Un'icona personalizzata può stare in due forme: la famiglia classica
        // (ICN#, icl8, …) con quell'id, oppure un'unica risorsa 'icns' già
        // impacchettata, che è come la scrivono macOS e noi. Cercarne una sola
        // vuol dire non vedere l'altra — e chi non la vede aggiunge una seconda
        // icona a un file che ce l'ha già.
        if let ready = fork.data(type: "icns", id: -16455), !ready.isEmpty {
            return ready
        }
        return icns(from: fork, id: -16455)
    }

    /// Il file ha già un'icona personalizzata, in una qualunque delle due forme?
    static func hasCustomIcon(fork: Fork) -> Bool {
        custom(fork: fork) != nil
    }

    /// L'id della risorsa icona dell'applicazione, seguendo BNDL e FREF.
    static func applicationIconID(in fork: Fork) -> Int16? {
        // Il BNDL è convenzionalmente 128, ma non è obbligatorio: si prende
        // quello che c'è, col numero più basso per determinismo.
        guard let bundleID = fork.ids(ofType: "BNDL").min(),
              let bundle = fork.data(type: "BNDL", id: bundleID),
              let maps = parseBundle(bundle),
              let frefs = maps["FREF"], let icons = maps["ICN#"]
        else { return nil }

        // Fra i FREF che il bundle dichiara, quello che descrive l'applicazione
        // stessa: fileType 'APPL'.
        for (_, frefResourceID) in frefs.sorted(by: { $0.key < $1.key }) {
            guard let fref = fork.data(type: "FREF", id: frefResourceID),
                  fref.count >= 6,
                  let type = fref.ostype(0), type == "APPL",
                  let localIcon = fref.be16(4)
            else { continue }
            if let real = icons[Int16(bitPattern: UInt16(localIcon))] { return real }
        }
        return nil
    }

    /// Il creator a quattro lettere di un file classico, dal suo FinderInfo.
    static func fileCreator(of url: URL) -> String? {
        var buffer = [UInt8](repeating: 0, count: 32)
        guard getxattr(url.path, "com.apple.FinderInfo", &buffer, 32, 0, 0) >= 8 else { return nil }
        return String(bytes: buffer[4..<8], encoding: .macOSRoman)
    }

    /// L'icona di un *documento*, cercata nel `Desktop` del volume.
    ///
    /// Un documento un'icona propria non ce l'ha: ha un creator e un tipo,
    /// quattro lettere ciascuno, e il Finder li risolveva contro un database che
    /// teneva su ogni disco — copiandoci dentro BNDL, FREF e icone di ogni
    /// applicazione incontrata. È per questo che un disco che non ha mai visto
    /// un'applicazione mostra i suoi documenti vuoti, allora come adesso.
    ///
    /// La passeggiata è la stessa delle applicazioni con due differenze: il
    /// BNDL si trova confrontandone il **creator** invece di prendere il primo,
    /// e la FREF cercata è quella col **tipo del documento** invece di `APPL`.
    static func forDocument(desktop: Fork, creator: String, type: String) -> Data? {
        for bundleID in desktop.ids(ofType: "BNDL").sorted() {
            guard let bundle = desktop.data(type: "BNDL", id: bundleID),
                  bundle.count >= 8,
                  // Il creator sono i primi quattro byte: è quello che fa di un
                  // Desktop un database invece che un mucchio.
                  bundle.ostype(0) == creator,
                  let maps = parseBundle(bundle),
                  let frefs = maps["FREF"], let icons = maps["ICN#"]
            else { continue }

            for (_, frefID) in frefs.sorted(by: { $0.key < $1.key }) {
                guard let fref = desktop.data(type: "FREF", id: frefID),
                      fref.count >= 6,
                      fref.ostype(0) == type,
                      let local = fref.be16(4),
                      let real = icons[Int16(bitPattern: UInt16(local))]
                else { continue }
                if let icon = icns(from: desktop, id: real) { return icon }
            }
        }
        return nil
    }

    /// Il `Desktop` di un volume montato, già parsificato, se c'è.
    ///
    /// Si legge una volta per volume: parsificare un database condiviso per ogni
    /// file sarebbe assurdo.
    static func desktopDatabase(ofVolume volume: URL) -> Fork? {
        let desktop = volume.appendingPathComponent("Desktop")
        guard let raw = resourceFork(of: desktop) else { return nil }
        return Fork(raw)
    }

    /// Il BNDL: `["FREF": [id locale: id risorsa], "ICN#": […]]`.
    private static func parseBundle(_ bundle: Data) -> [String: [Int16: Int16]]? {
        // creator(4) + version(2) + numero di tipi − 1 (2)
        guard bundle.count >= 8, let rawTypes = bundle.be16(6) else { return nil }

        var maps: [String: [Int16: Int16]] = [:]
        var cursor = 8
        for _ in 0..<(rawTypes + 1) {
            guard cursor + 6 <= bundle.count,
                  let type = bundle.ostype(cursor),
                  let rawCount = bundle.be16(cursor + 4)
            else { break }
            cursor += 6

            var pairs: [Int16: Int16] = [:]
            for _ in 0..<(rawCount + 1) {
                guard cursor + 4 <= bundle.count,
                      let local = bundle.be16(cursor), let real = bundle.be16(cursor + 2)
                else { break }
                pairs[Int16(bitPattern: UInt16(local))] = Int16(bitPattern: UInt16(real))
                cursor += 4
            }
            maps[type] = pairs
        }
        return maps.isEmpty ? nil : maps
    }

    // MARK: - Impacchettare

    /// Mette la famiglia di icone con quell'id dentro un `.icns`.
    ///
    /// Nessuna conversione: i byte delle risorse entrano tali e quali, perché il
    /// formato `.icns` contiene ancora i tipi classici e macOS li sa disegnare —
    /// `ICN#` in bianco e nero con la sua maschera, `icl8` e `ics8` indicizzati
    /// sulla tavolozza di sistema del 1984.
    static func icns(from fork: Fork, id: Int16) -> Data? {
        // Le risorse classiche finiscono nell'`.icns` **ridisegnate**, non
        // copiate. Copiarle sarebbe più fedele e non funziona, per due motivi
        // che si sommano.
        //
        // I colori: decodificate, `icl4` e `icl8` diventano entrambe RGBA a 32
        // bit e nulla le distingue più, così chi disegna ne sceglie una a caso
        // — e quando esce quella a sedici colori l'icona è sbagliata. L'omino
        // di Norton veniva blu.
        //
        // La trasparenza: la maschera vive solo nel membro `#`, e macOS **non
        // la applica** alla variante a colori. Verificato disegnando le due
        // separatamente su un fondo rosso: la maschera da sola ritaglia
        // correttamente, `icl8` da sola esce su un quadrato bianco opaco. Nel
        // 1984 le due cose le teneva insieme il Finder; oggi non le tiene
        // insieme nessuno.
        //
        // Quindi si prende il colore dalla variante più ricca, l'alpha dalla
        // maschera, e si riconfeziona in PNG — che il contenitore moderno
        // accetta, e che porta l'alpha con sé senza dipendere da niente.
        // Le misure vanno nella coppia che il formato ha ricevuto dopo: 24 bit
        // compressi RLE piu' una maschera a 8 bit separata. Non in PNG.
        //
        // La differenza si vede solo passando dal servizio icone del Finder, ed
        // e' totale. `ic04`/`ic05` il formato li definisce come ARGB grezzo:
        // mettendoci un PNG, macOS ne legge i byte come pixel e disegna rumore
        // colorato. `icp4`/`icp5` un PNG lo accettano — `NSImage` li apre
        // correttamente — ma il servizio icone, quello che disegna le icone nel
        // Finder, no: stesso rumore. Misurato con lo stesso file nelle tre
        // forme, reso a 16, 32 e 64 pixel.
        //
        // Con `is32`/`il32` e le loro maschere invece va, ed e' anche la forma
        // che il driver produce: una sola cosa da conoscere invece di due.
        let gruppi = [(lato: 48, maschera: "ich#", colori: ["ich8", "ich4"],
                       fuoriRGB: "ih32", fuoriMaschera: "h8mk"),
                      (lato: 32, maschera: "ICN#", colori: ["icl8", "icl4"],
                       fuoriRGB: "il32", fuoriMaschera: "l8mk"),
                      (lato: 16, maschera: "ics#", colori: ["ics8", "ics4"],
                       fuoriRGB: "is32", fuoriMaschera: "s8mk")]

        var pezzi: [(tipo: String, dati: Data)] = []

        for gruppo in gruppi {
            guard let ricca = gruppo.colori.first(where: { fork.data(type: $0, id: id) != nil }),
                  let composto = componi(fork: fork, id: id,
                                         colori: ricca, maschera: gruppo.maschera,
                                         lato: gruppo.lato),
                  let (rgb, alpha) = piani(composto)
            else { continue }

            pezzi.append((gruppo.fuoriRGB, rle24(rgb)))
            pezzi.append((gruppo.fuoriMaschera, alpha))
        }
        guard !pezzi.isEmpty else { return nil }

        var body = Data()
        for pezzo in pezzi {
            body.append(contentsOf: Array(pezzo.tipo.utf8))
            body.appendBE32(UInt32(pezzo.dati.count + 8))
            body.append(pezzo.dati)
        }
        var file = Data("icns".utf8)
        file.appendBE32(UInt32(body.count + 8))
        file.append(body)
        return file
    }

    /// I tre canali separati e la maschera, come li vuole il formato.
    ///
    /// Nei tipi a 24 bit i canali non sono intrecciati: prima tutto il rosso,
    /// poi tutto il verde, poi tutto il blu. La maschera e' un piano a parte, un
    /// byte per pixel.
    private static func piani(_ rep: NSBitmapImageRep) -> (rgb: [UInt8], alpha: Data)? {
        let lato = rep.pixelsWide
        guard rep.pixelsHigh == lato else { return nil }

        var rgb = [UInt8](repeating: 0, count: lato * lato * 3)
        var alpha = [UInt8](repeating: 0, count: lato * lato)
        let pixel = lato * lato

        for y in 0..<lato {
            for x in 0..<lato {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let i = y * lato + x
                rgb[i]              = UInt8((c.redComponent   * 255).rounded())
                rgb[pixel + i]      = UInt8((c.greenComponent * 255).rounded())
                rgb[pixel * 2 + i]  = UInt8((c.blueComponent  * 255).rounded())
                alpha[i]            = UInt8((c.alphaComponent * 255).rounded())
            }
        }
        return (rgb, Data(alpha))
    }

    /// La compressione che i tipi a 24 bit dell'`.icns` si aspettano.
    ///
    /// Un byte guida sotto 0x80 vuol dire «i prossimi (guida + 1) byte sono
    /// letterali»; uno pari o sopra vuol dire «ripeti il byte che segue
    /// (guida - 125) volte». Quindi una ripetizione conviene da tre byte in su,
    /// e le due forme si fermano a 128 e 130.
    ///
    /// I canali si comprimono uno per volta, non tutti insieme: le ripetizioni
    /// stanno dentro un canale, e a cavallo di due si perderebbero.
    private static func rle24(_ piani: [UInt8]) -> Data {
        var fuori = Data()
        let perCanale = piani.count / 3

        for canale in 0..<3 {
            let inizio = canale * perCanale
            var i = 0
            while i < perCanale {
                var ripetizioni = 1
                while ripetizioni < 130, i + ripetizioni < perCanale,
                      piani[inizio + i + ripetizioni] == piani[inizio + i] {
                    ripetizioni += 1
                }
                if ripetizioni >= 3 {
                    fuori.append(UInt8(0x80 + ripetizioni - 3))
                    fuori.append(piani[inizio + i])
                    i += ripetizioni
                    continue
                }
                // Una sequenza letterale corre finche' non spuntano tre byte
                // uguali, perche' da li' la ripetizione costa meno.
                var letterali = 0
                while letterali < 128, i + letterali < perCanale {
                    if i + letterali + 2 < perCanale,
                       piani[inizio + i + letterali] == piani[inizio + i + letterali + 1],
                       piani[inizio + i + letterali] == piani[inizio + i + letterali + 2] {
                        break
                    }
                    letterali += 1
                }
                if letterali == 0 { letterali = 1 }
                fuori.append(UInt8(letterali - 1))
                fuori.append(contentsOf: piani[(inizio + i)..<(inizio + i + letterali)])
                i += letterali
            }
        }
        return fuori
    }

    /// Colore da una variante, alpha dalla maschera, in un solo bitmap.
    ///
    /// Le due risorse si danno in pasto al sistema **insieme**, in un `.icns`
    /// con dentro solo loro: la variante a colori da sola non si decodifica
    /// nemmeno — è indicizzata e senza maschera non è un'icona completa —
    /// mentre in coppia il sistema le apre entrambe, e si occupa lui della
    /// tavolozza di sistema del 1984 e dei bit impacchettati.
    ///
    /// Quello che restituisce però non è ancora utilizzabile: la maschera porta
    /// l'alpha giusto ma è in bianco e nero, e la variante a colori ha i colori
    /// giusti su un quadrato opaco. Da qui il rimescolamento, colore dall'una e
    /// alpha dall'altra.
    private static func componi(fork: Fork, id: Int16, colori: String, maschera: String,
                                lato: Int) -> NSBitmapImageRep? {
        guard let bytesMaschera = fork.data(type: maschera, id: id), !bytesMaschera.isEmpty,
              let bytesColori = fork.data(type: colori, id: id), !bytesColori.isEmpty
        else { return nil }

        var body = Data()
        for (tipo, risorsa) in [(maschera, bytesMaschera), (colori, bytesColori)] {
            body.append(contentsOf: Array(tipo.utf8))
            body.appendBE32(UInt32(risorsa.count + 8))
            body.append(risorsa)
        }
        var file = Data("icns".utf8)
        file.appendBE32(UInt32(body.count + 8))
        file.append(body)

        // L'ordine delle rappresentazioni segue quello del file, e nel file la
        // maschera l'abbiamo messa per prima.
        guard let image = NSImage(data: file) else { return nil }
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
                        .filter { $0.pixelsWide == lato && $0.pixelsHigh == lato }
        guard reps.count == 2, let colore = appiattisci(reps[1], lato: lato) else { return nil }
        let ritaglio = reps[0]

        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lato, pixelsHigh: lato,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: lato * 4, bitsPerPixel: 32)
        else { return nil }

        for y in 0..<lato {
            for x in 0..<lato {
                guard let pixel = colore.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let alpha = ritaglio.colorAt(x: x, y: y)?.alphaComponent ?? 1
                out.setColor(NSColor(deviceRed: pixel.redComponent, green: pixel.greenComponent,
                                     blue: pixel.blueComponent, alpha: alpha), atX: x, y: y)
            }
        }
        return out
    }

    /// La variante a colori ridisegnata su fondo opaco, per poterne leggere i
    /// pixel.
    ///
    /// Letti direttamente, i suoi byte sono tutti zero: il sistema tiene il
    /// risultato della decodifica altrove e lo materializza solo quando lo si
    /// disegna. Quindi lo si disegna, e si legge il risultato.
    private static func appiattisci(_ rep: NSBitmapImageRep, lato: Int) -> NSBitmapImageRep? {
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lato, pixelsHigh: lato,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: lato * 4, bitsPerPixel: 32)
        else { return nil }

        let contesto = NSGraphicsContext(bitmapImageRep: out)
        let precedente = NSGraphicsContext.current
        NSGraphicsContext.current = contesto
        contesto?.imageInterpolation = .none
        let tutto = CGRect(x: 0, y: 0, width: lato, height: lato)
        NSColor.white.setFill()
        NSBezierPath(rect: tutto).fill()
        rep.draw(in: tutto, from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        NSGraphicsContext.current = precedente
        return out
    }

    /// Ingrandimento a quadretti netti, al multiplo intero che ci sta.
    private static func ingrandisci(_ rep: NSBitmapImageRep, a lato: Int) -> NSBitmapImageRep? {
        let fattore = max(1, lato / max(rep.pixelsWide, 1))
        let misura = rep.pixelsWide * fattore
        guard misura > rep.pixelsWide,
              let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: misura, pixelsHigh: misura,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: misura * 4, bitsPerPixel: 32)
        else { return nil }

        let contesto = NSGraphicsContext(bitmapImageRep: out)
        let precedente = NSGraphicsContext.current
        NSGraphicsContext.current = contesto
        contesto?.imageInterpolation = .none
        rep.draw(in: CGRect(x: 0, y: 0, width: misura, height: misura),
                 from: .zero, operation: .copy, fraction: 1,
                 respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        NSGraphicsContext.current = precedente
        return out
    }

    // MARK: - Comodità

    /// Un'applicazione classica, dal suo type.
    ///
    /// Il confronto è con `APPL` e basta, e il "e basta" è una decisione presa
    /// dopo averne provata un'altra e averla scartata.
    ///
    /// Il fatto scomodo è che per un file che dichiara `APPL` il Finder non
    /// chiede la miniatura a nessuno: disegna il divieto degli eseguibili che
    /// non sa lanciare e chiude il discorso. Verificato provando tutto il
    /// resto — dirottare l'UTI (vince quello di Apple), togliere i bit di
    /// esecuzione, firmare con un Team ID vero, accendere «Mostra anteprima
    /// icona»: il divieto resta. Il vincolo preciso è la conformità a
    /// `com.apple.application`, non a `public.executable`: un `.exe` conforma
    /// al secondo e non al primo, e la sua miniatura si vede benissimo.
    ///
    /// Da lì l'idea di dare a quei file un type privato, che li toglieva dalla
    /// categoria e faceva comparire l'icona. Funzionava, e va comunque
    /// scartata: il type è del file, non della sua visualizzazione, e un
    /// programma del 1992 con il type cambiato su un Mac OS 9 non si avvia più.
    /// Vale anche per i volumi montati, perché quel type finirebbe in ogni
    /// copia fatta dal Finder.
    ///
    /// La strada giusta era già lì: accendere `kHasCustomIcon` e mettere
    /// l'icona nel fork. Il Finder l'icona personalizzata la disegna anche a un
    /// `APPL`, a piena misura e senza cornice, e del type non gliene importa —
    /// e il driver tutto questo lo sintetizza senza scrivere un byte sul disco.
    static func isApplication(_ type: String?) -> Bool {
        type == "APPL"
    }

    /// Il type a quattro lettere di un file classico, dal suo FinderInfo.
    ///
    /// Il driver lo sintetizza dal record di catalogo del volume e lo espone
    /// come xattr, quindi si legge come un attributo qualunque — e la sandbox
    /// di un'estensione lo concede, perché è un attributo del file stesso.
    static func fileType(of url: URL) -> String? {
        var buffer = [UInt8](repeating: 0, count: 32)
        guard getxattr(url.path, "com.apple.FinderInfo", &buffer, 32, 0, 0) >= 8 else { return nil }
        return String(bytes: buffer[0..<4], encoding: .macOSRoman)
    }

    /// L'icona per un file su disco, provando le strade in ordine di costo.
    ///
    /// L'icona personalizzata vale per qualunque file. Quella via BNDL invece
    /// **solo per le applicazioni vere**, e il controllo sul type non è una
    /// formalità: il `Desktop` di ogni disco è pieno di BNDL — è il database
    /// delle icone del volume, è il suo mestiere — e senza il controllo si
    /// finisce per dare a quel file l'icona del primo programma che ci si
    /// trova dentro. Su 25 floppy veri, era il caso di quasi tutti i falsi
    /// positivi.
    ///
    /// Non copre i documenti: la loro icona non è nel documento, sta nel
    /// `Desktop` del volume, che da dentro la sandbox di un'estensione non si
    /// legge. Per quelli la strada decisa è un xattr sintetizzato dal driver.
    static func forFile(at url: URL) -> Data? {
        guard let fork = resourceFork(of: url), let parsed = Fork(fork) else { return nil }
        if let custom = custom(fork: parsed) { return custom }
        guard isApplication(fileType(of: url)) else { return nil }
        return forApplication(fork: parsed)
    }

    /// Il fork di risorse di un file, letto dal percorso che il kernel espone.
    static func resourceFork(of url: URL, limit: Int = 8 * 1024 * 1024) -> Data? {
        let path = url.appendingPathComponent("..namedfork/rsrc")
        guard let handle = try? FileHandle(forReadingFrom: path) else { return nil }
        defer { try? handle.close() }
        // Un tetto c'è per non farsi sorprendere da un fork enorme o corrotto:
        // le icone stanno nei primi kilobyte, il resto è codice e dialoghi.
        // `readData(ofLength:)` e non `read(upToCount:)`: il secondo esiste solo
        // da macOS 10.15.4, e questo progetto arriva fino a 10.15.
        return handle.readData(ofLength: limit)
    }
}

// MARK: - Letture big-endian, con i limiti controllati

private extension Data {
    func byte(_ offset: Int) -> Int? {
        guard offset >= 0, offset < count else { return nil }
        return Int(self[startIndex + offset])
    }

    func be16(_ offset: Int) -> Int? {
        guard let a = byte(offset), let b = byte(offset + 1) else { return nil }
        return a << 8 | b
    }

    func be32(_ offset: Int) -> Int? {
        guard let a = byte(offset), let b = byte(offset + 1),
              let c = byte(offset + 2), let d = byte(offset + 3) else { return nil }
        return a << 24 | b << 16 | c << 8 | d
    }

    /// Un OSType: quattro byte che sono anche quattro caratteri MacRoman.
    func ostype(_ offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return String(data: self[(startIndex + offset)..<(startIndex + offset + 4)],
                      encoding: .macOSRoman)
    }

    func slice(_ offset: Int, _ length: Int) -> Data {
        Data(self[(startIndex + offset)..<(startIndex + offset + length)])
    }

    mutating func appendBE32(_ value: UInt32) {
        append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24),
                            UInt8(truncatingIfNeeded: value >> 16),
                            UInt8(truncatingIfNeeded: value >> 8),
                            UInt8(truncatingIfNeeded: value)])
    }
}
