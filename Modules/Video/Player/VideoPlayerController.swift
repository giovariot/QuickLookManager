import AVFoundation
import Combine
import os
import QLMNative

private let log = Logger(subsystem: "com.giovariot.QuickLookManager", category: "video")

/// Uscita audio: nella sandbox delle anteprime di Quick Look `AVSampleBufferAudioRenderer` non esiste (il suo inizializzatore
/// restituisce nil: verificato), ma `AVAudioEngine` parte. L'audio si suona quindi con un `AVAudioPlayerNode` e fa da orologio
/// per il video.
private final class AudioOutput: @unchecked Sendable {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    /// Il formato standard di AVAudioEngine (float 32 bit, canali separati). Il mixer non accetta un formato interleaved: collegarlo così lancia
    /// un'eccezione (visto nel registro di arresto). `QLMMediaReader` produce campioni interleaved, che `schedule` separa.
    let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private let state = OSAllocatedUnfairLock(initialState: (queuedFrames: 0, base: 0.0, hasBase: false))

    init() throws {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    /// Secondi di audio già consegnati al lettore e non ancora suonati.
    var queuedSeconds: Double { Double(state.withLock { $0.queuedFrames }) / 48000 }
    var hasBase: Bool { state.withLock { $0.hasBase } }
    /// Il tempo del filmato del primo campione consegnato dopo l'ultimo reset.
    var mediaBase: Double? { state.withLock { $0.hasBase ? $0.base : nil } }

    /// Il tempo del filmato che sta suonando adesso, se l'audio gira.
    var mediaTime: Double? {
        guard player.isPlaying, let node = player.lastRenderTime, let t = player.playerTime(forNodeTime: node), t.sampleTime >= 0 else { return nil }
        let base = state.withLock { $0.base }
        return base + Double(t.sampleTime) / t.sampleRate
    }

    func schedule(_ sample: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return }
        let count = Int(frames)
        let bytes = count * 2 * MemoryLayout<Float>.size
        guard CMBlockBufferGetDataLength(block) >= bytes else { return }
        var interleaved = [Float](repeating: 0, count: count * 2)
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: &interleaved) == noErr else { return }
        let left = channels[0], right = channels[1]
        for i in 0..<count { left[i] = interleaved[2 * i]; right[i] = interleaved[2 * i + 1] }
        buffer.frameLength = frames
        state.withLock {
            if !$0.hasBase { $0.base = CMSampleBufferGetPresentationTimeStamp(sample).seconds; $0.hasBase = true }
            $0.queuedFrames += Int(frames)
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.state.withLock { $0.queuedFrames -= Int(frames) }
        }
    }

    /// Dopo un salto: il lettore perde ciò che aveva in coda e la prima nuova consegna fissa l'origine dei tempi.
    func reset() {
        player.stop()
        state.withLock { $0 = (0, 0, false) }
    }

    func shutdown() {
        player.stop()
        engine.stop()
    }
}

/// Il lettore: ffmpeg decodifica (`QLMMediaReader`), AVFoundation mostra i fotogrammi e `AVAudioEngine` suona l'audio.
/// L'audio è l'orologio: `AVSampleBufferRenderSynchronizer` guida il video e viene riallineato se si scosta.
@MainActor
final class VideoPlayerController: NSObject, ObservableObject {
    let reader: QLMMediaReader
    let displayLayer = AVSampleBufferDisplayLayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double
    @Published private(set) var isFinished = false
    @Published var volume: Float = 1 { didSet { applyVolume(); if volume > 0 { isMuted = false } } }
    @Published var isMuted = false { didSet { applyVolume() } }

    var hasVideo: Bool { reader.hasVideo }
    /// `true` se c'è una traccia audio e l'uscita audio è partita.
    let hasAudio: Bool
    var title: String? { reader.title }
    var details: String {   // letto dopo il primo fotogramma, quando si sa se VideoToolbox lavora davvero
        [reader.videoCodec.map { $0.uppercased() }, reader.audioCodec.map { $0.uppercased() },
         reader.usesHardwareDecoding ? "VideoToolbox" : nil].compactMap { $0 }.joined(separator: " · ")
    }
    var displaySize: CGSize { reader.displaySize }
    var isStopped: Bool { stopped }

