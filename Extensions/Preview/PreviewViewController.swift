import Cocoa
import QuickLookUI
import QLMCore
import os

private let log = Logger(subsystem: "com.giovariot.QuickLookManager", category: "preview")

/// Estensione Quick Look (anteprima basata su vista): `QLMRouter` sceglie il modulo.
@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        log.info("anteprima di \(url.lastPathComponent, privacy: .public)")
        let content: NSView
        do { content = try await QLMRouter.makeView(for: url) } catch {
            log.error("errore: \(String(describing: error), privacy: .public)")
            throw error
        }
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        log.info("vista pronta per \(url.lastPathComponent, privacy: .public)")
    }
}
