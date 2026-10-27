import AppKit
import ImageIO
import QuickLookThumbnailing

/// Modulo EPS. macOS non sa più disegnare i PostScript: l'anteprima si prende dall'immagine che il file porta con sé
/// (TIFF del formato DOS EPS Binary, oppure bitmap `%%BeginPreview`) e, se manca o se lo si chiede, da Ghostscript.
enum EPSPreview {
    struct Metadata {
        var title: String?
        var creator: String?
        var date: String?
        var boundingBox: CGRect?
    }

    struct Loaded {
        let image: CGImage?
        let metadata: Metadata
        let source: Source
        enum Source { case embedded, ghostscript, none }
    }

    // MARK: Lettura

    static func load(url: URL, settings: QLMSettings.EPS) throws -> Loaded {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let meta = parseMetadata(data)
        if settings.preferEmbeddedPreview, let img = embeddedPreview(in: data) {
            return Loaded(image: img, metadata: meta, source: .embedded)
        }
        do {
            let img = try GhostscriptRenderer.render(url: url, resolution: settings.resolution)
            return Loaded(image: img, metadata: meta, source: .ghostscript)
        } catch {
            NSLog("QuickLook Manager EPS: Ghostscript non ha reso \(url.lastPathComponent): \(error)")
        }
        if let img = embeddedPreview(in: data) {
            return Loaded(image: img, metadata: meta, source: .embedded)
        }
        return Loaded(image: nil, metadata: meta, source: .none)
    }

    /// Anteprima incorporata: prima il TIFF del formato binario DOS, poi il bitmap ASCII.
    static func embeddedPreview(in data: Data) -> CGImage? {
        if data.count > 30, data[0] == 0xC5, data[1] == 0xD0, data[2] == 0xD3, data[3] == 0xC6 {
            func u32(_ o: Int) -> Int {
                Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24
            }
            let tiffStart = u32(20), tiffLength = u32(24)
            if tiffLength > 0, tiffStart + tiffLength <= data.count,
               let src = CGImageSourceCreateWithData(data.subdata(in: tiffStart..<(tiffStart + tiffLength)) as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return cg
            }
        }
        return asciiPreview(in: data)
    }

    /// `%%BeginPreview: larghezza altezza profondità righe` seguito da righe `% HEX…` fino a `%%EndPreview`.
    private static func asciiPreview(in data: Data) -> CGImage? {
        // Le intestazioni stanno nei primi kilobyte: non serve leggere tutto come testo.
        let head = data.prefix(1 << 20)
        guard let text = String(data: head, encoding: .isoLatin1),
              let begin = text.range(of: "%%BeginPreview:"),
              let end = text.range(of: "%%EndPreview", range: begin.upperBound..<text.endIndex) else { return nil }
        let lines = text[begin.upperBound..<end.lowerBound].split(whereSeparator: \.isNewline)
        guard let header = lines.first else { return nil }
        let nums = header.split(separator: " ").compactMap { Int($0) }
        guard nums.count >= 3, nums[0] > 0, nums[1] > 0, [1, 2, 4, 8].contains(nums[2]) else { return nil }
        let (w, h, depth) = (nums[0], nums[1], nums[2])
        var bytes: [UInt8] = []
        for line in lines.dropFirst() {
            var s = Substring(line)
            if s.hasPrefix("%") { s = s.dropFirst() }
            var hi: UInt8?
            for c in s.utf8 {
                guard let v = hexValue(c) else { continue }
                if let h0 = hi { bytes.append(h0 << 4 | v); hi = nil } else { hi = v }
            }
        }
        let rowBytes = (w * depth + 7) / 8
        guard bytes.count >= rowBytes * h else { return nil }
        var gray = [UInt8](repeating: 0, count: w * h)
        let maxValue = (1 << depth) - 1
        for y in 0..<h {
            for x in 0..<w {
                let bit = x * depth
                let byte = bytes[y * rowBytes + bit / 8]
                let v = Int(byte >> UInt8(8 - depth - bit % 8)) & maxValue
                gray[y * w + x] = UInt8(v * 255 / maxValue)
            }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 65...70: return c - 55
        case 97...102: return c - 87
        default: return nil
        }
    }

