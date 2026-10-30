import Foundation

/// Testsätze für die Latenzmessung. `[[slnc N]]` erzeugt bei `say` N ms Stille
/// (natürliche Sprechpausen); aus dem Referenztext wird es entfernt.
struct Part: Codable, Sendable {
    let voice: String
    let lang: String
    let text: String
    /// Stille nach diesem Teil in ms (Sprachwechsel mitten im Satz: kurz).
    var gapMs: Int = 450
}

struct BenchScript: Codable, Sendable {
    let id: String
    let lang: String
    let length: String
    let parts: [Part]
    /// Zusatzaudio für Einzelmessungen, nicht Teil der Standardmatrix.
    var extra = false

    var reference: String {
        parts.map { $0.text.replacingOccurrences(of: #"\[\[[^\]]*\]\]"#, with: " ", options: .regularExpression) }
            .joined(separator: " ")
    }
}

let de = "Anna"
let en = "Samantha"

let benchScripts: [BenchScript] = [
    // MARK: Deutsch
    BenchScript(id: "de-8", lang: "de", length: "8s", parts: [
        Part(voice: de, lang: "de", text: "Kannst du mir bitte bis morgen früh die aktuelle Präsentation schicken? Vielen Dank dir."),
    ]),
    BenchScript(id: "de-30", lang: "de", length: "30s", parts: [
        Part(voice: de, lang: "de", text: """
        Hallo Jana, ich wollte mich kurz wegen des Termins am Donnerstag melden. [[slnc 700]] \
        Leider schaffe ich es nicht vor zehn Uhr, weil ich vorher noch beim Arzt bin. [[slnc 800]] \
        Wäre es für dich in Ordnung, wenn wir die Besprechung auf den Nachmittag verschieben? [[slnc 700]] \
        Ich bringe dann auch die überarbeiteten Unterlagen und die Zahlen aus dem letzten Quartal mit. \
        Gib mir einfach kurz Bescheid, was dir besser passt.
        """),
    ]),
    BenchScript(id: "de-75", lang: "de", length: "75s", parts: [
        Part(voice: de, lang: "de", text: """
        Ich fasse kurz zusammen, was wir heute im Team besprochen haben. [[slnc 700]] \
        Erstens wollen wir die neue Version der App erst nach den Herbstferien veröffentlichen, \
        weil die Rückmeldungen aus dem Test noch nicht vollständig ausgewertet sind. [[slnc 900]] \
        Zweitens kümmert sich Markus um die Übersetzungen und um die Texte im Einstellungsbereich. \
        Er braucht dafür ungefähr zwei Wochen. [[slnc 800]] \
        Drittens müssen wir klären, wie wir mit den Anfragen der Kunden umgehen, \
        die sich über die langsame Synchronisierung beschwert haben. [[slnc 700]] \
        Ich schlage vor, dass wir dafür eine eigene Seite mit häufigen Fragen anlegen \
        und die wichtigsten Antworten dort sammeln. [[slnc 900]] \
        Außerdem sollten wir uns noch einmal die Kosten für den Server anschauen, \
        denn die Rechnung im letzten Monat war deutlich höher als geplant. [[slnc 800]] \
        Zum Schluss noch eine Bitte: Tragt eure Urlaubstage bis Ende der Woche in den gemeinsamen Kalender ein, \
        damit wir die Planung für den Dezember abschließen können. [[slnc 600]] \
        Danke euch allen für die gute Arbeit in den letzten Wochen.
        """),
    ]),

    // MARK: Englisch
    BenchScript(id: "en-8", lang: "en", length: "8s", parts: [
        Part(voice: en, lang: "en", text: "Could you please send me the updated slides before lunch tomorrow? Thanks a lot."),
    ]),
    BenchScript(id: "en-30", lang: "en", length: "30s", parts: [
        Part(voice: en, lang: "en", text: """
        Hi Mark, I just wanted to follow up on our call from this morning. [[slnc 700]] \
        I talked to the design team, and they need two more days to finish the onboarding screens. [[slnc 800]] \
        That means we will probably miss the original deadline on Friday. [[slnc 700]] \
        I suggest we move the internal review to Tuesday and keep the public launch date as it is. \
        Let me know if that works for you, or if you would rather discuss it in person.
        """),
    ]),
    BenchScript(id: "en-75", lang: "en", length: "75s", parts: [
        Part(voice: en, lang: "en", text: """
        Here is a quick summary of what we decided in today's planning meeting. [[slnc 700]] \
        First, the mobile release is postponed until after the holidays, \
        because the feedback from the beta testers is not fully processed yet. [[slnc 900]] \
        Second, Sarah will take care of the translations and the new help pages, \
        which should take about two weeks. [[slnc 800]] \
        Third, we still need a clear answer for the customers who complained about slow synchronization. [[slnc 700]] \
        I would like to collect the most common questions on a separate page \
        and link it directly from the settings screen. [[slnc 900]] \
        We should also review our hosting costs, \
        since last month's invoice was significantly higher than expected. [[slnc 800]] \
        Finally, please add your vacation days to the shared calendar by the end of the week, \
        so that we can finish the schedule for December. [[slnc 600]] \
        One more thing: the new office keys are ready, [[slnc 500]] \
        and you can pick them up at the front desk from Wednesday on. [[slnc 700]] \
        Thanks everyone for the great work over the last few weeks.
        """),
    ]),

    // MARK: Gemischt (Deutsch mit englischen Fachbegriffen + Sprachwechsel mitten im Satz)
    BenchScript(id: "mix-8", lang: "mix", length: "8s", parts: [
        Part(voice: de, lang: "de", text: "Ich habe den Pull Request gemerged, aber", gapMs: 120),
        Part(voice: en, lang: "en", text: "the build is still failing on staging."),
    ]),
    BenchScript(id: "mix-30", lang: "mix", length: "30s", parts: [
        Part(voice: de, lang: "de", text: """
        Kurzes Update zum Release: Das Deployment auf Staging ist durch, [[slnc 600]] \
        aber beim Login gibt es noch einen Bug mit dem Token Refresh. [[slnc 800]] \
        Ich habe mit Tom gesprochen und
        """, gapMs: 150),
        Part(voice: en, lang: "en", text: """
        he thinks the issue is caused by the new caching layer in the backend.
        """),
        Part(voice: de, lang: "de", text: """
        Wir machen morgen früh ein kurzes Meeting dazu und entscheiden dann, \
        ob wir den Release verschieben. [[slnc 700]] \
        Bis dahin bitte keine Hotfixes direkt auf Production.
        """),
    ]),
    BenchScript(id: "mix-75", lang: "mix", length: "75s", parts: [
        Part(voice: de, lang: "de", text: """
        Also, ich fasse mal den Stand vom Sprint zusammen. [[slnc 700]] \
        Das Backend ist fertig, die API ist dokumentiert und alle Endpoints haben Unit Tests. [[slnc 800]] \
        Beim Frontend hängen wir noch, weil das neue Design System erst seit Montag da ist. [[slnc 700]] \
        Lisa hat gesagt,
        """, gapMs: 150),
        Part(voice: en, lang: "en", text: """
        we should not merge anything into main before the code review is done.
        """, gapMs: 600),
        Part(voice: de, lang: "de", text: """
        Das finde ich richtig. [[slnc 700]] \
        Für das Onboarding brauchen wir außerdem noch die finalen Screenshots \
        und einen kurzen Text für den App Store. [[slnc 800]] \
        Im Daily morgen sollten wir klären, wer das übernimmt. [[slnc 600]] \
        Und dann noch eine Info von unserem Kunden aus London:
        """, gapMs: 400),
        Part(voice: en, lang: "en", text: """
        They are really happy with the prototype, but they asked for an export to PDF \
        and a dark mode before the next demo.
        """, gapMs: 600),
        Part(voice: de, lang: "de", text: """
        Ich würde vorschlagen, dass wir den Dark Mode vorziehen und den Export in den nächsten Sprint schieben. [[slnc 800]] \
        Wenn niemand etwas dagegen hat, trage ich das gleich so ins Board ein und schreibe dem Kunden eine kurze Mail.
        """),
    ]),

    // MARK: Zusatz (W8-Nachmessung)
    BenchScript(id: "fr-mix", lang: "mix", length: "30s", parts: [
        Part(voice: "Thomas", lang: "fr", text: """
        Petit point sur le projet : le déploiement sur staging est terminé, [[slnc 600]] \
        mais il reste un bug avec le login. [[slnc 700]] J'ai parlé avec Julie et
        """, gapMs: 150),
        Part(voice: en, lang: "en", text: "she thinks the problem comes from the new cache."),
        Part(voice: "Thomas", lang: "fr", text: """
        On en discute demain matin et on décide si on repousse la sortie. [[slnc 600]] \
        D'ici là, pas de correctifs directement en production.
        """),
    ], extra: true),
    BenchScript(id: "de-bild", lang: "de", length: "8s", parts: [
        Part(voice: de, lang: "de", text: "Schick mir bitte das Bild von gestern Abend. [[slnc 500]] Das Bild mit dem Hund finde ich besonders schön."),
    ], extra: true),
]
