import Foundation

/// Le risorse compresse del Resource Manager (System 7 e seguenti).
///
/// Un programma poteva comprimere le sue risorse — icone comprese — e il
/// Resource Manager le decomprimeva da sé alla lettura. Chi legge il fork a
/// mano deve farlo da sé: senza, una `icl8` da 441 byte invece di 1024 viene
/// presa per pixel veri e l'icona esce bianca.
///
/// Intestazione, versione 8:
///
///     0   4  firma A89F6572
///     4   2  lunghezza dell'intestazione (18)
///     6   1  versione (8)
///     7   1  attributi
///     8   4  dimensione dopo la decompressione
///     12  1  working buffer, 13 1 expansion buffer
///     14  2  numero del decompressore (`dcmp`)
///     16  2  riservato
///
/// I decompressori 0 e 1 di sistema sono implementati qui. L'algoritmo e le
/// due tabelle di parole costanti vengono da `resource_dasm` di Martin
/// Michelsen (licenza MIT, github.com/fuzziqersoftware/resource_dasm).
/// Altri decompressori (2, 3, intestazione versione 9, `dcmp` personalizzati)
/// non sono gestiti: la risorsa resta senza dati e chi la cerca non la trova.
enum ClassicDecompress {

    static func isCompressed(_ data: Data) -> Bool {
        data.count >= 18 && data.prefix(4).elementsEqual([0xA8, 0x9F, 0x65, 0x72])
    }

    /// I dati decompressi, oppure `nil` se il formato non è tra quelli noti o
    /// il flusso è danneggiato.
    static func decompress(_ data: Data) -> Data? {
        guard isCompressed(data) else { return nil }
        let b = [UInt8](data)
        let headerLength = Int(b[4]) << 8 | Int(b[5])
        let version = b[6]
        guard version == 8, headerLength >= 18, headerLength <= b.count else { return nil }
        let size = Int(b[8]) << 24 | Int(b[9]) << 16 | Int(b[10]) << 8 | Int(b[11])
        let dcmp = Int(b[14]) << 8 | Int(b[15])
        guard dcmp == 0 || dcmp == 1, size >= 0, size <= 64 << 20 else { return nil }

        var out: [UInt8]?
        do {
            var r = Reader(bytes: b, at: headerLength)
            out = try expand(&r, isSystem1: dcmp == 1)
        } catch {
            return nil
        }
        guard var result = out else { return nil }
        // Alcuni compressori scrivono qualche byte in più alla fine.
        if result.count > size { result.removeLast(result.count - size) }
        return Data(result)
    }

    // MARK: - Lettura

    private struct Fail: Error {}

    private struct Reader {
        let bytes: [UInt8]
        var at: Int

        mutating func u8() throws -> Int {
            guard at < bytes.count else { throw Fail() }
            defer { at += 1 }
            return Int(bytes[at])
        }
        mutating func u16() throws -> Int { try u8() << 8 | u8() }
        mutating func u32() throws -> Int { try u16() << 16 | u16() }
        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, at + n <= bytes.count else { throw Fail() }
            defer { at += n }
            return Array(bytes[at..<(at + n)])
        }

