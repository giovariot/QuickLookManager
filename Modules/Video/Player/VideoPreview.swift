import AppKit
import QLMNative
import QuickLookThumbnailing
import SwiftUI
import os

private let videoLog = Logger(subsystem: "com.giovariot.QuickLookManager", category: "video")

/// Modulo «Video»: lettore integrato per i formati che macOS non conosce. Parte da solo all'apertura e si ferma quando la
/// finestra di Quick Look si chiude (o quando il file viene sostituito da un altro).
enum VideoPreview {
    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let settings = QLMSettings.load().video
        let controller = try VideoPlayerController(url: url)
        return PlayerHostView(controller: controller, autoplay: settings.autoplay)
    }

    static func thumbnailReply(for url: URL, maximumSize: CGSize, scale: CGFloat) throws -> QLThumbnailReply {
        let pixels = Int(max(maximumSize.width, maximumSize.height) * scale)
        let fraction = QLMSettings.load().video.thumbnailFraction
        guard let cg = QLMMediaReader.copyThumbnail(forPath: url.path, fraction: fraction, maxSize: Int32(max(64, pixels))) else {
            throw CocoaError(.featureUnsupported)
        }
        let size = CGSize(width: cg.width, height: cg.height)
        let k = min(maximumSize.width / size.width, maximumSize.height / size.height)
        let fitted = CGSize(width: size.width * k, height: size.height * k)
        return QLThumbnailReply(contextSize: fitted, drawing: { context in
            context.draw(cg, in: CGRect(origin: .zero, size: fitted))
            return true
        })
    }
}

/// La vista dell'anteprima. È lei che sa quando la finestra sparisce.
final class PlayerHostView: NSHostingView<PlayerView> {
    fileprivate let controller: VideoPlayerController
    private let autoplay: Bool
    private var observers: [NSObjectProtocol] = []
    private var pausedByOcclusion = false

    @MainActor
    init(controller: VideoPlayerController, autoplay: Bool) {
        self.controller = controller
        self.autoplay = autoplay
        super.init(rootView: PlayerView(controller: controller))
        frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    }
    @MainActor required init(rootView: PlayerView) { fatalError("usa init(controller:autoplay:)") }
    @MainActor @objc required dynamic init?(coder: NSCoder) { fatalError() }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            videoLog.info("viewDidMoveToWindow: finestra \(self.window != nil ? "sì" : "no", privacy: .public), autoplay \(self.autoplay)")
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else {
                controller.stop()          // tolta dalla finestra: il file è cambiato o l'anteprima è chiusa
                return
            }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller.stop() }
            })
            // Finestra nascosta o coperta: niente audio per niente. Quando torna visibile si riprende, ma solo se
            // era in corso: all'apertura macOS segnala la finestra non visibile per un istante, e senza questo
            // l'avvio automatico veniva annullato.
            observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, !self.controller.isStopped else { return }
                    let visible = window.occlusionState.contains(.visible)
                    videoLog.info("occlusione: visibile=\(visible), in corso=\(self.controller.isPlaying), sospeso da me=\(self.pausedByOcclusion)")
                    if !visible, self.controller.isPlaying {
                        self.pausedByOcclusion = true
                        self.controller.pause()
                    } else if visible, self.pausedByOcclusion {
                        self.pausedByOcclusion = false
                        self.controller.play()
                    }
                }
            })
            if autoplay && !controller.isStopped && !controller.isPlaying { controller.play() }
        }
    }
}

#if DEBUG
/// Solo Debug: lo stato del lettore, per le prove da riga di comando.
public enum VideoDebug {
    @MainActor
    public static func report(_ view: NSView) -> String? {
        guard let host = view as? PlayerHostView else { return nil }
        return host.debugState
    }
    @MainActor
    public static func seek(_ view: NSView, to seconds: Double) { (view as? PlayerHostView)?.controller.seek(to: seconds) }
    @MainActor
    public static func simulateClose(_ view: NSView) { (view as? PlayerHostView)?.window?.close() }
}

extension PlayerHostView {
    @MainActor var debugState: String { controller.debugState }
}

extension VideoPlayerController {
    var debugState: String {
        "playing=\(isPlaying) stopped=\(isStopped) t=\(String(format: "%.2f", currentTime)) duration=\(String(format: "%.1f", duration)) "
        + "video=\(hasVideo) audio=\(hasAudio) details=[\(details)] videoStatus=\(displayLayer.status.rawValue) "
        + "audioStatus=\(debugAudioStatus) finished=\(isFinished)"
    }
}
#endif
