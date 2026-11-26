import Foundation

// Il lettore UDF legge l'elenco di un'immagine costruita al volo con `hdiutil makehybrid -udf`:
// nomi, cartelle annidate, dimensioni, e un file con nome non ASCII.
func fail(_ m: String) -> Never { print("✗ \(m)"); exit(1) }

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("qlm-udf-\(getpid())")
defer { try? FileManager.default.removeItem(at: tmp) }
let src = tmp.appendingPathComponent("src")
try FileManager.default.createDirectory(at: src.appendingPathComponent("a/b/c"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: src.appendingPathComponent("vuota"), withIntermediateDirectories: true)
let files: [String: Int] = ["radice.txt": 10, "a/uno.bin": 5000, "a/b/due.bin": 70_000, "a/b/c/tre.txt": 3, "città è.txt": 42]
for (p, n) in files { try Data(repeating: 0x41, count: n).write(to: src.appendingPathComponent(p)) }
// molti file in una cartella: la directory occupa piu' di un settore
try FileManager.default.createDirectory(at: src.appendingPathComponent("tanti"), withIntermediateDirectories: true)
var expected = files
for i in 0..<300 { let p = "tanti/file-con-un-nome-abbastanza-lungo-\(i).dat"; expected[p] = i + 1; try Data(repeating: 1, count: i + 1).write(to: src.appendingPathComponent(p)) }

let iso = tmp.appendingPathComponent("prova.iso").path
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
p.arguments = ["makehybrid", "-udf", "-iso", "-hfs-volume-name", "T", "-o", iso, src.path]
p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
try p.run(); p.waitUntilExit()
guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: iso) else { print("hdiutil non ha creato l'immagine: prova saltata"); exit(0) }

guard let r = UDFReader.list(path: iso, maxEntries: 10_000) else { fail("il volume UDF non si legge") }
let got = Dictionary(uniqueKeysWithValues: r.entries.filter { !$0.isDirectory }.map { ($0.path.precomposedStringWithCanonicalMapping, Int($0.size)) })
for (path, size) in expected {
    let key = path.precomposedStringWithCanonicalMapping
    guard let g = got[key] else { fail("manca \(path) (letti: \(got.count))") }
    if g != size { fail("\(path): dimensione \(g), attesa \(size)") }
}
if got.count != expected.count { fail("file letti \(got.count), attesi \(expected.count)") }
let dirs = Set(r.entries.filter { $0.isDirectory }.map { $0.path })
for d in ["a", "a/b", "a/b/c", "vuota", "tanti"] where !dirs.contains(d) { fail("manca la cartella \(d)") }
if r.totalCount != r.entries.count { fail("conteggio \(r.totalCount) diverso dalle voci \(r.entries.count)") }
if UDFReader.list(path: iso, maxEntries: 5)?.truncated != true { fail("con un tetto di 5 voci l'elenco dovrebbe risultare troncato") }
if UDFReader.list(path: "/etc/hosts", maxEntries: 10) != nil { fail("un file qualunque non e' un volume UDF") }
print("ok")
