import AppKit

extension NSImage {
	/// Because some (PNG) image data will return weird float values
	func bestImageSize() -> NSSize {
		var w: Int = 0
		var h: Int = 0
		for imageRep in self.representations {
			w = max(w, imageRep.pixelsWide)
			h = max(h, imageRep.pixelsHigh)
		}
		return NSSize(width: w, height: h)
	}
	
	/// Rounds the corners only when the image is an opaque square (iOS and Android icons): an icon that
	/// already has its own shape (macOS, Windows, classic Mac) keeps it, with its transparent corners.
	func roundedIfSquare() -> NSImage {
		let size = bestImageSize()
		guard size.width > 0, size.height > 0 else { return self }
		guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
		      rep.hasAlpha else { return withRoundCorners() }
		let w = rep.pixelsWide, h = rep.pixelsHigh
		let corners = [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)]
		let opaque = corners.allSatisfy { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 1) > 0.98 }
		return opaque ? withRoundCorners() : self
	}
	
	/// Apply rounded corners to image (iOS7 style)
	func withRoundCorners() -> NSImage {
		let existingSize = bestImageSize()
		// Un'immagine senza misura in pixel (per esempio una disegnata al volo) non si può ritagliare:
		// `lockFocus` su 0×0 lancia un'eccezione e fa morire l'estensione.
		guard existingSize.width > 0, existingSize.height > 0 else { return self }
		let composedImage = NSImage(size: existingSize)
		
		composedImage.lockFocus()
		NSGraphicsContext.current?.imageInterpolation = .high
		
		let imageFrame = NSRect(origin: .zero, size: existingSize)
		let clipPath = NSBezierPath.IOS7RoundedRect(imageFrame, cornerRadius: existingSize.width * 0.225)
		clipPath.windingRule = .evenOdd
		clipPath.addClip()
		
		self.draw(in: imageFrame)
		composedImage.unlockFocus()
		return composedImage
	}
		
	/// Convert image to PNG and encode with base64 to be embeded in html output.
	///
	/// Si prende la rappresentazione con più pixel. La strada di prima (`tiffRepresentation` e poi
	/// `NSBitmapImageRep(data:)`) ne pescava una sola, e con un'icona a più misure non era la più grande.
	func asBase64() -> String {
		let best = representations
			.compactMap { $0 as? NSBitmapImageRep }
			.max { $0.pixelsWide < $1.pixelsWide }
		if let best, let png = best.representation(using: .png, properties: [:]) {
			return png.base64EncodedString()
		}
		let imageData = tiffRepresentation!
		let imageRep = NSBitmapImageRep(data: imageData)!
		let imageDataPNG = imageRep.representation(using: .png, properties: [:])!
		return imageDataPNG.base64EncodedString()
	}
}
