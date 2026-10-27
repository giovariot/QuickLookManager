import AppKit
import CoreImage
import ImageIO
import QLMNative
import QuickLookThumbnailing

/// Modulo «Foto RAW»: l'immagine incorporata nel file (o, se manca, lo sviluppo a mezza risoluzione), letta con LibRaw.
enum RawPreview {
    struct Loaded {
        let image: CGImage
        let info: QLMRawResult
    }

    static func load(url: URL, settings: QLMSettings.Raw) throws -> Loaded {
        let result = try QLMRawKit.readFile(atPath: url.path, renderIfMissing: settings.renderIfMissing)
        guard let image = makeImage(from: result) else { throw CocoaError(.fileReadCorruptFile) }
        return Loaded(image: image, info: result)
    }

    /// `CGImage` già raddrizzata. Un JPEG con orientamento EXIF proprio lo porta con sé; negli altri casi vale quello di LibRaw.
    private static func makeImage(from r: QLMRawResult) -> CGImage? {
        if r.isJPEG {
            guard let src = CGImageSourceCreateWithData(r.imageData as CFData, nil) else { return nil }
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let hasEXIFOrientation = props?[kCGImagePropertyOrientation] != nil
            guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let orientation = Int32((props?[kCGImagePropertyOrientation] as? Int) ?? r.orientation)
            return hasEXIFOrientation || r.orientation <= 1 ? oriented(cg, orientation) : oriented(cg, Int32(r.orientation))
        }
        let w = r.width, h = r.height
        guard w > 0, h > 0, r.imageData.count >= w * h * 3, let provider = CGDataProvider(data: r.imageData as CFData) else { return nil }
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: w * 3,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        return cg.map { oriented($0, Int32(r.orientation)) }
    }

    private static func oriented(_ cg: CGImage, _ exif: Int32) -> CGImage {
        guard exif > 1, exif <= 8 else { return cg }
        let ci = CIImage(cgImage: cg).oriented(forExifOrientation: exif)
        return CIContext().createCGImage(ci, from: ci.extent) ?? cg
    }

    // MARK: Vista

    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let settings = QLMSettings.load().raw
        let loaded = try load(url: url, settings: settings)
        return ImageCaptionView(image: loaded.image, caption: settings.showInfo ? caption(for: loaded) : nil)
    }

    private static func caption(for l: Loaded) -> String {
        let i = l.info
        var parts: [String] = []
        let camera = [i.make, i.model].compactMap { $0 }.joined(separator: " ")
        if !camera.isEmpty { parts.append(camera) }
        if let lens = i.lens { parts.append(lens) }
        if i.focalLength > 0 { parts.append(String(format: "%.0f mm", i.focalLength)) }
        if i.aperture > 0 { parts.append(String(format: "ƒ/%.1f", i.aperture)) }
        if i.shutter > 0 { parts.append(i.shutter >= 1 ? String(format: "%.1f s", i.shutter) : "1/\(Int((1 / i.shutter).rounded())) s") }
        if i.iso > 0 { parts.append("ISO \(Int(i.iso))") }
        if i.rawWidth > 0 { parts.append("\(i.rawWidth)×\(i.rawHeight)") }
        if let date = i.date { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        if i.wasRendered { parts.append(String(localized: "sviluppata da LibRaw", bundle: QLMBundle.framework)) }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Miniatura

    static func thumbnailReply(for url: URL, maximumSize: CGSize) throws -> QLThumbnailReply {
        let loaded = try load(url: url, settings: QLMSettings.load().raw)
        let cg = loaded.image
        let size = CGSize(width: cg.width, height: cg.height)
        let k = min(maximumSize.width / size.width, maximumSize.height / size.height)
        let fitted = CGSize(width: size.width * k, height: size.height * k)
        return QLThumbnailReply(contextSize: fitted, drawing: { context in
            context.draw(cg, in: CGRect(origin: .zero, size: fitted))
            return true
        })
    }
}

