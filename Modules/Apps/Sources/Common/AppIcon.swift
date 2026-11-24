import Foundation
import AppKit // NSImage
import AssetCarReader // CarReader
import os // OSLog

private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "de.relikd.QLAppBundleExtended", category: "AppIcon")


struct AppIcon {
	let meta: MetaInfo
	
	init(_ meta: MetaInfo) {
		self.meta = meta
	}
	
	/// Convenience getter to extract app icon regardless of bundle-type.
	func extractImageForThumbnail() -> NSImage {
		switch meta.type {
		case .IPA, .Archive, .Extension, .MacApp:
			extractImage(from: meta.readPlist_Icon()?.filenames)
		case .APK:
			extractImage(from: meta.readApk_Icon())
		case .ClassicMac:
			ClassicSupport.icon(for: meta) ?? defaultIcon()
		case .WindowsPE:
			// Senza icona incorporata: un file .ico con lo stesso nome accanto al programma, se c'è; poi, per un
			// programma DOS, l'icona del prompt; per il resto (DLL, .exe di Windows) una pagina con il simbolo di Windows.
			ClassicSupport.icon(for: meta)
				?? siblingIcon(of: meta.url)
				?? (WindowsIcon.isDOSProgram(at: meta.url) ? dosIcon() : windowsDocumentIcon(label: meta.url.pathExtension))
		case .Flatpak:
			// I due PNG che `flatpak build-bundle` mette nei metadati: si legge
			// il più grande, e non si tocca il resto del file.
			FlatpakBundle.icona(meta.url).flatMap { NSImage(data: $0) } ?? defaultIcon()
		}
	}
	
	/// Extract image from Android app bundle.
	func extractImage(from apkIcon: Apk_Icon?) -> NSImage {
		if let data = apkIcon?.data, let img = NSImage(data: data) {
			return img
		}
		return defaultIcon()
	}
	
	/// Try multiple methods to extract image.
	/// This method will always return an image even if none is found, in which case it returns the default image.
	func extractImage(from plistIcons: [String]?) -> NSImage {
		// no need to unwrap the plist, and most .ipa should include the Artwork anyway
		if meta.type == .IPA {
			if let data = meta.zipFile!.unzipFile("iTunesArtwork"), let img = NSImage(data: data) {
				os_log(.debug, log: log, "[icon] using iTunesArtwork.")
				return img
			}
			// else, fallthrough
		}
		
		// Extract image name from app plist
		var plistImgNames = plistIcons ?? []
		os_log(.debug, log: log, "[icon] icon names in plist: %{public}@", plistImgNames)
		
		// If no previous filename works (or empty), try default icon names
		plistImgNames.append("Icon")
		plistImgNames.append("icon")
		plistImgNames.append("AppIcon")
		
		// First, try if an image file with that name exists.
		//
		// Il nome trovato non garantisce un'immagine: la ricerca va per
		// prefisso, e in un pacchetto qualunque può pescare una cartella o un
		// file che immagine non è. Con il `!` di prima l'anteprima moriva --
		// misurato su un framework di sistema, dove l'estensione non mostrava
		// niente perché il processo era già finito. Se non si apre, si va
		// avanti con le altre strade.
		if let actualName = expandImageName(plistImgNames) {
			os_log(.debug, log: log, "[icon] using plist image file %{public}@", actualName)
			if meta.type == .IPA {
				if let data = meta.zipFile!.unzipFile(actualName), let img = NSImage(data: data) {
					return img
				}
			} else if let img = NSImage(contentsOfFile: actualName) {
				return biggerFromAssetsCar(than: img, name: plistImgNames.first) ?? img
			}
			os_log(.error, log: log, "[icon] '%{public}@' non si apre come immagine", actualName)
		}
		
		// Else: try Assets.car
		if let primo = plistImgNames.first, let img = imageFromAssetsCar(primo) {
			return img
		}
		
		// Fallback to default icon
		return defaultIcon()
	}
	
