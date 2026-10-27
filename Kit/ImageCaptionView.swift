import AppKit

/// L'immagine che riempie la vista, con una riga di dati di scatto sotto.
/// Usata dai moduli RAW ed EPS.
final class ImageCaptionView: NSView {
    init(image: CGImage, caption: String?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let imageView = NSImageView(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(imageView)
        var constraints = [
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        if let caption {
            let bar = NSVisualEffectView()
            bar.material = .headerView
            bar.blendingMode = .withinWindow
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            let label = NSTextField(wrappingLabelWithString: caption)
            label.font = .preferredFont(forTextStyle: .callout)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(label)
            constraints += [
                bar.leadingAnchor.constraint(equalTo: leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor),
                imageView.bottomAnchor.constraint(equalTo: bar.topAnchor),
                label.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -8),
                label.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            ]
        } else {
            constraints.append(imageView.bottomAnchor.constraint(equalTo: bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }
    required init?(coder: NSCoder) { fatalError() }
}
