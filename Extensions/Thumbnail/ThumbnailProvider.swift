import QuickLookThumbnailing
import QLMCore
import os

private let log = Logger(subsystem: "com.giovariot.QuickLookManager", category: "thumbnail")

extension QLThumbnailReply {
    /// Metodo privato `setIconFlavor:` (lo usava anche QLAppBundle): 0 = icona così com'è, trasparente, senza il
    /// riquadro bianco che il Finder mette dietro le miniature dei documenti; 12 = stile «pattern» degli archivi Xcode.
    fileprivate func setFlavor(_ flavor: Int) {
        typealias SetIconFlavor = @convention(c) (NSObject, Selector, NSInteger) -> Bool
        let selector = NSSelectorFromString("setIconFlavor:")
        guard responds(to: selector) else { return }
        _ = unsafeBitCast(method(for: selector), to: SetIconFlavor.self)(self, selector, flavor)
    }
}

/// Estensione miniature: `QLMRouter` sceglie il modulo e prepara la risposta.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let name = request.fileURL.lastPathComponent
        let logging = QLMSettings.load().diagnosticLog
        let start = ContinuousClock.now
        do {
            let reply = try QLMRouter.thumbnailReply(for: request)
            // Le app (e i programmi Windows, Mac classici…) mostrano la loro icona con la sua forma, senza riquadro.
            if QLMRouter.module(for: request.fileURL) == .apps {
                reply.setFlavor(request.fileURL.pathExtension.lowercased() == "xcarchive" ? 12 : 0)
            }
            if logging { log.info("miniatura di \(name, privacy: .public): risposta preparata in \((ContinuousClock.now - start).milliseconds) ms") }
            handler(reply, nil)
        } catch {
            if logging { log.info("nessuna miniatura per \(name, privacy: .public) dopo \((ContinuousClock.now - start).milliseconds) ms: \(String(describing: error), privacy: .public)") }
            handler(nil, error)
        }
    }
}

private extension Duration {
    var milliseconds: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
