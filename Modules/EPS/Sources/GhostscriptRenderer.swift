import Foundation
import ImageIO

/// Rende un EPS con Ghostscript, caricato a runtime da `libgs.dylib`. Se la libreria non c'è, `render` fallisce
/// e il modulo ripiega sull'anteprima incorporata: niente dipende da Ghostscript in fase di collegamento.
///
/// Ghostscript ammette una sola istanza per processo: le rese passano da un lucchetto.
public enum GhostscriptRenderer {
    enum Failure: Error { case libraryMissing, failed(Int32), noOutput }

    private typealias NewInstance = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>, UnsafeMutableRawPointer?) -> Int32
    private typealias SetArgEncoding = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Int32
    private typealias InitWithArgs = @convention(c) (UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
    private typealias Exit = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    private typealias DeleteInstance = @convention(c) (UnsafeMutableRawPointer?) -> Void

    private static let lock = NSLock()

    /// Dove cercare `libgs.dylib`: nel framework (`Ghostscript/`), poi in `QLM_LIBGS` (solo Debug).
    private static var libraryCandidates: [String] {
        var paths: [String] = []
        #if DEBUG
        if let p = ProcessInfo.processInfo.environment["QLM_LIBGS"] { paths.append(p) }
        #endif
        if let res = QLMBundle.framework.resourceURL {
            paths.append(res.appendingPathComponent("Ghostscript/libgs.dylib").path)
        }
        return paths
    }

    /// Cartella con `Resource/Init` e i font di Ghostscript, accanto alla libreria.
    private static func resourceDirectory(for lib: String) -> String? {
        let dir = (lib as NSString).deletingLastPathComponent
        for candidate in ["\(dir)/Resource", "\(dir)/../share/ghostscript/Resource"] where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return nil
    }

    /// `true` se Ghostscript è incorporato nell'app (o indicato da `QLM_LIBGS` in Debug).
    public static var isAvailable: Bool { libraryCandidates.contains { FileManager.default.fileExists(atPath: $0) } }

    static func render(url: URL, resolution: Int) throws -> CGImage {
        guard let libPath = libraryCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { throw Failure.libraryMissing }
        guard let handle = dlopen(libPath, RTLD_NOW | RTLD_LOCAL) else {
            NSLog("QuickLook Manager EPS: dlopen non riuscito: \(String(cString: dlerror()))")
            throw Failure.libraryMissing
        }
        guard let pNew = dlsym(handle, "gsapi_new_instance"),
              let pEnc = dlsym(handle, "gsapi_set_arg_encoding"),
              let pInit = dlsym(handle, "gsapi_init_with_args"),
              let pExit = dlsym(handle, "gsapi_exit"),
              let pDelete = dlsym(handle, "gsapi_delete_instance") else { throw Failure.libraryMissing }
        let newInstance = unsafeBitCast(pNew, to: NewInstance.self)
        let setEncoding = unsafeBitCast(pEnc, to: SetArgEncoding.self)
        let initWithArgs = unsafeBitCast(pInit, to: InitWithArgs.self)
        let exitGS = unsafeBitCast(pExit, to: Exit.self)
        let deleteInstance = unsafeBitCast(pDelete, to: DeleteInstance.self)

        lock.lock(); defer { lock.unlock() }
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("qlm-eps-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }

        var args = ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-dEPSCrop", "-sDEVICE=png16m",
                    "-dTextAlphaBits=4", "-dGraphicsAlphaBits=4", "-r\(max(36, min(resolution, 600)))",
                    "-sOutputFile=\(output.path)", "--permit-file-read=\(url.path)"]
        if let res = resourceDirectory(for: libPath) {
            var dirs = ["\(res)/Init", "\(res)/Font", res]
            let base = (res as NSString).deletingLastPathComponent as NSString
            for extra in ["lib", "iccprofiles"] where FileManager.default.fileExists(atPath: base.appendingPathComponent(extra)) {
                dirs.append(base.appendingPathComponent(extra))
            }
            args.append("-I" + dirs.joined(separator: ":"))
        }
        args.append(url.path)
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        defer { cArgs.forEach { free($0) } }

        var instance: UnsafeMutableRawPointer?
        guard newInstance(&instance, nil) >= 0 else { throw Failure.failed(-1) }
        _ = setEncoding(instance, 1) // GS_ARG_ENCODING_UTF8
        let code = initWithArgs(instance, Int32(cArgs.count), &cArgs)
        _ = exitGS(instance)
        deleteInstance(instance)
        guard code >= 0 else { throw Failure.failed(code) }
        // Il file temporaneo sparisce all'uscita: l'immagine va decodificata ora, non quando qualcuno la disegna.
        guard let data = try? Data(contentsOf: output),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let ctx = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.noOutput }
        ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        guard let cg = ctx.makeImage() else { throw Failure.noOutput }
        return cg
    }
}
