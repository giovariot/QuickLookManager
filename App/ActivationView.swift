import SwiftUI
import QLMCore

/// macOS registra le estensioni di un'app quando la scopre, non a ogni apertura: se la registrazione salta, riaprire
/// l'app non la rimette. Per questo, se l'app sta in Applicazioni, a ogni avvio ripassa le sue estensioni al sistema.
enum ExtensionRegistrar {
    /// Le estensioni dentro `Contents/PlugIns`.
    static var embeddedExtensions: [URL] {
        guard let dir = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return items.filter { $0.pathExtension == "appex" }
    }

    /// `true` solo per una copia installata: le build di prova (DerivedData, Download…) non si registrano.
    static var isInstalledCopy: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    @discardableResult
    static func registerIfInstalled() -> Int {
        guard isInstalledCopy else { return 0 }
        let list = embeddedExtensions
        for url in list { run("/usr/bin/pluginkit", ["-a", url.path]) }
        return list.count
    }

    static func reloadQuickLook() {
        run("/usr/bin/qlmanage", ["-r"])
        run("/usr/bin/qlmanage", ["-r", "cache"])
    }

    private static func run(_ tool: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}

struct ActivationView: View {
    @EnvironmentObject var store: ManagerStore

    var body: some View {
        Form {
            Section("Estensioni") {
                Text("Le anteprime e le miniature sono estensioni di Quick Look. Se l'app sta in Applicazioni, macOS le attiva da solo; se vuoi controllare quale estensione ha la precedenza su un tipo di file:")
                Button("Apri Impostazioni di Sistema…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                }
                if !ExtensionRegistrar.isInstalledCopy {
                    Label("Questa copia non è in Applicazioni: le estensioni non vengono registrate.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Se qualcosa non va") {
                Text("Se un'anteprima non cambia dopo un aggiornamento, ricarica Quick Look.")
                Button("Ricarica Quick Look") { ExtensionRegistrar.reloadQuickLook() }
                Toggle("Registra nel log i tempi delle miniature", isOn: $store.value.diagnosticLog)
                Text("Serve a capire dove si perde tempo quando le miniature sono lente. Si legge in Console.app, cercando la categoria «thumbnail» del sottosistema com.giovariot.QuickLookManager.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Altre app con le stesse anteprime") {
                Text("Se sono installati anche QuickTextLook, QLAppBundle, QuickLook Video, Camera RawX o Preview3MF, per gli stessi tipi di file Quick Look ne sceglie una sola. Togli le app che QuickLook Manager sostituisce, o spegni la loro estensione nelle Impostazioni di Sistema.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Attivazione")
    }
}
