import Foundation

extension PreviewGenerator {
	/// Le righe che stanno sotto il nome, per qualunque tipo di file.
	///
	/// Il riquadro in cima ha sempre la stessa sostanza — icona, nome, poche
	/// righe che dicono cos'è — perché è così che un pannello si riconosce a
	/// colpo d'occhio. Cosa ci finisce dentro cambia col file: un `.ipa` mette
	/// versione e bundle id, un programma del 1992 mette type, creator e le due
	/// metà del suo fork, un `.app` di oggi mette architetture e firma.
	///
	/// **Come** si vedono quelle righe lo decide invece lo stile scelto, e per
	/// questo se ne preparano due forme: distese («Versione 3.3 (918)»), che è
	/// come le scrive Apparency, e a tabella (etichetta a sinistra, valore a
	/// destra). Il modello HTML prende quella che gli serve; qui non si sa nulla
	/// di come verrà disegnato.
	mutating func procSommario(_ meta: MetaInfo) {
		var righe: [Riga] = []

		// L'`Info.plist` di un programma macOS serve due volte — per dire che
		// cos'è e per il copyright — e si legge una volta sola.
		let bundleMac = meta.bundleMacOS
		let plistMac = bundleMac != nil ? meta.plistGrezzo() : nil

		func aggiungi(_ riga: Riga?) {
			guard let riga, !riga.valore.trimmingCharacters(in: .whitespaces).isEmpty else { return }
			righe.append(riga)
		}
		func aggiungiSola(_ testo: String?) {
			guard let testo, !testo.trimmingCharacters(in: .whitespaces).isEmpty else { return }
			righe.append(.sola(testo))
		}
		func campo(_ chiave: String) -> String? {
			data[chiave].flatMap { $0.isEmpty ? nil : $0 }
		}

		let titolo: String
		switch meta.type {
		case .IPA, .Archive, .Extension, .APK, .MacApp:
			titolo = campo("AppName") ?? meta.url.lastPathComponent
			aggiungiSola(descrizione(meta, plistMac))
			if let v = campo("AppVersion") {
				let build = data["AppBuildVer"] ?? ""
				aggiungi(Riga(String(localized: "Versione", bundle: QLMBundle.framework), build.isEmpty ? v : "\(v) (\(build))"))
			}
			aggiungi(campo("AppId").map { Riga(String(localized: "Identificatore", bundle: QLMBundle.framework), $0) })
			aggiungi(campo("AppExtensionType").map {
				Riga(String(localized: "Tipo di estensione", bundle: QLMBundle.framework), $0,
				         disteso: String(localized: "Estensione \($0)", bundle: QLMBundle.framework))
			})
			if let bundleMac {
				// Architetture, sistema minimo e copyright: vengono dal binario
				// e non dall'`Info.plist`, che il minimo lo dichiara solo
				// quando l'autore se n'è ricordato.
				for riga in MacApp.righe(url: bundleMac, uti: meta.UTI, plist: plistMac) {
					aggiungi(riga)
				}
			} else {
				// Per un programma macOS queste sarebbero righe già dette: la
				// piattaforma sta nel genere e nelle architetture, e l'SDK è una
				// cosa di chi compila, non di chi apre il pannello.
				aggiungi(campo("AppDeviceFamily").map { Riga(String(localized: "Dispositivi", bundle: QLMBundle.framework), $0) })
				aggiungi(campo("AppSDK").map { Riga("SDK", $0) })
				aggiungi(campo("AppMinOS").map { Riga(String(localized: "Richiede", bundle: QLMBundle.framework), $0) })
			}

		case .ClassicMac, .WindowsPE:
			titolo = meta.url.lastPathComponent
			aggiungiSola(descrizione(meta, nil))
			for riga in ClassicSupport.summaryLines(for: meta) { aggiungi(riga) }

		case .Flatpak:
			let info = FlatpakBundle.leggi(meta.url)
			// Il nome vero sta nel file `metadata` del pacchetto; il nome del
			// file è quello che ha scelto chi l'ha scaricato.
			titolo = FlatpakBundle.campo("name", in: info?.metadata)
				?? meta.url.deletingPathExtension().lastPathComponent
			aggiungiSola(descrizione(meta, nil))
			for riga in info.map(FlatpakBundle.righe) ?? [] { aggiungi(riga) }
		}

		// L'ultima riga è sempre questa, come in Apparency: quanto pesa e
		// quand'è stato toccato l'ultima volta.
		let peso = data["FileSize"] ?? ""
		let quando = data["FileModified"] ?? ""
		if !peso.isEmpty || !quando.isEmpty {
			aggiungi(Riga("File", [peso, quando.isEmpty ? nil : String(localized: "modificato \(quando)", bundle: QLMBundle.framework)]
				.compactMap { $0 }.joined(separator: ", ")))
		}

		self.apply([
			"Titolo": escapeHTML(titolo),
			"Sommario": distese(righe),
			"SommarioRighe": tabella(righe),
		])

		// L'elenco dei tipi di risorsa è lungo mezza pagina: sta in una sezione
		// sua, non fra le righe di identità.
		let tipi = ClassicSupport.resourceTypes(for: meta)
		if !tipi.isEmpty {
			self.apply(["RisorseHidden": CLASS_VISIBLE,
			            "RisorseElenco": escapeHTML(tipi.joined(separator: " "))])
		}
	}

