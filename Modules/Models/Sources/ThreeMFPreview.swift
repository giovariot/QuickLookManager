import AppKit
import SceneKit
import ImageIO
import QuickLookThumbnailing

/// Punto d'ingresso del modulo «Modelli 3D»: anteprima SceneKit e miniature di file 3MF.
enum ThreeMFPreview {
    private static var controllerKey: UInt8 = 0

    @MainActor
    static func makeView(for url: URL) throws -> NSView {
        let controller = ThreeMFViewController()
        let view = controller.view
        try controller.load(url: url)
        // La vista non tiene in vita il suo controller: ci pensa questo legame.
        objc_setAssociatedObject(view, &controllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return view
    }

    /// Miniatura: l'immagine che il programma di slicing ha incorporato, se c'è; altrimenti un rendering SceneKit.
    static func thumbnailReply(for url: URL, maximumSize: CGSize, scale: CGFloat) throws -> QLThumbnailReply {
        if let data = try? ThreeMFParser.extractEmbeddedThumbnail(fileAt: url),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let size = CGSize(width: cg.width, height: cg.height)
            return QLThumbnailReply(contextSize: maximumSize, drawing: { context in
                context.draw(cg, in: aspectFit(size, in: bounds(of: context)))
                return true
            })
        }
        let result = try ThreeMFParser.parse(fileAt: url)
        let scene = SceneBuilder.buildScene(from: result.items, showBuildPlate: false)
        scene.background.contents = NSColor.white
        scene.rootNode.enumerateChildNodes { node, _ in node.removeAllActions() }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: maximumSize.width * scale, height: maximumSize.height * scale),
                                      antialiasingMode: .multisampling4X)
        return QLThumbnailReply(contextSize: maximumSize, drawing: { context in
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
            context.draw(cg, in: bounds(of: context))
            return true
        })
    }

    /// Tutto il contesto di disegno della miniatura, nelle sue unità (su Retina può arrivare in pixel).
    private static func bounds(of context: CGContext) -> CGRect {
        CGRect(x: 0, y: 0, width: context.width, height: context.height).applying(context.ctm.inverted()).standardized
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let k = min(rect.width / size.width, rect.height / size.height)
        return CGRect(x: rect.midX - size.width * k / 2, y: rect.midY - size.height * k / 2, width: size.width * k, height: size.height * k)
    }
}
