import SwiftUI
import QLMCore
import UniformTypeIdentifiers

private let sizeChoices: [Int] = [256, 1024, 2048, 5120, 10240]
private func sizeLabel(_ kb: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(kb) * 1024, countStyle: .file) }

struct CodeSettingsView: View {
    @EnvironmentObject var store: TextSettingsStore
    var body: some View {
        Group {
            Section("Visualizzazione") {
                Toggle("Numeri di riga", isOn: $store.value.code.lineNumbers)
                Toggle("Vai a capo automaticamente", isOn: $store.value.code.wrapLines)
                Stepper("Dimensione del carattere: \(Int(store.value.code.fontSize)) pt", value: $store.value.code.fontSize, in: 9...24)
                Picker("Larghezza della tabulazione", selection: $store.value.code.tabWidth) {
                    ForEach([2, 4, 8], id: \.self) { Text("\($0) spazi").tag($0) }
                }
            }
            Section("Linguaggio") {
                Toggle("Riconosci il linguaggio dal contenuto", isOn: $store.value.code.autoDetectLanguage)
                Text("Usato quando l'estensione non indica un linguaggio noto.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Limiti") {
                Picker("Dimensione massima evidenziata", selection: $store.value.code.maxKilobytes) {
                    ForEach(sizeChoices, id: \.self) { Text(sizeLabel($0)).tag($0) }
                }
            }
        }
    }
}

struct DataSettingsView: View {
    @EnvironmentObject var store: TextSettingsStore
    var body: some View {
        Group {
            Section("All'apertura") {
                Picker("Mostra", selection: $store.value.data.startMode) {
                    Text("Struttura").tag(QTLSettings.DataFormats.Mode.tree)
                    Text("Sorgente").tag(QTLSettings.DataFormats.Mode.source)
                }
                .pickerStyle(.segmented)
                Stepper("Livelli espansi: \(store.value.data.expandLevels)", value: $store.value.data.expandLevels, in: 0...6)
                Toggle("Mostra la colonna «Tipo»", isOn: $store.value.data.showTypes)
                Toggle("Property list: mostra la struttura", isOn: $store.value.data.plistAsTree)
            }
            Section("Limiti") {
                Picker("Dimensione massima letta", selection: $store.value.data.maxKilobytes) {
                    ForEach(sizeChoices, id: \.self) { Text(sizeLabel($0)).tag($0) }
                }
            }
            Section {
                Text("Il sorgente usa le impostazioni di carattere e numeri di riga della scheda Codice.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct TextSettingsView: View {
    @EnvironmentObject var store: TextSettingsStore
    var body: some View {
        Group {
            Section("Visualizzazione") {
                Picker("Carattere", selection: $store.value.text.fontStyle) {
                    Text("A spaziatura fissa").tag(QTLSettings.Text.FontStyle.monospaced)
                    Text("Proporzionale").tag(QTLSettings.Text.FontStyle.proportional)
                }
                Stepper("Dimensione: \(Int(store.value.text.fontSize)) pt", value: $store.value.text.fontSize, in: 9...24)
                Toggle("Vai a capo automaticamente", isOn: $store.value.text.wrapLines)
                Toggle("Numeri di riga", isOn: $store.value.text.lineNumbers)
            }
            Section("Codifica") {
                Picker("Codifica", selection: $store.value.text.encoding) {
                    Text("Automatica").tag("auto")
                    ForEach(TextDecoding.namedEncodings, id: \.name) { Text($0.label).tag($0.name) }
                }
                Toggle("Leggi .nfo, .diz e simili come DOS (CP437)", isOn: $store.value.text.legacyDOSEncoding)
            }
            Section("Limiti") {
                Picker("Dimensione massima letta", selection: $store.value.text.maxKilobytes) {
                    ForEach(sizeChoices, id: \.self) { Text(sizeLabel($0)).tag($0) }
                }
            }
        }
    }
}

struct MarkdownSettingsView: View {
    @EnvironmentObject var store: TextSettingsStore
    @State private var importing = false
    @State private var customThemes = MarkupWebView.customThemes()
    @State private var importError: String?

    var body: some View {
        Group {
            Section("Dialetto") {
                Picker("Markdown", selection: $store.value.markdown.flavor) {
                    Text("Typora (tutte le estensioni)").tag("typora")
                    Text("GitHub (GFM)").tag("gfm")
                    Text("CommonMark").tag("commonmark")
                    Text("MultiMarkdown").tag("multimarkdown")
                }
                Toggle("Formule matematiche (KaTeX)", isOn: $store.value.markdown.math)
                Toggle("Diagrammi (Mermaid)", isOn: $store.value.markdown.diagrams)
                Toggle("Mostra anche Textile, AsciiDoc, Creole, reStructuredText e BBCode", isOn: $store.value.markdown.renderOtherMarkup)
            }
            Section("Tema") {
                Picker("Stile", selection: $store.value.markdown.theme) {
                    ForEach(MarkupWebView.builtInThemes, id: \.id) { Text($0.label).tag($0.id) }
                    if !customThemes.isEmpty {
                        Divider()
                        ForEach(customThemes, id: \.self) { Text($0).tag("custom:" + $0) }
                    }
                }
                HStack {
                    Button("Importa CSS…") { importing = true }
                    Button("Mostra cartella dei temi") {
                        try? FileManager.default.createDirectory(at: QTLPaths.themesDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(QTLPaths.themesDirectory)
                    }
                }
                if let importError { Text(importError).foregroundStyle(.red).font(.callout) }
                Text("Sono compatibili i temi di Typora e qualunque CSS che usi #write o .markdown-body. Il tema scelto si applica sopra la base di sistema.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Testo") {
                Stepper("Dimensione: \(Int(store.value.markdown.fontSize)) pt", value: $store.value.markdown.fontSize, in: 10...28)
                Picker("Larghezza massima", selection: $store.value.markdown.maxWidth) {
                    Text("Tutta la finestra").tag(0.0)
                    Text("Stretta (680 pt)").tag(680.0)
                    Text("Media (860 pt)").tag(860.0)
                    Text("Ampia (1100 pt)").tag(1100.0)
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "css") ?? .plainText], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importCSS(urls)
        }
    }

    private func importCSS(_ urls: [URL]) {
        importError = nil
        do {
            try FileManager.default.createDirectory(at: QTLPaths.themesDirectory, withIntermediateDirectories: true)
            for u in urls {
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                let dest = QTLPaths.themesDirectory.appendingPathComponent(u.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: u, to: dest)
            }
            customThemes = MarkupWebView.customThemes()
            if let last = urls.last { store.value.markdown.theme = "custom:" + last.lastPathComponent }
        } catch {
            importError = error.localizedDescription
        }
    }
}
