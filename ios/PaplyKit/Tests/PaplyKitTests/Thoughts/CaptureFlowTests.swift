import Foundation
import Testing
@testable import PaplyKit

// Besitzer: H3. Ende-zu-Ende der Aufnahme aus Sicht von ThoughtCapture (App), mit Ersatzteilen aus
// ProcessingTests (kein Groq): genau die Aufruf-Reihenfolge der App –
// beginCapture → expectLiveTranscript → Samples → close → finishCapture → liveTranscript / kick,
// bzw. Verwerfen: finishCapture → delete.

@Suite("Gedanken-Aufnahme (H3-Ablauf)")
struct CaptureFlowTests {
    /// Was ThoughtCapture beim Start tut (Eintrag + WAV synchron, Live-Pipeline angekündigt).
    private func start(_ h: Harness, live: Bool) async throws -> (String, WAVWriter) {
        let (thought, writer) = try await h.store.beginCapture(trigger: .control, at: h.clock.now)
        if live { await h.processor.expectLiveTranscript(thought.id) }
        return (thought.id, writer)
    }

    private func collect(_ events: AsyncStream<ProcessorEvent>, until id: String) async -> [ProcessorEvent] {
        var seen: [ProcessorEvent] = []
        var iterator = events.makeAsyncIterator()
        while let event = await iterator.next() {
            seen.append(event)
            switch event {
            case .saved(let x, _, _) where x == id, .empty(let x) where x == id, .failed(let x, _) where x == id:
                return seen
            case .waiting(let x, _, _) where x == id:
                return seen
            default:
                continue
            }
        }
        return seen
    }

    @Test func livePathStructuresWithoutSecondWhisperCall() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let events = h.processor.events
        let (id, writer) = try await start(h, live: true)
        writer.append(StoreSupport.tone(seconds: 2))
        // Während der Aufnahme: der Eintrag ist `recording`, die Warteschlange fasst ihn nicht an
        await h.run()
        #expect(await h.thought(id)?.state == .recording)
        // Stopp: captured. Zwischen Stopp und Live-Ergebnis darf kein Dateiweg (Whisper) starten.
        let saved = try await h.store.finishCapture(id, durationMs: writer.close())
        #expect(saved?.state == .captured)
        await h.run()
        #expect(await h.transcriber.calls == 0)
        await h.processor.liveTranscript(id, outcome: DictationOutcome(
            text: "die tomaten im garten muss ich morgen gießen", raw: "die tomaten im garten muss ich morgen gießen", languages: ["de"]))
        await h.processor.waitUntilIdle()
        let thought = try #require(await h.thought(id))
        #expect(thought.state == .done)
        #expect(await h.transcriber.calls == 0)
        #expect(await h.structurer.calls == 1)
        let seen = await collect(events, until: id)
        #expect(seen.contains(.processing(id)))
        #expect(seen.last == .saved(id, topicTitle: "Garten", topicIcon: .leaf))
    }

    @Test func filePathWithoutLivePipeline() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let (id, writer) = try await start(h, live: false)
        writer.append(StoreSupport.tone(seconds: 1))
        try await h.store.finishCapture(id, durationMs: writer.close())
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.transcriber.calls == 1)
        #expect(await h.structurer.calls == 1)
    }

    @Test func discardedThoughtGoesToTrashAndIsNeverProcessed() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let (id, writer) = try await start(h, live: false)
        writer.append(StoreSupport.tone(seconds: 1))
        // Verwerfen wie ThoughtCapture.discard: sichern, dann in „Zuletzt gelöscht“
        try await h.store.finishCapture(id, durationMs: writer.close())
        try await h.store.delete(id)
        await h.run()
        let trashed = try #require(await h.thought(id))
        #expect(trashed.deletedAt != nil)
        #expect(trashed.state == .captured)
        #expect(await h.transcriber.calls == 0)
        #expect(await h.structurer.calls == 0)
        #expect(await h.store.audioURL(id) != nil) // Ton bleibt für die Wiederherstellung
        // Wiederherstellen → normal geordnet
        try await h.store.restore(id)
        await h.run()
        #expect(await h.thought(id)?.state == .done)
        #expect(await h.structurer.calls == 1)
    }

    @Test func captureWithoutAudioLeavesNoEntry() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let (id, writer) = try await start(h, live: false)
        let saved = try await h.store.finishCapture(id, durationMs: writer.close())
        #expect(saved == nil)
        #expect(await h.thought(id) == nil)
    }

    @Test func failedStartLeavesNoEntry() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        // Mikro ließ sich nicht starten: ThoughtCapture schließt die Datei und ruft discardCapture
        let (id, writer) = try await start(h, live: false)
        _ = writer.close()
        await h.store.discardCapture(id)
        #expect(await h.thought(id) == nil)
        await h.run()
        #expect(await h.transcriber.calls == 0)
    }
}
