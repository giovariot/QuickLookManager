import SwiftUI
import QLMCore

/// Pagina di un modulo: interruttore, impostazioni e formati.
struct ModuleDetailView: View {
    let module: QLMModule
    @EnvironmentObject var store: ManagerStore

    private var enabled: Binding<Bool> {
        Binding(get: { store.value.isEnabled(module) },
                set: { store.value.setEnabled($0, for: module) })
    }

    var body: some View {
        Group {
            if module.isImplemented {
                Form {
                    Section {
                        Toggle(isOn: enabled) {
                            Text("Attivo")
                            Text(module.summary)
                        }
                    }
                    if enabled.wrappedValue {
                        switch module {
                        case .text: TextModuleSettings()
                        case .apps: AppsModuleSettings()
                        case .raw: RawModuleSettings()
                        case .eps: EPSModuleSettings()
                        case .archives: ArchivesModuleSettings()
                        case .models: ModelsModuleInfo()
                        case .video: VideoModuleSettings()
                        case .pkg: PkgModuleInfo()
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView {
                    Label(module.title, systemImage: module.symbol)
                } description: {
                    Text(module.summary)
                    Text("Non ancora disponibile.")
                }
            }
        }
        .navigationTitle(module.title)
    }
}

// MARK: Testo e codice

private enum TextTab: String, CaseIterable, Identifiable {
    case code, data, text, markdown, formats
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .code: "Codice"
        case .data: "JSON e YAML"
        case .text: "Testo"
        case .markdown: "Markdown"
        case .formats: "Formati"
        }
    }
}

struct TextModuleSettings: View {
    @State private var tab = TextTab.code