	/// Return the bundled default icon `"defaultIcon.png"`
	/// La pagina di documento generica del sistema, con il simbolo di Windows (quattro riquadri) al posto del punto
	/// interrogativo e l'estensione sotto, come fa il sistema con i file .reg.
	private func windowsDocumentIcon(label: String) -> NSImage {
		let side: CGFloat = 512
		let page = NSWorkspace.shared.icon(for: .data)
		return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
			NSGraphicsContext.current?.imageInterpolation = .high
			page.draw(in: rect)
			let ink = NSColor.systemGray.withAlphaComponent(0.8)
			ink.setFill()
			let pane: CGFloat = 62, gap: CGFloat = 10
			let origin = CGPoint(x: rect.midX - pane - gap / 2 - 12, y: rect.midY - 44)
			for row in 0..<2 {
				for col in 0..<2 {
					let r = NSRect(x: origin.x + CGFloat(col) * (pane + gap), y: origin.y + CGFloat(row) * (pane + gap), width: pane, height: pane)
					NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
				}
			}
			let text = label.uppercased() as NSString
			let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .semibold), .foregroundColor: ink]
			let w = text.size(withAttributes: attrs).width
			text.draw(at: CGPoint(x: rect.midX - w / 2 - 12, y: origin.y - 64), withAttributes: attrs)
			return true
		}
	}
	
	/// `NOME.ICO` (qualunque maiuscola) nella stessa cartella. Dalla sandbox dell'estensione la cartella può non
	/// essere leggibile: in quel caso non si trova niente e si passa all'icona generica.
	private func siblingIcon(of url: URL) -> NSImage? {
		let dir = url.deletingLastPathComponent()
		let base = url.deletingPathExtension().lastPathComponent.lowercased()
		guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
		      let match = names.first(where: { $0.lowercased() == base + ".ico" }),
		      let data = try? Data(contentsOf: dir.appendingPathComponent(match)),
		      let image = NSImage(data: data), image.size.width > 0 else { return nil }
		return image
	}
	
	/// Il prompt dei comandi in una finestra: per i programmi DOS, che non hanno icone dentro.
	private func dosIcon() -> NSImage {
		let side: CGFloat = 512
		return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
			NSGraphicsContext.current?.imageInterpolation = .high
			let frame = rect.insetBy(dx: 52, dy: 100)
			let shadow = NSShadow()
			shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
			shadow.shadowBlurRadius = 14
			shadow.shadowOffset = NSSize(width: 0, height: -6)
			NSGraphicsContext.saveGraphicsState()
			shadow.set()
			NSColor.lightGray.setFill()
			NSBezierPath(roundedRect: frame, xRadius: 18, yRadius: 18).fill()
			NSGraphicsContext.restoreGraphicsState()
			let bar = NSRect(x: frame.minX + 10, y: frame.maxY - 58, width: frame.width - 20, height: 46)
			NSColor.systemBlue.setFill()
			NSBezierPath(roundedRect: bar, xRadius: 10, yRadius: 10).fill()
			let screen = NSRect(x: frame.minX + 14, y: frame.minY + 14, width: frame.width - 28, height: frame.height - 82)
			NSColor.black.setFill()
			NSBezierPath(roundedRect: screen, xRadius: 8, yRadius: 8).fill()
			let attrs: [NSAttributedString.Key: Any] = [
				.font: NSFont.monospacedSystemFont(ofSize: 72, weight: .bold),
				.foregroundColor: NSColor.white]
			("C:\\>_" as NSString).draw(at: CGPoint(x: screen.minX + 26, y: screen.midY - 44), withAttributes: attrs)
			return true
		}
	}
	
	private func defaultIcon() -> NSImage {
		// Anche qui niente `!`: un'icona che manca vale un riquadro vuoto, non
		// un'anteprima che non compare.
		if let iconURL = QLMBundle.appsResources.url(forResource: "defaultIcon", withExtension: "png"),
		   let img = NSImage(contentsOf: iconURL) {
			return img
		}
		os_log(.error, log: log, "[icon] manca defaultIcon.png nel bundle")
		return NSImage(size: NSSize(width: 1, height: 1))
	}
	
	/// Extract an image from `Assets.car`
	/// Un `.icns` moderno arriva a 256 pixel (le misure da 512 e 1024 stanno nel catalogo `Assets.car`): se il
	/// catalogo ha la stessa icona più grande, si usa quella. Per le app macOS, non per gli IPA.
	private func biggerFromAssetsCar(than img: NSImage, name: String?) -> NSImage? {
		guard meta.type != .IPA, let name, img.bestImageSize().width < 512,
		      let car = imageFromAssetsCar(name), car.bestImageSize().width > img.bestImageSize().width else { return nil }
		return car
	}

	func imageFromAssetsCar(_ imageName: String) -> NSImage? {
		guard let data = meta.readPayloadFile("Assets.car", osxSubdir: "Resources") else {
			return nil
		}
		return CarReader(data)?.imageFromAssetsCar(imageName)
	}
}


// MARK: - Plist

extension AppIcon {
	/// Given a filename, search Bundle or Filesystem for files that match. Select the filename with the highest resolution.
	private func expandImageName(_ iconList: [String]) -> String? {
		var matches: [String] = []
		switch meta.type {
		case .IPA:
			for iconPath in iconList {
				let zipPath = "Payload/*.app/\(iconPath)*"
				for zip in meta.zipFile!.filesMatching(zipPath) {
					if zip.sizeUncompressed > 0 {
						matches.append(zip.filepath)
					}
				}
				if matches.count > 0 {
					break
				}
			}
			
		case .APK:
			return nil // handled in `extractImage()`
			
		case .ClassicMac, .WindowsPE, .Flatpak:
			return nil // l'icona non ha un nome: sta dentro il file
			
		case .Archive, .Extension, .MacApp:
			for iconPath in iconList {
				let fileName = iconPath.components(separatedBy: "/").last!
				let parentDir = meta.effectiveUrl("Resources", iconPath).parentDir().path
				guard let files = try? FileManager.default.contentsOfDirectory(atPath: parentDir) else {
					continue
				}
				for file in files {
					if file.hasPrefix(fileName) {
						let fullPath = parentDir + "/" + file
						if let fSize = try? FileManager.default.attributesOfItem(atPath: fullPath)[FileAttributeKey.size] as? Int {
							if fSize > 0 {
								matches.append(fullPath)
							}
						}
					}
				}
				if matches.count > 0 {
					break
				}
			}
		}
		return matches.isEmpty ? nil : sortedByResolution(matches).first
	}

	/// @return lower index means higher resolution.
	private func resolutionIndex(_ iconName: String) -> Int {
		let lower = iconName.lowercased()
		// "defaultX" = launch image
		let penalty = lower.contains("small") || lower.hasPrefix("default") ? 20 : 0
		
		let resolutionOrder: [String] = [
			"@3x", "180", "167", "152", "@2x", "120",
			"144", "114", "87", "80", "76", "72", "58", "57"
		]
		for (i, res) in resolutionOrder.enumerated() {
			if iconName.contains(res) {
				return i + penalty
			}
		}
		return 50 + penalty
	}
	
	/// Given a list of filenames, order them highest resolution first.
	private func sortedByResolution(_ icons: [String]) -> [String] {
		return icons.sorted { (icon1, icon2) -> Bool in
			let index1 = self.resolutionIndex(icon1)
			let index2 = self.resolutionIndex(icon2)
			return index1 < index2
		}
	}
}


// MARK: - Extension: NSImage

// AppIcon extension