        /// Il numero a lunghezza variabile del formato.
        mutating func encodedInt() throws -> Int {
            var v = try u8()
            if v & 0x80 == 0 { return v }
            if v == 0xFF { return try u32() }
            v = ((v - 0xC0) << 8) | (try u8())
            return v & 0x4000 != 0 ? v | ~0x7FFF : v
        }
    }

    private static func put16(_ out: inout [UInt8], _ v: Int) {
        out.append(UInt8(truncatingIfNeeded: v >> 8))
        out.append(UInt8(truncatingIfNeeded: v))
    }

    // MARK: - Decompressione

    private static func expand(_ r: inout Reader, isSystem1: Bool) throws -> [UInt8] {
        var out: [UInt8] = []
        var memo: [[UInt8]] = []

        func memoString(_ slot: Int) throws -> [UInt8] {
            guard slot >= 0, slot < memo.count else { throw Fail() }
            return memo[slot]
        }

        while true {
            let c = try r.u8()
            if isSystem1 {
                switch c {
                case 0..<0x10:    out += try r.take(c + 1)
                case 0x10..<0x20: let s = try r.take(c - 0x0F); memo.append(s); out += s
                case 0x20..<0xD0: out += try memoString(c - 0x20)
                case 0xD0:        out += try r.take(try r.encodedInt())
                case 0xD1:        let s = try r.take(try r.encodedInt()); memo.append(s); out += s
                case 0xD2:        out += try memoString(try r.u8() + 0xB0)
                case 0xD3:        out += try memoString(try r.u8() + 0x1B0)
                case 0xD4:        out += try memoString(try r.u16() + 0xB0)
                case 0xD5..<0xFE:
                    let i = c - 0xD5
                    guard i < constTable1.count else { throw Fail() }
                    put16(&out, Int(constTable1[i]))
                case 0xFE:        try extensionCommand(&r, &out)
                default:          return out                      // 0xFF
                }
            } else {
                switch c {
                case 0:           out += try r.take(try r.encodedInt() * 2)
                case 1..<0x10:    out += try r.take(c * 2)
                case 0x10:        let s = try r.take(try r.encodedInt() * 2); memo.append(s); out += s
                case 0x11..<0x20: let s = try r.take((c - 0x10) * 2); memo.append(s); out += s
                case 0x20:        out += try memoString(try r.u8() + 0x28)
                case 0x21:        out += try memoString(try r.u8() + 0x128)
                case 0x22:        out += try memoString(try r.u16() + 0x28)
                case 0x23..<0x4B: out += try memoString(c - 0x23)
                case 0x4B..<0xFE:
                    let i = c - 0x4B
                    guard i < constTable0.count else { throw Fail() }
                    put16(&out, Int(constTable0[i]))
                case 0xFE:        try extensionCommand(&r, &out)
                default:          return out                      // 0xFF
                }
            }
            guard out.count <= 64 << 20 else { throw Fail() }
        }
    }

    private static func extensionCommand(_ r: inout Reader, _ out: inout [UInt8]) throws {
        switch try r.u8() {
        case 0:   // tabella di esportazione
            var index = 6
            let segment = try r.encodedInt()
            let count = try r.encodedInt() & 0xFFFF
            for _ in 0..<count {
                index = (index + (try r.encodedInt() - 6)) & 0xFFFF
                put16(&out, 0x3F3C); put16(&out, segment); put16(&out, 0xA9F0); put16(&out, index)
            }
            put16(&out, 0x3F3C); put16(&out, segment); put16(&out, 0xA9F0)

        case 1:   // tabella dei salti
            var target = try r.encodedInt() & 0xFFFF
            let delta = try r.encodedInt() & 0xFFFF
            let count = (try r.encodedInt() & 0xFFFF) + 1
            var a5 = try r.encodedInt() & 0xFFFF
            for x in 0..<count {
                if x > 0 {
                    target = (target - 8) & 0xFFFF
                    a5 = delta == 0 ? try r.encodedInt() & 0xFFFF : (a5 + delta) & 0xFFFF
                }
                put16(&out, 0x6100); put16(&out, target); put16(&out, 0x4EED); put16(&out, a5)
            }

        case 2:   // byte ripetuto
            let v = UInt8(truncatingIfNeeded: try r.encodedInt())
            let count = (try r.encodedInt() & 0xFFFF) + 1
            out += [UInt8](repeating: v, count: count)

        case 3:   // parola ripetuta
            let v = try r.encodedInt()
            let count = (try r.encodedInt() & 0xFFFF) + 1
            for _ in 0..<count { put16(&out, v) }

        case 4:   // parole, differenze a 8 bit
            var v = try r.encodedInt() & 0xFFFF
            let count = (try r.encodedInt() & 0xFFFF) + 1
            for x in 0..<count {
                if x > 0 {
                    var d = try r.u8()
                    if d & 0x80 != 0 { d |= 0xFF00 }
                    v = (v + d) & 0xFFFF
                }
                put16(&out, v)
            }

        case 5:   // parole, differenze a lunghezza variabile
            var v = try r.encodedInt() & 0xFFFF
            let count = (try r.encodedInt() & 0xFFFF) + 1
            for x in 0..<count {
                if x > 0 { v = (v + (try r.encodedInt())) & 0xFFFF }
                put16(&out, v)
            }

        case 6:   // long, differenze a lunghezza variabile
            var v = try r.encodedInt() & 0xFFFF_FFFF
            let count = (try r.encodedInt() & 0xFFFF) + 1
            for x in 0..<count {
                if x > 0 { v = (v + (try r.encodedInt())) & 0xFFFF_FFFF }
                put16(&out, v >> 16); put16(&out, v & 0xFFFF)
            }

        default:
            break
        }
    }

    // MARK: - Tabelle

    private static let constTable0: [UInt16] = [
        0x0000, 0x4EBA, 0x0008, 0x4E75, 0x000C,
        0x4EAD, 0x2053, 0x2F0B, 0x6100, 0x0010, 0x7000, 0x2F00, 0x486E,
        0x2050, 0x206E, 0x2F2E, 0xFFFC, 0x48E7, 0x3F3C, 0x0004, 0xFFF8,
        0x2F0C, 0x2006, 0x4EED, 0x4E56, 0x2068, 0x4E5E, 0x0001, 0x588F,
        0x4FEF, 0x0002, 0x0018, 0x6000, 0xFFFF, 0x508F, 0x4E90, 0x0006,
        0x266E, 0x0014, 0xFFF4, 0x4CEE, 0x000A, 0x000E, 0x41EE, 0x4CDF,
        0x48C0, 0xFFF0, 0x2D40, 0x0012, 0x302E, 0x7001, 0x2F28, 0x2054,
        0x6700, 0x0020, 0x001C, 0x205F, 0x1800, 0x266F, 0x4878, 0x0016,
        0x41FA, 0x303C, 0x2840, 0x7200, 0x286E, 0x200C, 0x6600, 0x206B,
        0x2F07, 0x558F, 0x0028, 0xFFFE, 0xFFEC, 0x22D8, 0x200B, 0x000F,
        0x598F, 0x2F3C, 0xFF00, 0x0118, 0x81E1, 0x4A00, 0x4EB0, 0xFFE8,
        0x48C7, 0x0003, 0x0022, 0x0007, 0x001A, 0x6706, 0x6708, 0x4EF9,
        0x0024, 0x2078, 0x0800, 0x6604, 0x002A, 0x4ED0, 0x3028, 0x265F,
        0x6704, 0x0030, 0x43EE, 0x3F00, 0x201F, 0x001E, 0xFFF6, 0x202E,
        0x42A7, 0x2007, 0xFFFA, 0x6002, 0x3D40, 0x0C40, 0x6606, 0x0026,
        0x2D48, 0x2F01, 0x70FF, 0x6004, 0x1880, 0x4A40, 0x0040, 0x002C,
        0x2F08, 0x0011, 0xFFE4, 0x2140, 0x2640, 0xFFF2, 0x426E, 0x4EB9,
        0x3D7C, 0x0038, 0x000D, 0x6006, 0x422E, 0x203C, 0x670C, 0x2D68,
        0x6608, 0x4A2E, 0x4AAE, 0x002E, 0x4840, 0x225F, 0x2200, 0x670A,
        0x3007, 0x4267, 0x0032, 0x2028, 0x0009, 0x487A, 0x0200, 0x2F2B,
        0x0005, 0x226E, 0x6602, 0xE580, 0x670E, 0x660A, 0x0050, 0x3E00,
        0x660C, 0x2E00, 0xFFEE, 0x206D, 0x2040, 0xFFE0, 0x5340, 0x6008,
        0x0480, 0x0068, 0x0B7C, 0x4400, 0x41E8, 0x4841]

    private static let constTable1: [UInt16] = [
        0x0000, 0x0001, 0x0002,
        0x0003, 0x2E01, 0x3E01, 0x0101, 0x1E01, 0xFFFF, 0x0E01, 0x3100,
        0x1112, 0x0107, 0x3332, 0x1239, 0xED10, 0x0127, 0x2322, 0x0137,
        0x0706, 0x0117, 0x0123, 0x00FF, 0x002F, 0x070E, 0xFD3C, 0x0135,
        0x0115, 0x0102, 0x0007, 0x003E, 0x05D5, 0x0201, 0x0607, 0x0708,
        0x3001, 0x0133, 0x0010, 0x1716, 0x373E, 0x3637]
}
