import Foundation
import QLMNative
import Security

/// Tutto ciò che si può dire di un pacchetto `.pkg` senza installarlo e senza scompattarne il payload.
struct PkgReport {
    struct Component {
        var name: String                       // la cartella nel pacchetto, per esempio «Foo.pkg»
        var identifier: String?
        var version: String?
        var installLocation: String?
        var auth: String?
        var numberOfFiles: Int?
        var installKBytes: Int?
        var scripts: [String] = []             // nomi degli script dichiarati in PackageInfo
        var scriptFiles: [QLMArchiveEntry] = []
        var entries: [BomReader.Entry] = []
        var totalEntries = 0
        var truncated = false
    }

    var fileName: String
    var fileSize: Int64
    var title: String?
    var components: [Component] = []
    var hostArchitectures: String?
    var minimumOS: String?
    var requiresRestart = false
    var isDistribution = false
    var signers: [String] = []                 // dal firmatario alla radice
    var chainIsTrusted: Bool?
    var signatureStyle: String?
}

enum PkgInspector {
    enum Failure: Error, LocalizedError {
        case notFlat
        var errorDescription: String? { String(localized: "Non è un pacchetto «flat» (xar): i pacchetti in formato cartella non sono supportati.", bundle: QLMBundle.framework) }
    }

    static let maxEntries = 20000

    static func inspect(url: URL) throws -> PkgReport {
        let xar: XarArchive
        do { xar = try XarArchive(url: url) } catch { throw Failure.notFlat }
        var report = PkgReport(fileName: url.lastPathComponent,
                               fileSize: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))

        // Distribution: titolo, requisiti e riavvio.
        if let m = xar.member("Distribution"), let data = xar.data(of: m) {
            report.isDistribution = true
            let d = DistributionParser(data: data)
            report.title = d.title
            report.hostArchitectures = d.hostArchitectures
            report.minimumOS = d.minimumOS
            report.requiresRestart = d.requiresRestart
        }

        // Componenti: ogni cartella con un PackageInfo (o, in un pacchetto semplice, i file alla radice).
        let infoMembers = xar.members.filter { $0.path == "PackageInfo" || $0.path.hasSuffix("/PackageInfo") }
        for info in infoMembers {
            let prefix = String(info.path.dropLast("PackageInfo".count))
            var c = PkgReport.Component(name: prefix.isEmpty ? url.lastPathComponent : String(prefix.dropLast()))
            if let data = xar.data(of: info) { PackageInfoParser(data: data).fill(&c) }
            if let bomMember = xar.member(prefix + "Bom"), let bomData = xar.data(of: bomMember, maxBytes: 256 << 20), let bom = BomReader(data: bomData) {
                let r = bom.entries(limit: maxEntries)
                c.entries = r.entries; c.totalEntries = r.total; c.truncated = r.truncated
            }
            if let scripts = xar.member(prefix + "Scripts"), let data = xar.data(of: scripts, maxBytes: 64 << 20),
               let listing = try? QLMArchiveKit.listData(data, maxEntries: 500) {
                c.scriptFiles = listing.entries.filter { !$0.isDirectory && !($0.path as NSString).lastPathComponent.hasPrefix("._") }
            }
            report.components.append(c)
        }

        // Firma: i certificati nell'indice dell'archivio.
        if let sig = xar.signature {
            report.signatureStyle = sig.style
            let certs = sig.certificates.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            report.signers = certs.compactMap { SecCertificateCopySubjectSummary($0) as String? }
            if !certs.isEmpty {
                var trust: SecTrust?
                if SecTrustCreateWithCertificates(certs as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess, let trust {
                    report.chainIsTrusted = SecTrustEvaluateWithError(trust, nil)
                }
            }
        }
        return report
    }
}

// MARK: Analisi degli XML

/// `Distribution`: l'XML che descrive l'installazione guidata.
private final class DistributionParser: NSObject, XMLParserDelegate {
    var title: String?
    var hostArchitectures: String?
    var minimumOS: String?
    var requiresRestart = false
    private var text = ""
    private var inTitle = false

    init(data: Data) {
        super.init()
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        switch name {
        case "title": inTitle = true; text = ""
        case "options": hostArchitectures = a["hostArchitectures"] ?? hostArchitectures
        case "os-version": if minimumOS == nil { minimumOS = a["min"] }
        case "pkg-ref": if let c = a["onConclusion"], c.lowercased().contains("restart") { requiresRestart = true }
        case "restart": requiresRestart = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { if inTitle { text += s } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "title", inTitle { inTitle = false; let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty, title == nil { title = t } }
    }
}

/// `PackageInfo`: i dati di un singolo componente.
private final class PackageInfoParser: NSObject, XMLParserDelegate {
    private var info: [String: String] = [:]
    private var payload: [String: String] = [:]
    private var scripts: [String] = []
    private var inScripts = false

    init(data: Data) {
        super.init()
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func fill(_ c: inout PkgReport.Component) {
        c.identifier = info["identifier"]
        c.version = info["version"]
        c.installLocation = info["install-location"]
        c.auth = info["auth"]
        c.numberOfFiles = payload["numberOfFiles"].flatMap(Int.init)
        c.installKBytes = payload["installKBytes"].flatMap(Int.init)
        c.scripts = scripts
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        switch name {
        case "pkg-info": info = a
        case "payload": payload = a
        case "scripts": inScripts = true
        default: if inScripts, a["file"] != nil { scripts.append(name) }
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "scripts" { inScripts = false }
    }
}