    var body: some View {
        Section {
            Picker("Impostazioni", selection: $tab) {
                ForEach(TextTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        switch tab {
        case .code: CodeSettingsView()
        case .data: DataSettingsView()
        case .text: TextSettingsView()
        case .markdown: MarkdownSettingsView()
        case .formats: TextFormatsView()
        }
    }
}

// MARK: App e pacchetti

struct AppsModuleSettings: View {
    @EnvironmentObject var store: ManagerStore

    private let styles: [(id: String, title: LocalizedStringKey, detail: String)] = [
        ("centrato", "Centrato", "Icona in cima, campi a tabella con il nome a sinistra"),
        ("apparency", "Stile Apparency", "Icona a sinistra, righe che si leggono da sole"),
        ("originale", "Originale (QLAppBundle)", "Il pannello del progetto da cui viene questo modulo"),
    ]
    private let formats: [(title: LocalizedStringKey, detail: String)] = [
        ("App macOS", String(localized: ".app, framework, plug-in, estensioni, binari Mach-O: architetture, sistema minimo, firma, entitlement, notarizzazione")),
        ("App iOS", String(localized: ".ipa, .tipa, .xcarchive: profilo di provisioning, entitlement, App Transport Security")),
        ("App Android", String(localized: ".apk, .apkm: permessi, funzionalità, versione dell'SDK")),
        ("Altri formati", String(localized: ".exe e .dll di Windows, pacchetti .flatpak, programmi e documenti dei vecchi Mac")),
    ]

    var body: some View {
        Section("Aspetto del pannello") {
            Picker("Stile", selection: $store.value.appsPanelStyle) {
                ForEach(styles, id: \.id) { Text($0.title).tag($0.id) }
            }
            if let current = styles.first(where: { $0.id == store.value.appsPanelStyle }) {
                Text(current.detail).font(.callout).foregroundStyle(.secondary)
            }
        }
        ClassicIconsSection()
        Section("Formati supportati") {
            ForEach(Array(formats.enumerated()), id: \.offset) { _, f in
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                    Text(verbatim: f.detail).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Foto RAW

struct RawModuleSettings: View {
    @EnvironmentObject var store: ManagerStore

    var body: some View {
        Section("Anteprima") {
            Toggle("Mostra i dati di scatto sotto la foto", isOn: $store.value.raw.showInfo)
            Toggle("Sviluppa il RAW se non ha un'anteprima incorporata", isOn: $store.value.raw.renderIfMissing)
            Text("Quasi tutte le fotocamere salvano nel RAW un JPEG grande: è quello che si vede, ed è immediato. Lo sviluppo a mezza risoluzione è più lento e serve solo ai file che non lo hanno.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Formati supportati") {
            Text("Canon (CR2, CR3, CRW), Nikon (NEF, NRW), Sony (ARW, SR2), Fujifilm (RAF), Olympus (ORF), Panasonic (RW2), Pentax, Leica, Hasselblad, Phase One, Samsung, Adobe DNG e altri. Letti con LibRaw, incorporata nell'app.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: EPS

struct EPSModuleSettings: View {
    @EnvironmentObject var store: ManagerStore

    var body: some View {
        Section("Anteprima") {
            Toggle("Preferisci l'anteprima incorporata nel file", isOn: $store.value.eps.preferEmbeddedPreview)
            Picker("Risoluzione di resa", selection: $store.value.eps.resolution) {
                ForEach([72, 144, 216, 300], id: \.self) { Text("\($0) dpi").tag($0) }
            }
            .disabled(!GhostscriptRenderer.isAvailable)
        }
        Section("Ghostscript") {
            if GhostscriptRenderer.isAvailable {
                Label("Incorporato nell'app", systemImage: "checkmark.circle")
                Text("I file EPS senza anteprima, o quando la preferenza qui sopra è spenta, vengono resi da Ghostscript.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Label("Non incluso in questa versione dell'app", systemImage: "exclamationmark.triangle")
                Text("Si vedono solo i file EPS con un'anteprima incorporata (TIFF o bitmap), come quelli di Illustrator o InDesign. Compilando Ghostscript con scripts/vendor-ghostscript.sh e ricostruendo l'app, viene incorporato.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Archivi

struct ArchivesModuleSettings: View {
    @EnvironmentObject var store: ManagerStore

    var body: some View {
        Section("Elenco") {
            Picker("Voci mostrate al massimo", selection: $store.value.archives.maxEntries) {
                ForEach([1000, 5000, 20000, 100000], id: \.self) { Text($0.formatted()).tag($0) }
            }
            Text("Gli archivi più grandi mostrano le prime voci e il totale.").font(.callout).foregroundStyle(.secondary)
        }
        Section("Formati supportati") {
            Text("ZIP, 7z, RAR, tar (anche gz, bz2, xz, lzma, zst), cpio, CAB, LHA, ISO, XAR, RPM e DEB. Letti con la libarchive di macOS: i file con password mostrano i nomi solo se il formato lo permette.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: Modelli 3D

struct ModelsModuleInfo: View {
    var body: some View {
        Section("Formati supportati") {
            Text("File 3MF (Bambu Studio, OrcaSlicer, PrusaSlicer, Cura e altri): anteprima 3D che si può ruotare e ingrandire, con le piastre di stampa. Le miniature usano l'immagine incorporata dal programma, se c'è.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Basato su Preview3MF di Cavan O'Connor (MIT).").font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: Video

struct VideoModuleSettings: View {
    @EnvironmentObject var store: ManagerStore

    var body: some View {
        Section("Riproduzione") {
            Toggle("Avvia il filmato all'apertura", isOn: $store.value.video.autoplay)
            Text("Il filmato si ferma da solo quando chiudi la finestra di Quick Look o passi a un altro file.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Miniature") {
            Picker("Punto del filmato", selection: $store.value.video.thumbnailFraction) {
                ForEach([0.1, 0.25, 0.5], id: \.self) { Text($0, format: .percent).tag($0) }
            }
        }
        Section("Formati supportati") {
            Text("MKV, WebM, AVI, WMV e ASF, FLV, OGV, M2TS, VOB, RealMedia, DivX, MXF e altri letti da ffmpeg, con VideoToolbox quando il codec lo permette. MP4, MOV e M4V restano a macOS.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Basato su QLVideo di Jonathan Harris (GPL 2 o successiva) per le versioni di ffmpeg e le patch.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: Pacchetti PKG

struct PkgModuleInfo: View {
    var body: some View {
        Section("Cosa mostra") {
            Text("In alto: titolo, identificatore, versione, dove si installa, numero di file e spazio occupato, architetture e macOS richiesto, script, riavvio e firma. In basso: l'albero dei file che il pacchetto installa, con permessi e dimensioni, e i suoi script.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Limiti") {
            Text("Funziona con i pacchetti «flat» (.pkg, .mpkg). L'elenco dei file viene dal file Bom, senza scompattare il contenuto: per questo è immediato anche con pacchetti da gigabyte. Della firma si mostrano i certificati e se la catena è valida; la verifica crittografica del contenuto e la notarizzazione non sono controllate.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
