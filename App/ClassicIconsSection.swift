import SwiftUI
import QLMCore

/// «Icone dei vecchi Mac»: l'agente che dà l'icona ai programmi e ai documenti classici, e i due lavori su un disco.
struct ClassicIconsSection: View {
    @StateObject private var service = ClassicIconsService.shared
    @State private var job: Job?
    @State private var message: Message?
    @State private var errorText: String?

    struct Job: Identifiable {
        let id = UUID()
        let title: String
        let cancellation = ClassicIconsService.Cancellation()
        var detail = ""
        var fraction: Double?
    }

    struct Message: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private var agentOn: Binding<Bool> {
        Binding(get: { service.status == .on || service.status == .needsApproval },
                set: { errorText = service.setEnabled($0) })
    }

    var body: some View {
        Section("Icone dei vecchi Mac") {
            Toggle(isOn: agentOn) {
                Text("Dai l'icona ai file dei vecchi Mac")
                Text("Un agente in background guarda i dischi che colleghi e dà l'icona ai programmi e ai documenti classici. Scrive solo sui dischi per cui hai dato il permesso.")
            }
            switch service.status {
            case .needsApproval:
                HStack {
                    Label("In attesa della tua approvazione.", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Apri Login e estensioni…") { ClassicIconsService.openLoginItemsSettings() }
                }
            case .notFound:
                Label("L'agente non è dentro questa copia dell'app.", systemImage: "xmark.circle").foregroundStyle(.secondary)
            default: EmptyView()
            }
            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }
            Toggle(isOn: $service.includeNetworkVolumes) {
                Text("Includi anche i volumi di rete")
                Text("Di solito no: un disco condiviso si legge piano e non è tuo.")
            }
            HStack {
                Button("Dai le icone a un disco…") { chooseVolume(restoring: false) }
                Button("Ripristina un disco…") { chooseVolume(restoring: true) }
            }
        }
        .sheet(item: $job) { job in
            VStack(spacing: 12) {
                Text(job.title).font(.headline)
                if let f = job.fraction { ProgressView(value: f) } else { ProgressView() }
                Text(job.detail).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Button("Ferma") { job.cancellation.cancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: 360)
            .interactiveDismissDisabled()
        }
        .alert(item: $message) { m in
            Alert(title: Text(m.title), message: Text(m.text), dismissButton: .default(Text("OK")))
        }
        .onAppear { service.refresh() }
    }

    // MARK: Scegliere il disco

    private func chooseVolume(restoring: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        panel.message = restoring
            ? String(localized: "Scegli il disco di cui rimettere a posto i fork originali.")
            : String(localized: "Scegli il disco a cui dare le icone dei file classici.")
        panel.prompt = restoring ? String(localized: "Ripristina") : String(localized: "Dai le icone")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let volume = url.resolvingSymlinksInPath()
        restoring ? confirmRestore(volume) : giveIcons(volume)
    }

    // MARK: Dare le icone

    private func giveIcons(_ volume: URL) {
        let name = ClassicIconsService.volumeName(volume)
        guard ClassicIconsService.isWritable(volume) else {
            message = Message(title: String(localized: "Su «\(name)» non si può scrivere."),
                              text: String(localized: "Il disco è di sola lettura, oppure è montato da un driver FUSE: lì l'icona la costruisce già il driver, senza toccare il disco."))
            return
        }
        var j = Job(title: String(localized: "Guardo i file di «\(name)»"))
        j.detail = ""
        job = j
        let token = j.cancellation
        Task {
            let r = await ClassicIconsService.giveIcons(volume: volume, cancellation: token) { looked, written in
                Task { @MainActor in job?.detail = String(localized: "\(looked) file guardati, \(written) con l'icona nuova") }
            }
            job = nil
            message = report(r, name: name)
        }
    }

    private func report(_ r: ClassicIconsService.GiveResult, name: String) -> Message {
        let failures = r.failed == 0 ? "" : "\n\n" + String(localized: "Per \(r.failed) file la scrittura non è riuscita e non sono stati toccati\(r.firstError.map { " (\($0))" } ?? "").")
        if r.written == 0 && r.failed == 0 && !r.cancelled {
            return Message(title: String(localized: "Su «\(name)» non c'era niente da fare."),
                           text: String(localized: "Guardati \(r.looked) file: nessuno è un programma o un documento classico senza icona. I file che ce l'hanno già non si toccano."))
        }
        if r.written == 0 {
            return Message(title: String(localized: "Su «\(name)» nessuna icona è stata scritta."),
                           text: String(localized: "Guardati \(r.looked) file.") + failures)
        }
        let tail = r.cancelled ? String(localized: ", e mi sono fermato perché me l'hai chiesto.")
            : r.truncated ? String(localized: ", e mi sono fermato al tetto di \(r.limit).") : "."
        return Message(title: String(localized: "\(r.written) file di «\(name)» hanno l'icona nuova."),
                       text: String(localized: "Guardati \(r.looked) file") + tail + failures)
    }

    // MARK: Ripristinare

    private func confirmRestore(_ volume: URL) {
        let name = ClassicIconsService.volumeName(volume)
        let count = ClassicIconsService.restorableCount(volume: volume)
        guard count > 0 else {
            message = Message(title: String(localized: "Su «\(name)» non c'è niente da rimettere a posto."),
                              text: String(localized: "Nessun file di questo disco risulta modificato. L'elenco dei fork originali sta nella radice del disco o, se il disco è di sola lettura, nella cartella di supporto dell'app."))
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Rimettere com'erano \(count) file su «\(name)»?")
        alert.informativeText = String(localized: "Il fork di risorse di ogni file torna quello di partenza e l'icona aggiunta sparisce. Un file modificato dopo l'icona non viene toccato: se ne toglie solo il segno dell'icona.")
        alert.addButton(withTitle: String(localized: "Ripristina"))
        alert.addButton(withTitle: String(localized: "Annulla")).keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var j = Job(title: String(localized: "Rimetto a posto i file di «\(name)»"))
        j.fraction = 0
        job = j
        let token = j.cancellation
        Task {
            let r = await ClassicIconsService.restore(volume: volume, cancellation: token) { done, total in
                Task { @MainActor in
                    job?.fraction = total > 0 ? Double(done) / Double(total) : nil
                    job?.detail = String(localized: "\(done) di \(total) file")
                }
            }
            job = nil
            let left = r.left == 0 ? "" : "\n\n" + String(localized: "\(r.left) file erano stati modificati dopo l'icona: il loro contenuto non è stato toccato, è stato tolto solo il segno dell'icona.")
            if r.cancelled {
                message = Message(title: String(localized: "Ripristino fermato su «\(name)»."),
                                  text: String(localized: "\(r.restored) file sono già tornati com'erano; gli altri restano nell'elenco e puoi riprendere quando vuoi.") + left)
            } else if r.failed == 0 {
                message = Message(title: String(localized: "\(r.restored + r.left) file di «\(name)» non hanno più l'icona."),
                                  text: String(localized: "\(r.restored) sono tornati com'erano.") + left)
            } else {
                message = Message(title: String(localized: "Su «\(name)» \(r.failed) file non sono tornati com'erano."),
                                  text: String(localized: "\(r.restored) sì. L'elenco dei fork originali resta dov'è, così si può riprovare.") + left)
            }
        }
    }
}
