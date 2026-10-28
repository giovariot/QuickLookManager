import Foundation

// Sostituto minimo per le prove: i sorgenti del modulo usano `String(localized:bundle: QLMBundle.framework)`.
// Qui il bundle è quello del programma di prova, senza cataloghi, quindi i testi escono nella lingua dei sorgenti (italiano).
enum QLMBundle {
    static let framework = Bundle.main
    static let appsResources = Bundle.main
}

func tr(_ it: String, _ en: String) -> String { it }
