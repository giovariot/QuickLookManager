import Foundation
import os // OSLog

private let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "de.relikd.QLAppBundleExtended", category: "MetaInfo")

typealias PlistDict = [String: Any] // basically an untyped Dict


// Init QuickLook Type
enum FileType {
	case IPA
	case Archive
	case Extension
	case APK
	/// Programmi e documenti dei vecchi dischi Macintosh. L'icona sta nel fork
	/// di risorse, nei tipi che l'`.icns` di oggi contiene ancora.
	case ClassicMac
	/// Eseguibili Windows. L'icona sta nella sezione risorse del file PE.
	case WindowsPE
	/// Programmi macOS: `.app`, framework, plug-in, estensioni, e i binari
	/// nudi. Quello che l'`Info.plist` non dice — architetture, sistema
	/// minimo, sandbox, notarizzazione — sta nel binario e nella firma.
	case MacApp
	/// Pacchetti Flatpak, cioè applicazioni Linux in un file solo. L'icona ce
	/// l'hanno dentro: due PNG nei metadati, messi lì perché i negozi di
	/// applicazioni possano mostrarla senza scompattare niente.
	case Flatpak
}

struct MetaInfo {
	let UTI: String
	let url: URL
	private let effectiveUrl: URL // if set, will point to the app inside of an archive
	
	let type: FileType
	let zipFile: ZipFile? // only set for zipped file types
	let isOSX: Bool
	/// I framework hanno la forma del 1989 — `Versions/Current/<Nome>`, con le
	/// risorse in `Versions/Current/Resources` — invece di `Contents/MacOS` e
	/// `Contents/Resources`. È l'unica forma diversa, e cambia dove si vanno a
	/// prendere `Info.plist` e binario.
	private let isFramework: Bool
	
	/// Use file url and UTI type to generate an info object to pass around.
	init(_ url: URL) {
		self.url = url
		self.UTI = try! url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier ?? "Unknown"
		
		var isOSX = false
		var isFramework = false
		var effective: URL? = nil
		var zipFile: ZipFile? = nil
		
		// Il confronto va fatto in minuscolo: LaunchServices normalizza gli
		// identificativi di tipo, e a un file `.macapp` risponde
		// `com.giovariot.quicklookmanager.classic-application` -- minuscolo -- mentre
		// qui sotto c'era scritto `QLAppBundle`. Quel `case` non ha mai preso,
		// e un file rinominato finiva dritto nel `fatalError` in fondo: cioe'
		// l'estensione moriva invece di mostrare l'anteprima. Misurato
		// chiedendo il tipo a `resourceValues` su un file vero.
		switch self.UTI.lowercased() {
		case "com.apple.itunes.ipa", "com.opa334.trollstore.tipa", "dyn.ah62d4rv4ge81k4puqe" /* tipa */:
			self.type = FileType.IPA
			zipFile = ZipFile(self.url.path)
		case "com.apple.xcode.archive":
			self.type = FileType.Archive
			let productsDir = url.appendingPathComponent("Products", isDirectory: true)
			if productsDir.exists(), let bundleDir = recursiveSearchInfoPlist(productsDir) {
				isOSX = bundleDir.appendingPathComponent("MacOS").exists() && bundleDir.lastPathComponent == "Contents"
				effective = bundleDir
			} else {
				effective = productsDir // this is wrong but dont use `url` either because that will find the `Info.plist` of the archive itself
			}
		case "com.apple.application-and-system-extension":
			self.type = FileType.Extension
			if let bundleDir = recursiveSearchInfoPlist(url) {
				isOSX = bundleDir.appendingPathComponent("MacOS").exists() && bundleDir.lastPathComponent == "Contents"
				effective = bundleDir
			}
		case "com.google.android.apk", "dyn.ah62d4rv4ge80c6dp" /* apk */, "public.archive.apk", "dyn.ah62d4rv4ge80c6dpry" /* apkm */:
			self.type = FileType.APK
			zipFile = ZipFile(self.url.path)
		case "com.giovariot.quicklookmanager.classic-application", "com.apple.application-file":
			self.type = FileType.ClassicMac
		case "com.microsoft.windows-executable", "com.microsoft.windows-dynamic-link-library":
			self.type = FileType.WindowsPE
		case "com.apple.application-bundle", "com.apple.framework", "com.apple.xpc-service",
		     "com.apple.systempreference.prefpane", "com.apple.system-extension",
		     "com.apple.driver-extension", "com.apple.kernel-extension", "com.apple.plugin",
		     "com.apple.bundle", "com.apple.generic-bundle":
			// Un pacchetto macOS: tutto sta sotto `Contents`, che è la stessa
			// forma che `.Archive` e `.Extension` raggiungono con `isOSX`.
			self.type = FileType.MacApp
			isOSX = true
			let contents = url.appendingPathComponent("Contents", isDirectory: true)
			let versioni = url.appendingPathComponent("Versions/Current", isDirectory: true)
			if contents.exists() {
				effective = contents
			} else if versioni.exists() {
				effective = versioni
				isFramework = true
			} else {
				effective = recursiveSearchInfoPlist(url) ?? url
			}
		case "com.giovariot.quicklookmanager.flatpak-bundle",
		     "dyn.ah62d4rv4ge80q5dbsv2gc42" /* flatpak */:
			// Il tipo dinamico accanto al nostro, come si fa qui sopra per
			// .tipa e .apk: finche' LaunchServices non ha visto la nostra
			// dichiarazione, a un .flatpak assegna quello, e senza il Finder
			// non ci chiederebbe niente.
			self.type = FileType.Flatpak
		case "com.apple.mach-o-dylib", "public.unix-executable":
			// Un binario nudo: `Info.plist` non ne ha, e quello che si può dire
			// viene tutto dalle sue intestazioni e dalla sua firma.
			self.type = FileType.MacApp
			isOSX = true
		default:
			os_log(.error, log: log, "Unsupported file type: %{public}@", self.UTI)
			fatalError()
		}
		self.isOSX = isOSX
		self.isFramework = isFramework
		self.zipFile = zipFile
		self.effectiveUrl = effective ?? url
	}
	
