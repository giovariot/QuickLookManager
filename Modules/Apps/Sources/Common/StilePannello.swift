import Foundation

/// Che aspetto ha il pannello di anteprima.
///
/// Tre stili, tutti e tre con dentro le stesse cose: cambia dove sta il nome
/// del campo e dove sta l'icona.
///
/// - **centrato**: icona grande in cima, nome sotto, campi a tabella. È il
///   predefinito: su un programma del 1992 i campi sono codici di quattro
///   lettere e cifre in byte, e senza l'etichetta davanti non dicono niente.
/// - **apparency**: icona a sinistra e righe che si leggono da sole, come nel
///   pannello di Apparency.
/// - **originale**: il modello di QLAppBundle da cui viene questo fork.
///
/// **Dove vive la scelta.** A leggerla è l'estensione di anteprima, che sta in
/// sandbox; a scriverla è l'applicazione, che sandbox non ne ha. Il posto è
/// `~/Library/Application Support/QLAppBundle/`, e l'estensione ci arriva con
/// un'eccezione di sola lettura dichiarata nei suoi entitlement — la più
/// stretta possibile: una cartella, in lettura.
///
/// L'alternativa sarebbe stata scrivere dentro al contenitore dell'estensione,
/// che l'applicazione tecnicamente può fare. Ma quel contenitore lo crea il
/// sistema la prima volta che l'estensione gira: prima di allora non esiste, e
/// crearlo a mano vorrebbe dire mettersi in mezzo fra il sistema e una cartella
/// che è sua.
enum StilePannello: String, CaseIterable {
	case centrato
	case apparency
	case originale

	/// Come si chiama nel menu.
	var nome: String {
		switch self {
		case .centrato:   return String(localized: "Centrato", bundle: QLMBundle.framework)
		case .apparency:  return String(localized: "Alla Apparency", bundle: QLMBundle.framework)
		case .originale:  return String(localized: "Originale (QLAppBundle)", bundle: QLMBundle.framework)
		}
	}

	/// Una riga che dice cosa cambia, per chi sceglie.
	var descrizione: String {
		switch self {
		case .centrato:   return String(localized: "Icona in cima, campi a tabella con il nome a sinistra", bundle: QLMBundle.framework)
		case .apparency:  return String(localized: "Icona a sinistra, righe che si leggono da sole", bundle: QLMBundle.framework)
		case .originale:  return String(localized: "Il pannello del progetto da cui viene questo fork", bundle: QLMBundle.framework)
		}
	}

	/// Il pezzo che distingue i file del modello: `template-apparency.html`.
	/// Lo stile predefinito non ha suffisso, così i file si chiamano come si
	/// sono sempre chiamati e chi ha già un `template.html` suo continua a
	/// vederlo funzionare.
	var suffisso: String {
		switch self {
		case .centrato:   return ""
		case .apparency:  return "-apparency"
		case .originale:  return "-originale"
		}
	}

	// MARK: - Dove sta scritto

	/// La scelta sta nelle impostazioni del gestore (`QLMSettings.appsPanelStyle`): la scrive l'app, che non è
	/// in sandbox, e la legge l'estensione di anteprima, in sola lettura.
	static var scelto: StilePannello {
		StilePannello(rawValue: QLMSettings.load().appsPanelStyle) ?? .centrato
	}
}
