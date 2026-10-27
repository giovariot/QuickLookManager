import Foundation

extension PreviewGenerator {
	/// La sezione della firma: sandbox, hardening, notarizzazione, Gatekeeper.
	///
	/// Sono le righe per cui di solito si apre Apparency, e stanno in fondo e
	/// con le etichette perché sono tante e nessuna si legge da sé: «sì» da
	/// solo non vuol dire niente, «Sandbox sì» sì.
	mutating func procFirma(_ meta: MetaInfo) {
		guard let bundle = meta.bundleMacOS else { return }
		guard let firma = FirmaCodice.leggi(bundle) else {
			// Non firmato affatto, o illeggibile: vale la pena dirlo, perché su
			// un programma scaricato è la cosa più importante del pannello.
			self.apply([
				"FirmaHidden": CLASS_VISIBLE,
				"FirmaRighe": riga(String(localized: "Firma", bundle: QLMBundle.framework), String(localized: "nessuna firma leggibile", bundle: QLMBundle.framework)),
			])
			return
		}

		// Un `.appex` o un framework dentro un'applicazione: il biglietto di
		// notarizzazione ce l'ha il pacchetto di fuori, non lui.
		let annidato = bundle.path.contains("/Contents/")

		let html = MacApp.righeFirma(firma, annidato: annidato)
			.map { riga($0.etichetta, $0.valore, segno: $0.segno) }
			.joined(separator: "\n\t\t")

		self.apply(["FirmaHidden": CLASS_VISIBLE, "FirmaRighe": html])
	}

	/// Una riga con, davanti al valore, il pallino che dice come sta messa:
	/// verde se la cosa c'è ed è quella giusta, grigio se qui non serve, rosso
	/// se manca e dovrebbe esserci. Le righe che non sono un giudizio — chi ha
	/// firmato, l'identificatore — il pallino non ce l'hanno.
	private func riga(_ etichetta: String, _ valore: String,
	                  segno: MacApp.Segno = .nessuno) -> String {
		// Il segno ha una forma oltre al colore (vedi il CSS) e un testo per chi
		// non lo vede: «a posto», «non richiesto», «manca».
		let parola: String
		switch segno {
		case .buono:   parola = String(localized: "a posto", bundle: QLMBundle.framework)
		case .neutro:  parola = String(localized: "non richiesto", bundle: QLMBundle.framework)
		case .grave:   parola = String(localized: "manca", bundle: QLMBundle.framework)
		case .nessuno: parola = ""
		}
		let pallino = segno == .nessuno ? ""
			: "<span class=\"segno \(segno.rawValue)\" role=\"img\" aria-label=\"\(parola)\" title=\"\(parola)\"></span>"
		return "<dt>\(escapeHTML(etichetta))</dt><dd>\(pallino)\(escapeHTML(valore))</dd>"
	}
}

/// Il testo che finisce nell'HTML viene da nomi di certificati e da
/// identificatori scelti da chi ha firmato il programma: contenuto altrui, che
/// nel pannello va mostrato e non interpretato.
func escapeHTML(_ testo: String) -> String {
	testo
		.replacingOccurrences(of: "&", with: "&amp;")
		.replacingOccurrences(of: "<", with: "&lt;")
		.replacingOccurrences(of: ">", with: "&gt;")
		.replacingOccurrences(of: "\"", with: "&quot;")
		.replacingOccurrences(of: "'", with: "&apos;")
}
