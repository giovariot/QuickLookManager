import SwiftUI
import QLMCore

@main
struct QuickLookManagerApp: App {
    @StateObject private var store = ManagerStore()
    @StateObject private var textStore = TextSettingsStore()
    @StateObject private var state = AppState()

    init() {
        #if DEBUG
        DebugTools.runIfRequested()
        #endif
        ExtensionRegistrar.registerIfInstalled()
    }

    var body: some Scene {
        Window("QuickLook Manager", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(textStore)
                .environmentObject(state)
                .frame(minWidth: 760, minHeight: 500)
        }
        .defaultSize(width: 940, height: 640)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Apri…") { state.requestOpen() }
                    .keyboardShortcut("o")
            }
        }
    }
}

/// Impostazioni del gestore (moduli attivi, stile dei pannelli): ogni modifica va subito su disco, dove la leggono le estensioni.
@MainActor
final class ManagerStore: ObservableObject {
    @Published var value = QLMSettings.load() {
        didSet { if value != oldValue { value.save() } }
    }
}

/// Impostazioni del modulo «Testo e codice» (le stesse di QuickTextLook).
@MainActor
final class TextSettingsStore: ObservableObject {
    @Published var value = QTLSettings.load() {
        didSet { if value != oldValue { value.save() } }
    }
}

/// Stato condiviso tra il menu File e la vista di prova.
@MainActor
final class AppState: ObservableObject {
    enum Pane: Hashable { case try_, module(QLMModule), activation }
    @Published var pane: Pane? = {
        #if DEBUG
        if let p = DebugTools.initialPane { return p }
        #endif
        return .try_
    }()
    @Published var url: URL?
    @Published var importing = false
    func requestOpen() { pane = .try_; importing = true }
}
