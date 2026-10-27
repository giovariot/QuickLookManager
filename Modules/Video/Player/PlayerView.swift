import AppKit
import AVFoundation
import SwiftUI

/// Il livello di AVFoundation dentro SwiftUI.
private struct VideoLayerView: NSViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer = layer
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Vetro per i controlli sopra il contenuto (Liquid Glass dove c'è, materiale standard prima).
private struct ControlGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct PlayerView: View {
    @ObservedObject var controller: VideoPlayerController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Lo sfondo di un filmato è nero: è il contenuto, non un colore dell'interfaccia.
            Color.black
            if controller.hasVideo {
                VideoLayerView(layer: controller.displayLayer)
                    .accessibilityLabel(Text(controller.title ?? String(localized: "Video", bundle: QLMBundle.framework)))
            } else {
                audioPlaceholder
            }
            // Con VoiceOver i controlli restano sempre raggiungibili.
            if controlsVisible || !controller.isPlaying || NSWorkspace.shared.isVoiceOverEnabled {
                controlBar
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.togglePlay(); poke() }
        .onContinuousHover { phase in if case .active = phase { poke() } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controlsVisible)
        .onChange(of: controller.isPlaying) { _, _ in poke() }
        .onAppear { poke() }
    }

    private var audioPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 56)).symbolRenderingMode(.hierarchical)
            if let title = controller.title { Text(title).font(.title3) }
            Text(controller.details).font(.callout).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Controlli

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                controller.togglePlay()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(controller.isPlaying ? Text("Pausa", bundle: QLMBundle.framework) : Text("Riproduci", bundle: QLMBundle.framework))

            Text(format(scrubbing ? scrubValue : controller.currentTime))
                .font(.callout).monospacedDigit().foregroundStyle(.primary)

            if controller.duration > 0 {
                Slider(value: Binding(get: { scrubbing ? scrubValue : min(controller.currentTime, controller.duration) },
                                      set: { scrubValue = $0 }),
                       in: 0...controller.duration) { editing in
                    if editing { scrubbing = true; scrubValue = controller.currentTime }
                    else { scrubbing = false; controller.seek(to: scrubValue) }
                }
                .controlSize(.small)
                .accessibilityLabel(Text("Posizione", bundle: QLMBundle.framework))
                .accessibilityValue(Text(format(scrubbing ? scrubValue : controller.currentTime)))
                Text("-" + format(max(0, controller.duration - (scrubbing ? scrubValue : controller.currentTime))))
                    .font(.callout).monospacedDigit().foregroundStyle(.primary)
            } else {
                Spacer()
            }

            if controller.hasAudio {
                Button {
                    controller.isMuted.toggle()
                } label: {
                    Image(systemName: controller.isMuted || controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.isMuted ? Text("Riattiva l'audio", bundle: QLMBundle.framework) : Text("Silenzia", bundle: QLMBundle.framework))
                Slider(value: Binding(get: { Double(controller.isMuted ? 0 : controller.volume) },
                                      set: { controller.volume = Float($0) }), in: 0...1)
                    .controlSize(.small)
                    .frame(width: 80)
                    .accessibilityLabel(Text("Volume", bundle: QLMBundle.framework))
                    .accessibilityValue(Text(Double(controller.isMuted ? 0 : controller.volume), format: .percent.precision(.fractionLength(0))))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .modifier(ControlGlass())
        .frame(maxWidth: 720)
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.isFinite ? seconds : 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Mostra i controlli e li nasconde dopo qualche secondo se il filmato sta andando.
    private func poke() {
        controlsVisible = true
        hideTask?.cancel()
        guard controller.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && !scrubbing { controlsVisible = false }
        }
    }
}
