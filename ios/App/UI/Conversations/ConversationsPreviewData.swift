import PaplyKit
import SwiftUI

/// Frei erfundene Beispiele, niemals an einen Speicher oder die Aufnahme-Sitzung gebunden.
enum ConversationsPreviewData {
    static let people = [VoicePerson(id: "m", name: "Herr Müller"), VoicePerson(id: "n", name: "Nora Berg")]
    static let speakers: [ConversationSpeaker] = [
        .init(id: "S1", personID: VoicePerson.ownerID, nameSource: .owner, speechSeconds: 540, colorIndex: 0),
        .init(id: "S2", suggestion: .init(name: "Herr Müller", source: .transcript, evidence: "Guten Tag, Herr Müller. Passt es gerade?"), speechSeconds: 680, colorIndex: 1)
    ]
    static let phone = ConversationDisplay(conversation: Conversation(id: "preview-phone", durationMs: 1_420_000,
        origin: .imported, trigger: .app, state: .done, title: "Angebot für die Dachanlage",
        summary: .init(overview: "Die Dachanlage soll im Frühjahr gebaut werden. Für das Angebot fehlen noch die Dachmaße.",
            points: ["Die Garage bleibt zunächst frei.", "Ein Speicher wird als zweite Variante angeboten."],
            commitments: [.init(id: "c1", speakerID: "S2", text: "Dachmaße per Mail schicken", dueHint: "Bis Donnerstag")]), speakers: speakers),
        topic: "Sonnenwerk", tasks: [.init(id: "t1", text: "Angebot mit zwei Speichervarianten schicken", dueHint: "Freitag", owner: .ai)])
    static let meeting = ConversationDisplay(conversation: Conversation(id: "preview-meeting", createdAt: .now.addingTimeInterval(-86400), durationMs: 2_880_000,
        origin: .recording, trigger: .app, state: .done, title: "Planung für den Nachbarschaftsgarten",
        summary: .init(overview: "Vier Personen planen den ersten Gartentag. Treffpunkt ist am Samstag am alten Tor.",
            points: ["Die Beete werden gemeinsam vorbereitet.", "Werkzeug wird vor Ort geteilt."]),
        speakers: [speakers[0], .init(id: "S2", name: "Nora Berg", nameSource: .user, speechSeconds: 500, colorIndex: 2),
                   .init(id: "S3", name: "Tarek Sommer", nameSource: .user, speechSeconds: 400, colorIndex: 3),
                   .init(id: "S4", speechSeconds: 200, colorIndex: 4)]), topic: "Garten")
    static var waiting: ConversationDisplay {
        var item = phone; item.conversation.id = "preview-waiting"; item.conversation.state = .waitingLimit
        item.conversation.summary = nil; item.conversation.stagesDone = [.speakers, .transcript]; return item
    }
    static var analyzing: ConversationDisplay {
        var item = phone; item.conversation.id = "preview-analyzing"; item.conversation.title = nil
        item.conversation.state = .analyzing; item.conversation.summary = nil
        item.conversation.progress = .init(stage: .speakers, fraction: 0.4); return item
    }
    static var failed: ConversationDisplay {
        var item = phone; item.conversation.id = "preview-failed"; item.conversation.state = .needsAttention; return item
    }
    static var long: ConversationDisplay {
        var item = meeting; item.conversation.id = "preview-long"; item.conversation.title = "Lange Werkstattplanung"
        item.conversation.durationMs = 14_400_000; return item
    }
    static let utterances: [ConversationUtterance] = [
        .init(id: "u0", speakerID: "S1", start: 12, end: 17, text: "Guten Tag, Herr Müller. Passt es gerade?"),
        .init(id: "u1", speakerID: "S2", start: 18, end: 28, text: "Ja, gerne. Ich schicke Ihnen die Dachmaße bis Donnerstag per Mail."),
        .init(id: "u2", speakerID: "S1", start: 29, end: 39, text: "Dann schicke ich das Angebot am Freitag. Ich rechne zwei Varianten für den Speicher."),
        .init(id: "u3", speakerID: "S2", start: 40, end: 42, text: "Das klingt gut.", uncertain: true)
    ]
    private static let longTexts = [
        "Wir teilen die Arbeit auf und beginnen am Samstag mit den Beeten.",
        "Ich bringe die Werkzeuge mit. Wer kümmert sich um die Pflanzen?",
        "Die Liste ist vorbereitet, wir gehen sie gemeinsam durch.",
    ]
    static let longUtterances: [ConversationUtterance] = (0..<1200).map { (index: Int) -> ConversationUtterance in
        let start = Double(index * 12)
        return ConversationUtterance(id: "long-\(index)", speakerID: "S\(index % 4 + 1)", start: start, end: start + 10,
                                     text: longTexts[index % 3], uncertain: index % 37 == 0)
    }
    static let all = [phone, meeting, waiting, analyzing, failed, long]
}

#Preview("Gedanken-Zeile") { ConversationThoughtRow(item: ConversationsPreviewData.phone, time: "14:05").padding().background(PaplyBackground()).preferredColorScheme(.dark) }
#Preview("Zustandsband") { ConversationStatusBand(conversation: ConversationsPreviewData.analyzing.conversation, onRetry: {}).padding().background(PaplyBackground()).preferredColorScheme(.dark) }
#Preview("Sprecher") { ConversationSpeakerLabel(speaker: ConversationsPreviewData.speakers[1], showSuggestion: true).padding().background(PaplyBackground()).preferredColorScheme(.dark) }

#if DEBUG
extension ConversationsPreviewData {
    static var callUnknownOwner: ConversationDisplay {
        var item = phone
        item.conversation.speakers[0].personID = nil
        item.conversation.speakers[0].nameSource = .none
        return item
    }

    static var meetingWithTasks: ConversationDisplay {
        var item = meeting
        item.tasks = [.init(id: "garden-own", text: "Saatgut und Handschuhe besorgen", dueHint: "Freitag", owner: .ai)]
        item.conversation.summary?.commitments = [
            .init(id: "garden-nora", speakerID: "S2", text: "Jungpflanzen mitbringen", dueHint: "Samstag"),
            .init(id: "garden-tarek", speakerID: "S3", text: "Schubkarre organisieren"),
            .init(id: "garden-four", speakerID: "S4", text: "Wasseranschluss prüfen")
        ]
        item.conversation.gaps = [.init(at: 29, seconds: 300, reason: "pause")]
        return item
    }

    static var partlyProcessed: ConversationDisplay {
        var item = analyzing
        item.conversation.stagesDone = [.speakers, .transcript]
        return item
    }
}
#endif
