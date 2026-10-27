import SwiftUI
import QuickLookUI
import QLMCore

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: ManagerStore

    var body: some View {
        NavigationSplitView {
            List(selection: $state.pane) {
                Label {
                    Text("Prova un file")
                } icon: {
                    SidebarIcon(name: "eye")
                }
                .tag(AppState.Pane.try_)

                Section("Moduli") {
                    ForEach(QLMModule.allCases) { module in
                        ModuleRow(module: module)
                            .tag(AppState.Pane.module(module))
                    }
                }

                Section("Sistema") {
                    Label {
                        Text("Attivazione")
                    } icon: {
                        SidebarIcon(name: "puzzlepiece.extension")
                    }
                    .tag(AppState.Pane.activation)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            switch state.pane ?? .try_ {
            case .try_: TryFileView()
            case .module(let m): ModuleDetailView(module: m)
            case .activation: ActivationView()
            }
        }
    }
}

/// Icone in un riquadro di larghezza fissa: simboli di larghezza diversa restano incolonnati.
struct SidebarIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 20, height: 20, alignment: .center)
    }
}

/// Una riga della barra laterale: il modulo e l'interruttore che lo accende o lo spegne.
struct ModuleRow: View {
    let module: QLMModule
    @EnvironmentObject var store: ManagerStore

    private var enabled: Binding<Bool> {
        Binding(get: { store.value.isEnabled(module) },
                set: { store.value.setEnabled($0, for: module) })
    }

    var body: some View {
        HStack {
            Label {
                Text(module.title)
            } icon: {
                SidebarIcon(name: module.symbol)
            }
            .foregroundStyle(module.isImplemented ? .primary : .secondary)
            Spacer()
            Toggle("Attiva \(module.title)", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!module.isImplemented)
        }
        .contextMenu {
            Toggle(isOn: enabled) { Text("Attivo") }
                .disabled(!module.isImplemented)
        }
    }
}

// MARK: Prova un file

struct TryFileView: View {
    @EnvironmentObject var state: AppState
    @State private var targeted = false

    var body: some View {
        Group {
            if let url = state.url {
                QuickLookPreview(url: url)
            } else {
                ContentUnavailableView {
                    Label("Trascina un file qui", systemImage: "square.and.arrow.down")
                } description: {
                    Text("Vedrai l'anteprima di Quick Look: se QuickLook Manager è attivo, è quella dei suoi moduli.")
                } actions: {
                    Button("Scegli un file…") { state.importing = true }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if targeted { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3).padding(4) } }
        .dropDestination(for: URL.self) { urls, _ in state.url = urls.first; return urls.first != nil } isTargeted: { targeted = $0 }
        .fileImporter(isPresented: $state.importing, allowedContentTypes: [.item]) { result in
            if case .success(let u) = result { state.url = u }
        }
        .toolbar {
            ToolbarItem {
                Button("Scegli file", systemImage: "folder") { state.importing = true }
            }
        }
        .navigationTitle(state.url?.lastPathComponent ?? String(localized: "Prova un file"))
    }
}

struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.previewItem = url as NSURL
        return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != url { v.previewItem = url as NSURL }
    }
}
