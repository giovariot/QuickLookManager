import Foundation

let CLASS_HIDDEN = "hidden"
let CLASS_VISIBLE = ""

struct PreviewGenerator {
	/// Used for TAG replacements
	var data: [String: String] = [
		// default: hide everything
		"AppInfoHidden": CLASS_HIDDEN,
		"RisorseHidden": CLASS_HIDDEN,
		"FirmaHidden": CLASS_HIDDEN,
		"FirmaRighe": "",
		"RisorseElenco": "",
		"Titolo": "",
		"Sommario": "",
		"SommarioRighe": "",
		"NoPlistWarningHidden": CLASS_HIDDEN,
		"AppExtensionTypeHidden": CLASS_HIDDEN,
		"ArchiveHidden": CLASS_HIDDEN,
		"iTunesHidden": CLASS_HIDDEN,
		"TransportSecurityHidden": CLASS_HIDDEN,
		"EntitlementsHidden": CLASS_HIDDEN,
		"EntitlementsConteggio": "",
		"EntitlementsWarningHidden": CLASS_HIDDEN,
		"ProvisionHidden": CLASS_HIDDEN,
		"ApkFeaturesRequiredHidden": CLASS_HIDDEN,
		"ApkFeaturesOptionalHidden": CLASS_HIDDEN,
		"ApkPermissionsHidden": CLASS_HIDDEN,
	]
	let meta: MetaInfo
	
	init(_ meta: MetaInfo) throws {
		self.meta = meta
		
		switch meta.type {
		case .IPA, .Archive, .Extension:
			guard let plistApp = meta.readPlist_Info() else {
				throw RuntimeError("Info.plist not found")
			}
			procAppInfoApple(plistApp)
			if meta.type == .IPA {
				procItunesMeta(meta.readPlist_iTunesMetadata())
			} else if meta.type == .Archive {
				procArchiveInfo(meta.readPlistXCArchive())
			}
			procTransportSecurity(plistApp)
			// Un pacchetto macOS ha una firma da raccontare, che sia
			// un'applicazione, un'estensione o il programma dentro un archivio.
			procFirma(meta)
			
			let plistProvision = meta.readPlist_MobileProvision()
			procEntitlements(meta, plistApp, plistProvision)
			procProvision(plistProvision)
			// App Icon (last, because the image uses a lot of memory)
			data["AppIcon"] = AppIcon(meta).extractImage(from: plistApp.icons).withRoundCorners().asBase64()
			
		case .APK:
			guard let manifest = meta.readApk_Manifest() else {
				throw RuntimeError("AndroidManifest.xml not found")
			}
			procAppInfoAndroid(manifest)
			// App Icon (last, because the image uses a lot of memory)
			data["AppIcon"] = AppIcon(meta).extractImage(from: manifest.icon).withRoundCorners().asBase64()
			
		case .ClassicMac, .WindowsPE, .Flatpak:
			// App Icon (last, because the image uses a lot of memory)
			data["AppIcon"] = AppIcon(meta).extractImageForThumbnail().withRoundCorners().asBase64()
			
		case .MacApp:
			// L'`Info.plist` qui può anche non esserci — un binario nudo non ne
			// ha — e non è un motivo per rinunciare all'anteprima: il binario e
			// la firma parlano lo stesso.
			if let plistApp = meta.readPlist_Info() {
				procAppInfoApple(plistApp)
				procEntitlements(meta, plistApp, nil)
			}
			procFirma(meta)
			// App Icon (last, because the image uses a lot of memory)
			// Niente angoli arrotondati: l'icona di un programma macOS la sua
			// forma ce l'ha già, e ritagliarla di nuovo le mangia i bordi.
			data["AppIcon"] = AppIcon(meta).extractImageForThumbnail().asBase64()
		}
		
		data["QuickLookTitle"] = stringForFileType(meta)
		procFileInfo(meta.url)
		procSommario(meta)
		procFooterInfo()
	}
	
	mutating func apply(_ values: [String: String]) {
		data.merge(values) { (_, new) in new }
	}
	
	/// Title of the preview window
	private func stringForFileType(_ meta: MetaInfo) -> String {
		switch meta.type {
		case .IPA, .APK: return String(localized: "Informazioni sull'app", bundle: QLMBundle.framework)
		case .Archive:   return String(localized: "Informazioni sull'archivio", bundle: QLMBundle.framework)
		case .Extension: return String(localized: "Informazioni sull'estensione", bundle: QLMBundle.framework)
		case .ClassicMac: return String(localized: "File Macintosh classico", bundle: QLMBundle.framework)
		case .WindowsPE: return String(localized: "Eseguibile Windows", bundle: QLMBundle.framework)
		case .MacApp:    return String(localized: "Informazioni sull'app macOS", bundle: QLMBundle.framework)
		case .Flatpak:   return String(localized: "Pacchetto Flatpak", bundle: QLMBundle.framework)
		}
	}
	
