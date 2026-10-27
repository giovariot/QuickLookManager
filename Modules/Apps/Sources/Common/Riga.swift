import Foundation

/// Una riga d'identità del pannello: un'etichetta, un valore, e come si legge
/// quando l'etichetta non c'è.
///
/// Serve perché gli stili del pannello non sono d'accordo su una cosa sola:
/// **dove sta il nome del campo.** Lo stile alla Apparency le etichette non le
/// mette e scrive righe che si leggono da sole — «Versione 3.3 (918)» — mentre
/// lo stile a tabella mette il nome a sinistra e il valore a destra.
///
/// Con due rendering della stessa riga, quale usare lo decide il modello HTML,
/// e chi legge il file non deve sapere niente di come verrà disegnato. Il testo
/// disteso non è sempre «etichetta + valore»: «Type e creator» con «APPL /
/// PNnu» accanto sta bene in tabella, ma da sola quella riga si legge «Type
/// APPL, creator PNnu».
struct Riga {
	/// Il nome del campo, per gli stili che lo mostrano. `nil` per le righe che
	/// un nome non ce l'hanno: una descrizione, un copyright, il peso del file.
	let etichetta: String?
	let valore: String
	/// Come si legge senza etichetta.
	let disteso: String

	init(_ etichetta: String?, _ valore: String, disteso: String? = nil) {
		self.etichetta = etichetta
		self.valore = valore
		self.disteso = disteso ?? [etichetta, valore].compactMap { $0 }.joined(separator: " ")
	}

	/// Una riga senza etichetta, che si legge da sé.
	static func sola(_ testo: String) -> Riga { Riga(nil, testo) }
}
