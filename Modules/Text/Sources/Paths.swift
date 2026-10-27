import Foundation

/// Percorsi condivisi tra app ed estensioni.
///
/// Le estensioni Quick Look girano in sandbox: il loro `NSHomeDirectory()` è il contenitore. La cartella
/// delle impostazioni sta nella home vera ed è letta dalle estensioni grazie all'eccezione
/// `home-relative-path.read-only` dei file `.entitlements` (niente App Group, niente profilo di provisioning).
public enum QTLPaths {
    /// Home dell'utente (non quella del contenitore sandbox).
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/Library/Application Support/QuickLookManager`
    public static var supportDirectory: URL {
        realHome.appendingPathComponent("Library/Application Support/QuickLookManager", isDirectory: true)
    }
    public static var settingsFile: URL { supportDirectory.appendingPathComponent("settings.json") }
    /// Fogli di stile importati dall'utente per il Markdown.
    public static var themesDirectory: URL { supportDirectory.appendingPathComponent("Themes", isDirectory: true) }
    /// Percorso relativo alla home usato nelle eccezioni di sandbox.
    public static let sandboxExceptionPath = "/Library/Application Support/QuickLookManager/"

    /// Risorse web (bundle del framework).
    public static var webResources: URL {
        Bundle(for: BundleToken.self).resourceURL!.appendingPathComponent("Web", isDirectory: true)
    }
    /// Bundle del framework (risorse e stringhe localizzate).
    public static var bundle: Bundle { Bundle(for: BundleToken.self) }
    private final class BundleToken {}
}