	/// Le righe come le scrive Apparency: una sotto l'altra, senza etichette.
	private func distese(_ righe: [Riga]) -> String {
		righe
			.flatMap { $0.disteso.components(separatedBy: "\n") }
			.map { escapeHTML($0) }
			.joined(separator: "<br />\n\t\t\t")
	}

	/// Le stesse righe a tabella: il nome del campo a sinistra, il valore a
	/// destra. Una riga senza etichetta prende tutta la larghezza, perché è una
	/// frase e non un campo.
	private func tabella(_ righe: [Riga]) -> String {
		righe.map { riga in
			guard let etichetta = riga.etichetta else {
				return "<dt class=\"sola\"></dt><dd class=\"sola\">\(escapeHTML(riga.valore))</dd>"
			}
			return "<dt>\(escapeHTML(etichetta))</dt><dd>\(escapeHTML(riga.valore))</dd>"
		}.joined(separator: "\n\t\t\t")
	}

	/// Che cos'è questo file, in una riga.
	private func descrizione(_ meta: MetaInfo, _ plistMac: PlistDict?) -> String {
		switch meta.type {
		// Prima degli altri: un'estensione di macOS è un pacchetto macOS, e
		// dire «estensione QuickLook» è più preciso che «estensione di
		// applicazione».
		case .Extension where meta.isOSX:
			return MacApp.genere(uti: meta.UTI, plist: plistMac)
		case .MacApp:     return MacApp.genere(uti: meta.UTI, plist: plistMac)
		case .IPA:        return String(localized: "Applicazione iOS", bundle: QLMBundle.framework)
		case .Archive:    return String(localized: "Archivio Xcode", bundle: QLMBundle.framework)
		case .Extension:  return String(localized: "Estensione di applicazione", bundle: QLMBundle.framework)
		case .APK:        return String(localized: "Applicazione Android", bundle: QLMBundle.framework)
		case .WindowsPE:  return String(localized: "Eseguibile Windows", bundle: QLMBundle.framework)
		case .Flatpak:    return String(localized: "Applicazione Linux (Flatpak)", bundle: QLMBundle.framework)
		case .ClassicMac:
			return ClassicIcon.isApplication(ClassicIcon.fileType(of: meta.url))
				? String(localized: "Applicazione Macintosh classica", bundle: QLMBundle.framework)
				: String(localized: "Documento Macintosh classico", bundle: QLMBundle.framework)
		}
	}
}