    /// `%%Title`, `%%Creator`, `%%CreationDate` e `%%BoundingBox` dal preambolo.
    static func parseMetadata(_ data: Data) -> Metadata {
        var m = Metadata()
        let start: Int
        if data.count > 30, data[0] == 0xC5, data[1] == 0xD0 { start = Int(data[4]) | Int(data[5]) << 8 | Int(data[6]) << 16 | Int(data[7]) << 24 } else { start = 0 }
        guard start < data.count, let text = String(data: data[start..<min(data.count, start + 65536)], encoding: .isoLatin1) else { return m }
        for line in text.split(whereSeparator: \.isNewline).prefix(400) {
            if line.hasPrefix("%%EndComments") { break }
            func value(_ key: String) -> String? {
                line.hasPrefix(key) ? line.dropFirst(key.count).trimmingCharacters(in: .whitespaces) : nil
            }
            if let v = value("%%Title:") { m.title = v.trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
            else if let v = value("%%Creator:") { m.creator = v.trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
            else if let v = value("%%CreationDate:") { m.date = v.trimmingCharacters(in: CharacterSet(charactersIn: "()")) }
            else if let v = value("%%BoundingBox:") {
                let n = v.split(separator: " ").compactMap { Double($0) }
                if n.count == 4 { m.boundingBox = CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1]) }
            }
        }
        return m
    }

    // MARK: Vista

    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let loaded = try load(url: url, settings: QLMSettings.load().eps)
        let caption = caption(for: loaded)
        if let image = loaded.image {
            return ImageCaptionView(image: image, caption: caption)
        }
        // Nessuna immagine: almeno le informazioni del file.
        let label = NSTextField(wrappingLabelWithString: caption.isEmpty ? url.lastPathComponent : caption)
        label.alignment = .center
        label.font = .preferredFont(forTextStyle: .title3)
        let note = NSTextField(wrappingLabelWithString: String(localized: "Il file non contiene un'anteprima e Ghostscript non è disponibile: non si può disegnare.", bundle: QLMBundle.framework))
        note.textColor = .secondaryLabelColor
        note.alignment = .center
        let stack = NSStackView(views: [label, note])
        stack.orientation = .vertical
        stack.spacing = 12
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -48),
        ])
        return host
    }

    private static func caption(for l: Loaded) -> String {
        var parts: [String] = []
        if let t = l.metadata.title, !t.isEmpty { parts.append(t) }
        if let c = l.metadata.creator, !c.isEmpty { parts.append(c) }
        if let b = l.metadata.boundingBox { parts.append("\(Int(b.width))×\(Int(b.height)) pt") }
        if let d = l.metadata.date, !d.isEmpty { parts.append(d) }
        switch l.source {
        case .embedded: parts.append(String(localized: "anteprima incorporata", bundle: QLMBundle.framework))
        case .ghostscript: parts.append("Ghostscript")
        case .none: break
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Miniatura

    static func thumbnailReply(for url: URL, maximumSize: CGSize) throws -> QLThumbnailReply {
        let loaded = try load(url: url, settings: QLMSettings.load().eps)
        guard let cg = loaded.image else { throw CocoaError(.featureUnsupported) }
        let size = CGSize(width: cg.width, height: cg.height)
        let k = min(maximumSize.width / size.width, maximumSize.height / size.height)
        let fitted = CGSize(width: size.width * k, height: size.height * k)
        return QLThumbnailReply(contextSize: fitted, drawing: { context in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: fitted))
            context.draw(cg, in: CGRect(origin: .zero, size: fitted))
            return true
        })
    }
}
