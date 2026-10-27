import Foundation

/// Schneidet die laufende Aufnahme an Sprechpausen in Stücke, die sofort transkribiert
/// werden können.
///
/// Schwellen (in der Mac-Messung geprüft, siehe ios/docs/phase0/latenz-mac.md):
/// - Mindestens 10 s je Stück: Groq rechnet jede Anfrage mit mindestens 10 s ab, und
///   Whisper erkennt Sprache und Satzbau mit mehr Kontext sicherer.
/// - Pause ≥ 0,6 s: Pausen zwischen Wörtern und Verschlusslaute (p, t, k) liegen bei
///   50–300 ms, Zögern meist unter 0,5 s; 0,6 s liegt sicher zwischen Sätzen/Satzteilen,
///   nie mitten im Wort.
/// - Ab 20 s ohne Schnitt genügt 0,4 s: Schnellsprecher machen selten lange Pausen;
///   0,4 s liegt immer noch deutlich über Lücken innerhalb eines Worts.
/// - Geschnitten wird in der Mitte der geforderten Pause, damit beide Stücke etwas
///   Stille am Rand haben (Whisper halluziniert an harten Kanten eher).
package struct ChunkPlanner: Sendable {
    package var minChunkSeconds = 10.0
    var pauseSeconds = 0.6
    var relaxedAfterSeconds = 20.0
    var relaxedPauseSeconds = 0.4

    /// Erstes Fenster des noch offenen Stücks.
    private(set) var chunkStartFrame = 0

    package init() {}

    private func frames(_ seconds: Double) -> Int {
        Int((seconds * 1000 / VoiceActivityDetector.frameMs).rounded())
    }

    /// Liefert den Fensterbereich eines fertigen Stücks, wenn jetzt geschnitten werden soll.
    package mutating func nextCut(_ vad: VoiceActivityDetector) -> Range<Int>? {
        let end = vad.frameCount
        let pause = vad.trailingPauseFrames(endingAt: end)
        guard pause > 0 else { return nil }
        let pauseStart = end - pause
        let spoken = pauseStart - chunkStartFrame
        guard spoken > 0 else { return nil }
        let required = frames(Double(spoken) * VoiceActivityDetector.frameMs >= relaxedAfterSeconds * 1000
                              ? relaxedPauseSeconds : pauseSeconds)
        guard pause >= required else { return nil }
        let cut = pauseStart + required / 2
        guard cut - chunkStartFrame >= frames(minChunkSeconds),
              vad.hasSpeech(in: chunkStartFrame..<pauseStart) else { return nil }
        let chunk = chunkStartFrame..<cut
        chunkStartFrame = cut
        return chunk
    }
}
