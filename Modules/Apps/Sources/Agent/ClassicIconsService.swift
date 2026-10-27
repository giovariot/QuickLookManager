import AppKit
import ServiceManagement
import os

private let log = OSLog(subsystem: "com.giovariot.QuickLookManager", category: "icone-classiche")

/// Controllo dell'agente che dà l'icona ai file dei vecchi Mac, e dei due lavori che si fanno a mano su un disco:
/// dare le icone e rimettere a posto i fork originali. L'agente (`IconeAgent`) sta dentro l'app e lo registra l'app stessa con
/// `SMAppService`, così macOS lo elenca fra gli elementi in background e l'utente lo spegne quando vuole.
@MainActor
public final class ClassicIconsService: ObservableObject {
    public static let shared = ClassicIconsService()

    public enum Status: Equatable { case off, on, needsApproval, notFound }

    /// Nome del plist in `Contents/Library/LaunchAgents`.
    public static let agentPlist = "com.giovariot.QuickLookManager.IconeAgent.plist"

    @Published public private(set) var status: Status = .off
    @Published public var includeNetworkVolumes: Bool = VolumeClassico.includeVolumiDiRete {
        didSet { if includeNetworkVolumes != oldValue { _ = VolumeClassico.impostaVolumiDiRete(includeNetworkVolumes) } }
    }

    private init() { refresh() }

    private var service: SMAppService { SMAppService.agent(plistName: Self.agentPlist) }

    public func refresh() {
        switch service.status {
        case .enabled: status = .on
        case .requiresApproval: status = .needsApproval
        case .notFound: status = .notFound
        default: status = .off
        }
        includeNetworkVolumes = VolumeClassico.includeVolumiDiRete
    }

    /// Accende o spegne l'agente. Restituisce un messaggio se non ci riesce.
    @discardableResult
    public func setEnabled(_ on: Bool) -> String? {
        defer { refresh() }
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            os_log(.error, log: log, "agente: %{public}@", error.localizedDescription)
            return error.localizedDescription
        }
        return nil
    }

    public static func openLoginItemsSettings() {
        for address in ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
                        "x-apple.systempreferences:com.apple.preferences.users?LoginItems"] {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: Lavori su un disco

    public struct GiveResult: Sendable {
        public var looked = 0, written = 0, failed = 0
        public var firstError: String?
        public var truncated = false, cancelled = false
        public var limit = IconeAutomatiche.tettoPredefinito
    }

    public struct RestoreResult: Sendable {
        public var restored = 0, failed = 0, left = 0
        public var cancelled = false
    }

    /// Un segno che si può alzare da un altro thread.
    public final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        public init() {}
        public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        public func cancel() { lock.lock(); flag = true; lock.unlock() }
    }

    public static func isWritable(_ volume: URL) -> Bool { VolumeClassico.scrivibile(volume) }
    public static func volumeName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
    }

    /// Passa sul disco e dà l'icona ai programmi e ai documenti classici che non ce l'hanno.
    public nonisolated static func giveIcons(volume: URL, cancellation: Cancellation,
                                             progress: @escaping @Sendable (_ looked: Int, _ written: Int) -> Void) async -> GiveResult {
        await Task.detached(priority: .userInitiated) {
            let e = IconeAutomatiche.percorri(volume: volume, fermarsi: { cancellation.isCancelled },
                                              avanzamento: { progress($0.guardati, $0.scritti) })
            return GiveResult(looked: e.guardati, written: e.scritti, failed: e.falliti, firstError: e.primoErrore,
                              truncated: e.troncato, cancelled: e.interrotto)
        }.value
    }

    /// Quanti file di questo disco sono stati modificati e si possono rimettere come erano.
    public static func restorableCount(volume: URL) -> Int { ForkBackup.quanti(sulVolumeDi: volume) }

    public nonisolated static func restore(volume: URL, cancellation: Cancellation,
                                           progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void) async -> RestoreResult {
        await Task.detached(priority: .userInitiated) {
            let e = ClassicIconWriter.restoreAll(onVolume: volume, avanzamento: { progress($0, $1) },
                                                 annullato: { cancellation.isCancelled })
            return RestoreResult(restored: e.fatti, failed: e.falliti, left: e.lasciati, cancelled: e.interrotto)
        }.value
    }
}