	/// Il pacchetto macOS di cui si possono leggere binario e firma, se c'è.
	///
	/// Non è sempre `url`: dentro un `.xcarchive` il programma sta più in
	/// basso, e la firma che interessa è la sua, non quella dell'archivio. Un
	/// `.appex` di macOS è un pacchetto come gli altri e va trattato uguale —
	/// è il punto di avere un pannello solo.
	var bundleMacOS: URL? {
		switch type {
		case .MacApp:
			return url
		case .Extension, .Archive:
			// `effectiveUrl` qui è la cartella che contiene l'`Info.plist`,
			// cioè `Contents`: il pacchetto è quella sopra.
			return isOSX ? effectiveUrl.deletingLastPathComponent() : nil
		case .IPA, .APK, .ClassicMac, .WindowsPE, .Flatpak:
			return nil
		}
	}
	
	/// Evaluate path with `osxSubdir` and `filename`
	func effectiveUrl(_ osxSubdir: String?, _ filename: String) -> URL {
		switch self.type {
		// Questi due non hanno niente dentro da raggiungere: sono un file solo,
		// e quello che serve sta nei suoi fork o nelle sue sezioni.
		case .ClassicMac, .WindowsPE, .Flatpak:
			return effectiveUrl
		case .IPA, .APK:
			return effectiveUrl
		case .MacApp where isFramework:
			// `Versions/Current/<Nome>` per il binario, `Versions/Current/
			// Resources/<file>` per tutto il resto.
			if osxSubdir == "MacOS" {
				return effectiveUrl.appendingPathComponent(filename, isDirectory: false)
			}
			return effectiveUrl
				.appendingPathComponent("Resources", isDirectory: true)
				.appendingPathComponent(filename, isDirectory: false)
		case .Archive, .Extension, .MacApp:
			if isOSX, let osxSubdir {
				return effectiveUrl
					.appendingPathComponent(osxSubdir, isDirectory: true)
					.appendingPathComponent(filename, isDirectory: false)
			}
			return effectiveUrl.appendingPathComponent(filename, isDirectory: false)
		}
	}
	
	/// Load a file from bundle into memory. Either by file path or via unzip.
	func readPayloadFile(_ filename: String, osxSubdir: String?) -> Data? {
		switch self.type {
		case .IPA:
			return zipFile!.unzipFile("Payload/*.app/".appending(filename))
		case .APK:
			return nil // not applicable for .apk
		case .ClassicMac, .WindowsPE, .Flatpak:
			return nil // non hanno un bundle dentro: sono un file solo
		case .Archive, .Extension, .MacApp:
			return try? Data(contentsOf: self.effectiveUrl(osxSubdir, filename))
		}
	}
}


// MARK: - Plist

extension Data {
	/// Helper for optional chaining.
	func asPlistOrNil() -> PlistDict? {
		if self.isEmpty {
			return nil
		}
		//	var format: PropertyListSerialization.PropertyListFormat = .xml
		do {
			return try PropertyListSerialization.propertyList(from: self, format: nil) as? PlistDict
		} catch {
			os_log(.error, log: log, "ERROR reading plist %{public}@", error.localizedDescription)
			return nil
		}
	}
}


// MARK: - helper methods

/// breadth-first search for `Info.plist`
private func recursiveSearchInfoPlist(_ url: URL) -> URL? {
	var queue: [URL] = [url]
	while !queue.isEmpty {
		let current = queue.removeLast()
		if current.pathExtension == "framework" {
			continue // do not evaluate bundled frameworks
		}
		if let subfiles = try? FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: []) {
			for fname in subfiles {
				if fname.lastPathComponent == "Info.plist" {
					return fname.parentDir()
				}
			}
			queue.append(contentsOf: subfiles)
		}
	}
	return nil
}
