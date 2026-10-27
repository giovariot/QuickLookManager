import Foundation

/// Bundle del framework e dei suoi gruppi di risorse.
public enum QLMBundle {
    private final class Token {}
    public static var framework: Bundle { Bundle(for: Token.self) }

    /// Modelli HTML, fogli di stile e icona predefinita del modulo «App e pacchetti».
    static var appsResources: Bundle {
        Bundle(url: framework.resourceURL!.appendingPathComponent("AppsResources", isDirectory: true)) ?? framework
    }

    /// `Info.plist` dell'app o dell'estensione che sta ospitando il framework (versione, build).
    static var hostInfo: [String: Any]? { Bundle.main.infoDictionary }
}