    private let audio: AudioOutput?
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let videoQueue = DispatchQueue(label: "QLM.video.feed", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "QLM.audio.feed", qos: .userInitiated)
    private let epoch = OSAllocatedUnfairLock(initialState: 0)
    private let ended = OSAllocatedUnfairLock(initialState: (video: false, audio: false))
    private let audioLoopRunning = OSAllocatedUnfairLock(initialState: false)
    /// Per l'avvio sincronizzato: serve il primo fotogramma (se c'è) e un po' di audio già in coda.
    private let firstVideoPTS = OSAllocatedUnfairLock<Double?>(initialState: nil)
    private var timeObserver: Any?
    private var stopped = false
    private var wantsToPlay = false          // l'utente vuole che vada
    private var running = false              // l'orologio sta davvero girando
    private var startPending = false
    private var needsGate = true             // dopo l'apertura e dopo ogni salto: si riparte solo con fotogramma e audio pronti
    private var tickCount = 0
    private var anchor: Double = 0           // dove si riparte (secondi)

    init(url: URL) throws {
        reader = try QLMMediaReader(path: url.path)
        duration = reader.duration
        var output: AudioOutput?
        if reader.hasAudio {
            do { output = try AudioOutput() } catch { log.error("audio non disponibile: \(String(describing: error), privacy: .public)") }
        }
        audio = output
        hasAudio = output != nil
        super.init()
        displayLayer.videoGravity = .resizeAspect
        synchronizer.addRenderer(displayLayer)
        timeObserver = synchronizer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        reader.start()
        startFeeding()
        log.info("aperto: \(self.details, privacy: .public), durata \(self.duration), audio \(self.hasAudio)")
    }

    // MARK: Comandi

    func play() {
        guard !stopped else { return }
        log.info("play(): hasBase=\(self.audio?.hasBase ?? false) video=\(self.firstVideoPTS.withLock { $0 != nil }) coda audio=\(self.audio?.queuedSeconds ?? 0)")
        if isFinished { seek(to: 0) }
        wantsToPlay = true
        isPlaying = true
        if running { return }
        if needsGate { startPending = true; tryStart() } else { resume() }
    }

    func pause() {
        wantsToPlay = false
        isPlaying = false
        startPending = false
        guard running else { return }
        anchor = currentMediaTime()
        audio?.player.pause()
        synchronizer.rate = 0
        running = false
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func seek(to seconds: Double) {
        guard !stopped else { return }
        let t = max(0, duration > 0 ? min(seconds, duration) : seconds)
        let resumeAfter = wantsToPlay
        epoch.withLock { $0 += 1 }
        ended.withLock { $0 = (false, false) }
        firstVideoPTS.withLock { $0 = nil }
        synchronizer.rate = 0
        audio?.reset()
        displayLayer.flush()
        running = false
        reader.seek(toTime: t)
        anchor = t
        currentTime = t
        isFinished = false
        startPending = resumeAfter
        needsGate = true
        synchronizer.setRate(0, time: CMTime(seconds: t, preferredTimescale: 600))
        startFeeding()
        if resumeAfter { tryStart() }
    }

    /// Ferma tutto e libera il lettore: dopo, il controller non si riusa. Si chiama quando la finestra di Quick Look si chiude.
    func stop() {
        guard !stopped else { return }
        stopped = true
        wantsToPlay = false
        isPlaying = false
        running = false
        synchronizer.rate = 0
        if let timeObserver { synchronizer.removeTimeObserver(timeObserver) }
        timeObserver = nil
        displayLayer.stopRequestingMediaData()
        reader.stop()
        displayLayer.flush()
        audio?.shutdown()
        log.info("fermato")
        #if DEBUG
        print("VIDEO stop() eseguito")
        #endif
    }

    // MARK: Avvio sincronizzato

    private func currentMediaTime() -> Double {
        if running, let t = audio?.mediaTime { return t }
        let t = synchronizer.currentTime().seconds
        return t.isFinite ? t : anchor
    }

    /// Parte quando c'è abbastanza materiale: il primo fotogramma e almeno 0,25 s di audio.
    private func tryStart() {
        guard startPending, wantsToPlay, !stopped, !running else { return }
        log.info("tryStart: video=\(!self.hasVideo || self.firstVideoPTS.withLock { $0 } != nil) audio=\(self.audio?.queuedSeconds ?? 0)")
        let videoReady = !hasVideo || firstVideoPTS.withLock { $0 } != nil
        let audioReady = !hasAudio || (audio!.queuedSeconds >= 0.25 || ended.withLock { $0.audio } && audio!.hasBase)
        guard videoReady, audioReady else { return }
        startPending = false
        let start: Double = audio?.mediaBase ?? firstVideoPTS.withLock { $0 } ?? anchor
        begin(at: start)
    }

    private func begin(at media: Double) {
        let host = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08)
        let hostTime = CMClockMakeHostTimeFromSystemUnits(host)
        audio?.player.play(at: AVAudioTime(hostTime: host))
        synchronizer.setRate(1, time: CMTime(seconds: media, preferredTimescale: 600), atHostTime: hostTime)
        running = true
        needsGate = false
        log.info("avvio sincronizzato a \(media, privacy: .public) s (audio: \(self.hasAudio))")
    }

