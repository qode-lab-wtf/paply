@preconcurrency import AVFoundation
import PaplyKit
import SwiftUI

// „Original“ im Detail (KONZEPT §3.2): zugeklappt. Darin Wiedergabe (Play/Pause, Schieber),
// der Rohtext (auswählbar) und wann der Ton entfernt wird.

struct ThoughtOriginalSection: View {
    let thought: Thought
    let source: ThoughtSource?
    let audioURL: URL?

    @State private var expanded = ThoughtOriginalSection.startExpanded
    @Environment(\.accessibilityReduceMotion) private var reduce

    #if DEBUG
    static var startExpanded: Bool { ProcessInfo.processInfo.arguments.contains("-PaplyExpandOriginal") }
    #else
    static var startExpanded: Bool { false }
    #endif

    private var audioRemoved: Bool {
        if thought.audio == nil { return true }
        if let deleteAfter = thought.audio?.deleteAfter, deleteAfter < Date(), audioURL == nil { return true }
        return false
    }

    var body: some View {
        if source != nil || thought.audio != nil || thought.durationMs > 0 {
            Button {
                withAnimation(PaplyMotion.smooth(reduce)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("ORIGINAL")
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Spacer()
                }
                .foregroundStyle(Color.paplyTertiaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .docRow(top: 10, bottom: 6)
            .accessibilityLabel("Original")
            .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
            .accessibilityHint("Ton und Rohtext")

            if expanded {
                if audioRemoved {
                    Label("Ton nach 30 Tagen entfernt.", systemImage: "waveform.slash")
                        .font(.subheadline)
                        .foregroundStyle(Color.paplySecondaryText)
                        .docRow(top: 4, bottom: 10)
                } else {
                    AudioPlayerRow(url: audioURL, fallbackDuration: Double(thought.durationMs) / 1000)
                        .docRow(top: 4, bottom: 12)
                }
                if let raw = source?.text, !raw.isEmpty {
                    Text(raw)
                        .font(.callout)
                        .foregroundStyle(Color.paplyText.opacity(0.78))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
                        .docRow(bottom: 10)
                }
                if let note = retentionNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Color.paplyTertiaryText)
                        .docRow(bottom: 8)
                }
            }
        }
    }

    private var retentionNote: String? {
        guard !audioRemoved, let deleteAfter = thought.audio?.deleteAfter else { return nil }
        return "Ton wird am \(ThoughtDate.dayMonthLong.string(from: deleteAfter)) entfernt. Text und Aufgaben bleiben."
    }
}

extension ThoughtDate {
    static let dayMonthLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM"
        return f
    }()
}

/// ▶︎ ━━━━━○──── 0:34 / 1:12
struct AudioPlayerRow: View {
    let url: URL?
    let fallbackDuration: Double

    @State private var player = OriginalPlayer()
    @State private var scrubbing: Double?

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if let url { player.toggle(url) }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.paplyForest)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(url == nil ? Color.white.opacity(0.25) : Color.paplyGreenBright))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(url == nil)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Abspielen")

            VStack(spacing: 2) {
                let duration = player.duration > 0 ? player.duration : fallbackDuration
                let position = scrubbing ?? player.currentTime
                Slider(value: Binding(get: { min(position, max(duration, 0.01)) }, set: { scrubbing = $0 }),
                       in: 0...max(duration, 0.01)) { editing in
                    if !editing, let target = scrubbing {
                        player.seek(to: target)
                        scrubbing = nil
                    }
                }
                .tint(Color.paplyGreenBright)
                .disabled(url == nil)
                .accessibilityLabel("Position")
                .accessibilityValue("\(ThoughtDate.spokenClock(position)) von \(ThoughtDate.spokenClock(duration))")
                HStack {
                    Text(ThoughtDate.clock(position))
                    Spacer()
                    Text(ThoughtDate.clock(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.paplySecondaryText)
                .accessibilityHidden(true)
            }
        }
        .task(id: player.isPlaying) {
            // Zeit fortschreiben, solange abgespielt wird
            while player.isPlaying, !Task.isCancelled {
                player.refresh()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
        .onDisappear { player.stop() }
    }
}

/// Wiedergabe über die aktuelle Route. Läuft keine Paply-Sitzung, nimmt Paply kurz die Kategorie
/// „Wiedergabe“ (sonst bliebe es bei stummgeschaltetem iPhone still); die Sitzung des Mikros
/// setzt beim nächsten Start ihre eigene Kategorie.
@MainActor
@Observable
final class OriginalPlayer {
    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var currentTime: Double = 0
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var activatedSession = false
    @ObservationIgnored private var loadedURL: URL?

    func toggle(_ url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if loadedURL != url || player == nil {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            loadedURL = url
            duration = player?.duration ?? 0
        }
        guard let player else { return }
        if SessionController.shared.status == .off {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
            activatedSession = true
        }
        if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
        isPlaying = player.play()
    }

    func seek(to time: Double) {
        player?.currentTime = time
        currentTime = time
    }

    /// Zeit fortschreiben, Ende erkennen
    func refresh() {
        guard let player else { return }
        currentTime = player.currentTime
        if isPlaying && !player.isPlaying {
            isPlaying = false
            currentTime = player.duration
            releaseSession()
        }
    }

    func stop() {
        player?.stop()
        isPlaying = false
        releaseSession()
    }

    private func releaseSession() {
        guard activatedSession, SessionController.shared.status == .off else { return }
        activatedSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
