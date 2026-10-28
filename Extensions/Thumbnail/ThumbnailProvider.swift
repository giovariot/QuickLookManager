import QuickLookThumbnailing
import QLMCore
import os

private let log = Logger(subsystem: "com.giovariot.QuickLookManager", category: "thumbnail")

/// Estensione miniature: `QLMRouter` sceglie il modulo e prepara la risposta.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let name = request.fileURL.lastPathComponent
        let start = ContinuousClock.now
        do {
            let reply = try QLMRouter.thumbnailReply(for: request)
            log.info("miniatura di \(name, privacy: .public): risposta preparata in \((ContinuousClock.now - start).milliseconds) ms")
            handler(reply, nil)
        } catch {
            log.info("nessuna miniatura per \(name, privacy: .public) dopo \((ContinuousClock.now - start).milliseconds) ms: \(String(describing: error), privacy: .public)")
            handler(nil, error)
        }
    }
}

private extension Duration {
    var milliseconds: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
