import os
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

public enum QLMError: Error, LocalizedError {
    case moduleDisabled(QLMModule)
    public var errorDescription: String? {
        switch self {
        case .moduleDisabled(let m):
            String(localized: "Il modulo «\(m.title)» è disattivato in QuickLook Manager.", bundle: QLMBundle.framework)
        }
    }
}

/// Sceglie il modulo che si occupa di un file e gli chiede la vista o la miniatura.
private let thumbLog = Logger(subsystem: "com.giovariot.QuickLookManager", category: "thumbnail")

public enum QLMRouter {
    #if DEBUG
    /// Solo Debug: forza il modulo, per provare un tipo che il sistema non conosce ancora (l'app di prova non è registrata).
    nonisolated(unsafe) public static var debugForcedModule: QLMModule?
    #endif

    /// Il modulo competente per il tipo (UTI) del file; il testo prende tutto il resto.
    public static func module(for url: URL) -> QLMModule {
        #if DEBUG
        if let forced = debugForcedModule { return forced }
        #endif
        let uti = (try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier)?.lowercased() ?? ""
        return QLMTypes.module(forType: uti) ?? .text
    }

    @MainActor
    public static func makeView(for url: URL) async throws -> NSView {
        let module = module(for: url)
        guard QLMSettings.load().isEnabled(module) else { throw QLMError.moduleDisabled(module) }
        switch module {
        case .apps: return try AppsPreview.makeView(for: url)
        case .raw: return try RawPreview.makeView(for: url)
        case .models: return try ThreeMFPreview.makeView(for: url)
        case .eps: return try EPSPreview.makeView(for: url)
        case .archives: return try ArchivePreview.makeView(for: url)
        case .video: return try VideoPreview.makeView(for: url)
        case .pkg: return try PkgPreview.makeView(for: url)
        case .text: return try await PreviewFactory.makeView(for: url)
        }
    }

    /// Miniatura del file, o un errore se il modulo è spento o non ne sa fare una.
    public static func thumbnailReply(for request: QLFileThumbnailRequest) throws -> QLThumbnailReply {
        let url = request.fileURL
        let max = request.maximumSize
        let module = module(for: url)
        let settings = QLMSettings.load()
        guard settings.isEnabled(module) else { throw QLMError.moduleDisabled(module) }
        let logging = settings.diagnosticLog
        switch module {
        case .text:
            // Il testo sotto 48 pt non si legge: meglio l'icona del tipo di file, che il sistema usa se rifiutiamo.
            guard max.height >= 48 else { throw CocoaError(.featureUnsupported) }
            let size = CGSize(width: Swift.min(max.width, max.height * 0.78), height: max.height)
            return QLThumbnailReply(contextSize: size) { Thumbnailer.draw(url: url, in: CGRect(origin: .zero, size: size)) }
        case .apps:
            return QLThumbnailReply(contextSize: max) {
                // Il tempo qui è quello della lettura dell'icona dal file (grosso per gli .exe): finisce nel log.
                let start = ContinuousClock.now
                let ok = AppsPreview.drawThumbnail(url: url, in: CGRect(origin: .zero, size: max))
                let d = ContinuousClock.now - start
                if logging { thumbLog.info("icona di \(url.lastPathComponent, privacy: .public) disegnata in \(Int(d.components.seconds * 1000 + d.components.attoseconds / 1_000_000_000_000_000)) ms") }
                return ok
            }
        case .raw: return try RawPreview.thumbnailReply(for: url, maximumSize: max)
        case .models: return try ThreeMFPreview.thumbnailReply(for: url, maximumSize: max, scale: request.scale)
        case .eps: return try EPSPreview.thumbnailReply(for: url, maximumSize: max)
        case .video: return try VideoPreview.thumbnailReply(for: url, maximumSize: max, scale: request.scale)
        case .archives, .pkg: throw CocoaError(.featureUnsupported)
        }
    }
}