	/// I testi fissi dei modelli, nella lingua dell'utente: titoli di sezione,
	/// nomi dei campi, il testo alternativo dell'icona. Nei modelli sono
	/// segnaposto `{{T_…}}` come tutti gli altri; un modello scritto
	/// dall'utente può usarli o ignorarli. Il modello «originale» non li usa:
	/// resta com'era nel progetto da cui viene.
	static var testiFissi: [String: String] {
		[
			"T_Lang": String(localized: "it", bundle: QLMBundle.framework),
			"T_Dir": String(localized: "ltr", bundle: QLMBundle.framework),
			"T_Icona": String(localized: "Icona", bundle: QLMBundle.framework),
			"T_Tipi": String(localized: "Tipi", bundle: QLMBundle.framework),
			"T_NoPlist": String(localized: "Nessun Info.plist trovato", bundle: QLMBundle.framework),
			"T_Firma": String(localized: "Firma", bundle: QLMBundle.framework),
			"T_Risorse": String(localized: "Risorse", bundle: QLMBundle.framework),
			"T_NoteArchivio": String(localized: "Note dell'archivio", bundle: QLMBundle.framework),
			"T_MetadatiITunes": String(localized: "Metadati iTunes", bundle: QLMBundle.framework),
			"T_ITunesId": String(localized: "ID iTunes", bundle: QLMBundle.framework),
			"T_Titolo": String(localized: "Titolo", bundle: QLMBundle.framework),
			"T_Generi": String(localized: "Generi", bundle: QLMBundle.framework),
			"T_Uscita": String(localized: "Uscita", bundle: QLMBundle.framework),
			"T_AppleId": String(localized: "ID Apple", bundle: QLMBundle.framework),
			"T_Acquistato": String(localized: "Acquistato", bundle: QLMBundle.framework),
			"T_Prezzo": String(localized: "Prezzo", bundle: QLMBundle.framework),
			"T_EntitlementsFallito": String(localized: "Lettura degli entitlement non riuscita.", bundle: QLMBundle.framework),
			"T_NomeProfilo": String(localized: "Nome del profilo", bundle: QLMBundle.framework),
			"T_UuidProfilo": String(localized: "UUID del profilo", bundle: QLMBundle.framework),
			"T_TipoProfilo": String(localized: "Tipo di profilo", bundle: QLMBundle.framework),
			"T_DataCreazione": String(localized: "Data di creazione", bundle: QLMBundle.framework),
			"T_DataScadenza": String(localized: "Data di scadenza", bundle: QLMBundle.framework),
			"T_Certificati": String(localized: "Certificati sviluppatore", bundle: QLMBundle.framework),
			"T_Dispositivi": String(localized: "Dispositivi", bundle: QLMBundle.framework),
			"T_FunzioniRichieste": String(localized: "Funzionalità (richieste)", bundle: QLMBundle.framework),
			"T_FunzioniFacoltative": String(localized: "Funzionalità (facoltative)", bundle: QLMBundle.framework),
			"T_Permessi": String(localized: "Permessi", bundle: QLMBundle.framework),
		]
	}

	/// prepare html, replace values
	func generate(template html: String, css: String) -> String {
		let templateValues = data
			.merging(PreviewGenerator.testiFissi) { (_, new) in new }
			.merging(["CSS": css]) { (_, new) in new }
		return html.regexReplace("\\{\\{([^ }]{1,40}?)\\}\\}") { templateValues[$0] }
	}
}

extension String {
	/// Replace regex-pattern with custom replacement.
	/// @param pattern must include a regex group. (e.g. "a(b)c")
	func regexReplace(_ pattern: String, with fn: (_ match: String) -> String?) -> String {
		var rv = ""
		var prevLoc = self.startIndex
		let regex = try! NSRegularExpression(pattern: pattern)
		regex.enumerateMatches(in: self, range: NSRange(location: 0, length: self.count), using: { match, flags, stop  in
			let start = self.index(self.startIndex, offsetBy: match!.range.lowerBound)
			// append unrelated text up to this key
			rv.append(contentsOf: self[prevLoc ..< start])
			prevLoc = self.index(start, offsetBy: match!.range.length)
			// append key if exists (else remove template-key)
			let key = String(self[Range(match!.range(at: 1), in: self)!])
			if let value = fn(key) {
				rv.append(value)
			} else {
				// do not append anything -> removes all template keys from template
				// os_log(.debug, log: log, "unknown template key: %{public}@", key)
			}
		})
		// append remaining text
		rv.append(contentsOf: self[prevLoc ..< self.endIndex])
		return rv
	}
}
