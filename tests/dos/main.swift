import AppKit

// Prove: (1) un'immagine disegnata al volo (misura 0x0 in pixel) non fa lanciare l'arrotondamento degli angoli;
// (2) un quadrato opaco si arrotonda, un'icona con angoli trasparenti resta com'è; (3) si riconoscono i programmi DOS.
var guasti: [String] = []
func controlla(_ ok: Bool, _ msg: String) { if !ok { guasti.append(msg) } }

let alVolo = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
controlla(alVolo.roundedIfSquare() === alVolo, "un'immagine disegnata al volo deve tornare com'è")
controlla(alVolo.withRoundCorners() === alVolo, "withRoundCorners su misura nulla deve tornare l'immagine")

func bitmap(_ side: Int, alphaCorners: Bool) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set(); NSRect(x: 0, y: 0, width: side, height: side).fill(using: .copy)
    NSColor.blue.setFill()
    (alphaCorners ? NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: side, height: side)) : NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side))).fill()
    NSGraphicsContext.restoreGraphicsState()
    let img = NSImage(size: NSSize(width: side, height: side)); img.addRepresentation(rep); return img
}
let quadrato = bitmap(64, alphaCorners: false)
let tondo = bitmap(64, alphaCorners: true)
controlla(tondo.roundedIfSquare() === tondo, "un'icona con angoli trasparenti non va ritagliata")
controlla(quadrato.roundedIfSquare() !== quadrato, "un quadrato opaco va arrotondato")

func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 255), UInt8(v >> 8 & 255), UInt8(v >> 16 & 255), UInt8(v >> 24)] }
var dos = [UInt8](repeating: 0, count: 256); dos[0] = 0x4D; dos[1] = 0x5A
controlla(WindowsIcon.isDOSProgram(Data(dos)), "MZ senza puntatore a un PE è un programma DOS")
var pointsFar = dos; pointsFar.replaceSubrange(0x3C..<0x40, with: le32(225_641_835))
controlla(WindowsIcon.isDOSProgram(Data(pointsFar)), "MZ con puntatore fuori dal file è DOS (come DCONVERT.EXE)")
var pe = dos; pe.replaceSubrange(0x3C..<0x40, with: le32(0x80)); pe.replaceSubrange(0x80..<0x84, with: [0x50, 0x45, 0, 0])
controlla(!WindowsIcon.isDOSProgram(Data(pe)), "MZ con firma PE non è DOS")
controlla(!WindowsIcon.isDOSProgram(Data([0x7F, 0x45, 0x4C, 0x46] + [UInt8](repeating: 0, count: 64))), "un file senza MZ non è DOS")

if guasti.isEmpty { print("ok") } else { guasti.forEach { print("✗", $0) }; exit(1) }