    private func resume() {
        let host = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05)
        audio?.player.play(at: AVAudioTime(hostTime: host))
        synchronizer.setRate(1, time: CMTime(seconds: anchor, preferredTimescale: 600), atHostTime: CMClockMakeHostTimeFromSystemUnits(host))
        running = true
        log.info("ripreso a \(self.anchor, privacy: .public) s")
    }

    private func applyVolume() { audio?.volume = isMuted ? 0 : volume }

    // MARK: Orologio

    private func tick(_ seconds: Double) {
        guard !stopped, seconds.isFinite else { return }
        tryStart()
        // Il video segue l'audio: se si scosta di più di 60 ms lo si riallinea.
        if running, let a = audio?.mediaTime, abs(a - seconds) > 0.06 {
            synchronizer.setRate(1, time: CMTime(seconds: a, preferredTimescale: 600))
        }
        currentTime = max(0, running ? (audio?.mediaTime ?? seconds) : seconds)
        #if DEBUG
        #else
        tickCount += 1
        if tickCount % 10 == 0 { log.info("t=\(self.currentTime, privacy: .public) running=\(self.running) orologio=\(seconds, privacy: .public) audio=\(self.audio?.mediaTime ?? -1, privacy: .public)") }
        #endif
        let done = ended.withLock { $0 }
        let finishedVideo = !hasVideo || done.video, finishedAudio = !hasAudio || done.audio
        if isPlaying, running, finishedVideo, finishedAudio, duration <= 0 || currentTime >= duration - 0.3,
           (audio?.queuedSeconds ?? 0) < 0.05 {
            pause()
            isFinished = true
        }
    }

    // MARK: Alimentazione

    private func startFeeding() {
        if hasVideo {
            let renderer = displayLayer
            renderer.requestMediaDataWhenReady(on: videoQueue) { [weak self] in self?.feedVideo(renderer) }
        }
        if hasAudio, audioLoopRunning.withLock({ let was = $0; $0 = true; return !was }) {
            audioQueue.async { [weak self] in self?.audioLoop() }
        }
    }

    private nonisolated func feedVideo(_ renderer: AVSampleBufferDisplayLayer) {
        log.info("feedVideo: pronto=\(renderer.isReadyForMoreMediaData) stato=\(renderer.status.rawValue) errore=\(String(describing: renderer.error), privacy: .public)")
        while renderer.isReadyForMoreMediaData {
            let e = epoch.withLock { $0 }
            log.info("video: richiedo un fotogramma")
            guard let sample = reader.copyNextVideoSample() else {
                log.info("video: fine o nessun fotogramma")
                if e == epoch.withLock({ $0 }) { ended.withLock { $0.video = true } }
                renderer.stopRequestingMediaData()
                return
            }
            if e != epoch.withLock({ $0 }) { continue }       // arrivato dopo un salto: è vecchio
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let first = firstVideoPTS.withLock { v -> Bool in if v == nil { v = pts; return true }; return false }
            renderer.enqueue(sample)
            if first { log.info("primo fotogramma a \(pts, privacy: .public) s, stato \(renderer.status.rawValue)") }
            if first { DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.firstFrameArrived(pts) } } }
        }
    }

    private func firstFrameArrived(_ pts: Double) {
        log.info("firstFrameArrived: pending=\(self.startPending) wants=\(self.wantsToPlay) running=\(self.running)")
        // In pausa dopo un salto: il fotogramma deve vedersi, quindi l'orologio si porta su di lui.
        if !running && !startPending { synchronizer.setRate(0, time: CMTime(seconds: pts, preferredTimescale: 600)) }
        tryStart()
    }

    private nonisolated func audioLoop() {
        while true {
            if (audio?.queuedSeconds ?? 0) > 1.0 {                  // abbastanza in coda
                if isStoppedFlag.withLock({ $0 }) { break }
                usleep(20_000)
                continue
            }
            let e = epoch.withLock { $0 }
            guard let sample = reader.copyNextAudioSample() else {
                if e == epoch.withLock({ $0 }) {
                    ended.withLock { $0.audio = true }
                    audioLoopRunning.withLock { $0 = false }
                    return
                }
                continue
            }
            if e != epoch.withLock({ $0 }) { continue }
            audio?.schedule(sample)
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.tryStart() } }
            if isStoppedFlag.withLock({ $0 }) { break }
        }
        audioLoopRunning.withLock { $0 = false }
    }

    private nonisolated let isStoppedFlag = OSAllocatedUnfairLock(initialState: false)

    // MARK: Debug

    #if DEBUG
    var debugAudioStatus: Int { audio?.player.isPlaying == true ? 1 : 0 }
    #endif
}
