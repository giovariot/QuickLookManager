import SwiftUI
import QLMCore

struct TextFormatsView: View {
    var body: some View {
        Group {
            ForEach(FormatCatalog.groups) { g in
                Section {
                    if let note = g.note { Text(note).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estensioni").font(.subheadline).foregroundStyle(.secondary)
                        FlowLayout(spacing: 10) {
                            ForEach(g.extensions, id: \.self) { Text("." + $0).font(.callout.monospaced()) }
                        }
                    }
                    if !g.fileNames.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nomi di file").font(.subheadline).foregroundStyle(.secondary)
                            FlowLayout(spacing: 10) {
                                ForEach(g.fileNames, id: \.self) { Text($0).font(.callout.monospaced()) }
                            }
                        }
                    }
                } header: { Text(g.title) }
            }
        }
            }
}

