#if DEBUG
import SwiftUI
import QLMCore
import QLMNative

/// Strumenti di prova, solo in Debug.
///
/// - `-QLMRender <file> <png>`: l'anteprima che l'estensione darebbe a quel file, in una finestra salvata come PNG.
///   Non registra niente nel sistema.
/// - `-QLMModule <modulo>`: forza il modulo (text|apps|archives|raw|models|eps).
/// - `-QLMSnapshot <png>` (con `-QLMPane try|text|apps|archives|video|raw`): salva la finestra dell'app.
enum DebugTools {
    @MainActor
    static func runIfRequested() {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "-QLMModule"), i + 1 < a.count { QLMRouter.debugForcedModule = QLMModule(rawValue: a[i + 1]) }
        if let i = a.firstIndex(of: "-QLMThumb"), i + 2 < a.count {
            let cg = QLMMediaReader.copyThumbnail(forPath: a[i + 1], fraction: 0.5, maxSize: 512)
            print("MINIATURA: \(cg.map { "\($0.width)x\($0.height)" } ?? "nessuna")")
            if let cg { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 2])) }
            exit(0)
        } else if let i = a.firstIndex(of: "-QLMRender"), i + 2 < a.count {
            render(file: URL(fileURLWithPath: a[i + 1]), to: URL(fileURLWithPath: a[i + 2]))
        } else if let i = a.firstIndex(of: "-QLMSnapshot"), i + 1 < a.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.activate(ignoringOtherApps: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                for (n, w) in NSApp.windows.filter({ $0.isVisible && $0.contentView != nil }).enumerated() {
                    save(window: w, to: URL(fileURLWithPath: a[i + 1]), suffix: "-\(n)")
                }
                NSApp.terminate(nil)
            }
        }
    }

    static var initialPane: AppState.Pane? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "-QLMPane"), i + 1 < a.count else { return nil }
        if a[i + 1] == "try" { return .try_ }
        if a[i + 1] == "activation" { return .activation }
        return QLMModule(rawValue: a[i + 1]).map { .module($0) }
    }

    @MainActor
    private static func render(file: URL, to out: URL) {
        Task { @MainActor in
            do {
                let view = try await QLMRouter.makeView(for: file)
                let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
                w.contentView = view
                w.orderFrontRegardless()
                try? await Task.sleep(for: .seconds(Double(ProcessInfo.processInfo.environment["QLM_RENDER_DELAY"] ?? "3") ?? 3))
                if let r = VideoDebug.report(view) {
                    print("VIDEO dopo 3 s: \(r)")
                    // Salto a metà, poi chiusura della finestra: il lettore deve fermarsi da solo.
                    try? await Task.sleep(for: .seconds(1))
                    print("VIDEO dopo 4 s: \(VideoDebug.report(view) ?? "-")")
                    if let to = ProcessInfo.processInfo.environment["QLM_RENDER_SEEK"].flatMap(Double.init) {
                        VideoDebug.seek(view, to: to)
                        try? await Task.sleep(for: .seconds(1))
                        print("VIDEO dopo il salto a \(to) s + 1 s: \(VideoDebug.report(view) ?? "-")")
                    }
                }
                save(window: w, to: out, suffix: "")
                if VideoDebug.report(view) != nil {
                    VideoDebug.simulateClose(view)
                    try? await Task.sleep(for: .milliseconds(300))
                    print("VIDEO dopo la chiusura: \(VideoDebug.report(view) ?? "-")")
                }
            } catch {
                print("QLMRender errore: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func save(window w: NSWindow, to url: URL, suffix: String) {
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming]) else { return }
        let name = url.deletingPathExtension().lastPathComponent + suffix + ".png"
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
            .write(to: url.deletingLastPathComponent().appendingPathComponent(name))
    }
}
#endif
