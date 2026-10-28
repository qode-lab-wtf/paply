# Etappe 2 A – Gedanken-Kern (28.10.2026)

Neues JVM-Modul `:thoughts`, Paket `com.paply.thoughts`, abhängig von `:core`.
JDK-Toolchain 21, JVM-Ziel 17; `:app` hängt weiterhin nicht davon ab.
Keine Commits/Pushes; iOS und Diktatverhalten unverändert.

## Zuordnung Swift → Kotlin
- `Contracts.swift` → `Contracts.kt` (Werttypen als immutable data classes, Änderungen per `copy`).
- `Model/*` → `model/{ThoughtCoding,SupportTypes}.kt`; Modelle/Enums in `Contracts.kt`.
- `Store/*` → `store/{ThoughtStore,FileSafety,WAVWriter,StoreTypes}.kt`.
- `AI/*` → gleichnamige `ai/*`; Gedanken-Sicherheitsprofil in `ThoughtSafetyNet.kt`.
- Strukturierter Groq-Aufruf → `ai/StructuredChat.kt`, nutzt `:core`-Transport/Fehler.
- `Budget/TokenLedger.swift` → `budget/TokenLedger.kt`.
- `Processing/*` → gleichnamige `processing/*`; `DueDate`/`RawText` separat.
- Ausnahme `Local/TopicMentions.swift` → `nlp/TopicMentions.kt`: Validator braucht es direkt.
- Beta-Kern → `model/BetaFeatures.kt`; keine Display-/Reminder-Plan-Implementierung.

## Nachweis
Auf MacBook, eigener Arbeitsordner, ausschließlich:
`PAPLY_WORK=thoughts android/scripts/mb.sh sync`
`PAPLY_WORK=thoughts GRADLE_TASKS=":thoughts:test" android/scripts/mb.sh build`
267 Tests grün, alle HTTP-Tests offline mit MockWebServer, keine echten Groq-Aufrufe.

| Swift-Suite | iOS | Kotlin | Anmerkung |
|---|---:|---:|---|
| AIValidatorTests | 74 | 74 | Auf Teil-Suiten verteilt; Originalfälle erhalten |
| ProcessingTests | 40 | 40 | Testadapter für Local/TopicIndex |
| AILedgerPromptTests | 34 | 34 | Ledger, Prompt, Hygiene, Sicherheitsprofil |
| StoreTests | 29 | 29 | AVFoundation/Apple-Dateiattribute durch JVM-Prüfungen ersetzt |
| AIClientTests | 24 | 24 | 23 portiert; 1 Produktions-Datenschutztest statt Diagnose-API |
| AINumbersTests | 12 | 12 | Originalfälle |
| ThoughtTraceTests | 6 | 6 | Originalfälle, kein Nutzertext in Trace |
| DescribedTopicsTests | 24 | 24 | Drei Wörterbuch-Erwartungen angepasst, siehe unten |
| BetaFeaturesTests | 4 | 4 | Reminder-ID geprüft; Reminder-Plan gehört zu Teil B |
| TaskAgendaTests: SpokenTime/DueDate | 12 | 12 | Zusätzlicher Abschnitt mit eigener Kernlogik |
| AndroidSafetyTests | – | 8 | Defekte Dateien, Kopien, Rechte, Parallelität, Abbruch, NLP |

Prompts/Systemtexte einschließlich Teil-Prompt wörtlich aus iOS; Konzeptvergleich als Test.
247 angeforderte Testfälle/-Entsprechungen plus 20 zusätzliche; keine komplette Apple-NLP-Parität behauptet.

## Übergabe an Teil B
- `CandidateFinding`: `topicIndex`, beide `candidates`-Formen, `didChange`; Einträge wie Swift.
- `KeywordFinding.keywords` und `TopicSummarizing.summaries` in `Contracts.kt` implementieren.
- `ThoughtProcessor` und `TopicHygieneRunner` erhalten diese Abhängigkeiten explizit.
- Einfache Testadapter: `ProcessingSupport.kt` (`TestTopicIndex`, `TestCandidateFinder`, Harness).
- Drei DescribedTopics-Rangfolge-/Pinningtests prüfen derzeit Adapter; mit echtem Local erneut prüfen.
- `TopicMentions` ist bereits produktiv vorhanden; nicht nochmals portieren.
- `SearchHit.ranges`: UTF-16-Indizes, inklusive Kotlin-Range-Ende (NSRange-Länge umrechnen).
- `nlp/Embedder` mit revisions-/dimensionsgeprüften Vektoren; `UnavailableEmbedder` liefert false/null.

## NLP und Plattformabweichungen
- Snowball DE/EN: `com.github.rholder:snowball-stemmer:1.3.0.581.1`, kein Lucene.
- BSD-3-Lizenz im JAR unter `META-INF/LICENSE-snowball.txt`; Stämme statt Apple-Lemmata.
- Ohne Sprache beide Stämme; Validator behält Originalform/gemeinsamen Anfang als Rückfall.
- Großschreibung im Satzinneren → Nomen/Namenshinweis, Binnen-Großschrift → Namenshinweis;
  Endungen en/ern/eln bzw. englisch ing/ed → Verbhinweis, sonst otherWord; keine echte NER.
- Satzteilung über `java.text.BreakIterator`; alle 74 Validatorfälle ohne Erwartungsänderung grün.
- Apple-Wörterbuch fehlt: `CommonWords.available=false`; riskante Namensableitung auf -er aus.
  Drei DescribedTopics-Tests behalten ihre Eingaben, erwarten bei Beueler keinen Treffer bzw. Rückfall.
- `DueDate`: konservative DE/EN-Regeln statt NSDataDetector; 12 gemessene iOS-Tests portiert.
  Weitere Apple-Datumsformen nicht garantiert; nicht erkannte Ausdrücke bleiben als dueHint erhalten.

## Speicher, Sichtbarkeiten, offene Integration
- JSON-Versionen/Millisekunden wie iOS; atomar temp→fsync→rename, defekt → damaged-<ms>.json.
- Lesen löscht keine Platzhalter/Audio/temp-Dateien; Bereinigung nur in expliziter Recovery.
- Audio erst nach dauerhaftem Rohtext mit Rückleseprüfung/Verzeichnis-fsync entfernen.
- Nutzerrechte beim Commit erneut geprüft; Hygiene speichert nur Vorschläge, keine automatische Änderung.
- Eigene :core-Änderungen ausschließlich Sichtbarkeit: TextAnalysis, Lexicon, EditCheck, Pattern,
  GroqClient.request/send und primärer DictationPipeline-Konstruktor öffentlich.
- Gleichzeitige fremde Änderungen an :core/:app/:scripts erhalten; nicht Teil dieses Ports.
- Offen für B/App: echte Local/Map/Display-Adapter, Android-Speicher-/Backupschutz und Sprachdetektor.
- WAV PCM16/Float32 mono 16 kHz eingebaut; M4A/weitere Decoder über FileTranscriber-Decoder injizieren.
- Eval-only `chatStructuredDiagnosed` außerhalb Thoughts nicht portiert; Produktion verwirft failed_generation.
