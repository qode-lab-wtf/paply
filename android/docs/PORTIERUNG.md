# Paply Android V1 – Portierungskarte

Stand: 28.10.2026; ausschließlich lokale Quellen gelesen, keine Builds oder Netztests. Ziel: Funktions-, Design- und UX-Gleichheit mit dem vorhandenen iOS-Code; `ios/` bleibt unverändert.
Quellenrang: aktueller Code und `docs/ENTSCHEIDUNGEN.md:60` (einschließlich späterer Einträge) vor älteren Konzeptteilen; `docs/STAND.md:19`, `ios/docs/gedanken/KONZEPT.md:1`, `ios/docs/gedanken/EVAL.md:422`, `ios/docs/TESTFLIGHT.md:24` und `ios/README.md:1` geben Kontext. README „nur Diktat“, Konzept „Aufgaben-Chip“ und alte Versions-/Testzahlen sind teilweise überholt; Prompt v6, Aufgaben-Reiter und Widgets sind vorhanden. `docs/prototypes/paply-ios/gedanken-richtungen.html:6` ist eine frühere Richtungsstudie, keine aktuelle Pixelspezifikation.

## 1. Vollständige Modulkarte

Pfade relativ zu `ios/`; **K/** = `PaplyKit/Sources/PaplyKit/`. Namen ohne Endung meinen `.swift`; Klammern nennen physische Zeilen einschließlich Kommentare/Leerzeilen, Gruppen zählen jede Datei genau einmal. **a** = Logik nach JVM `:core`; **b** = Android-/Adapter-Neubau mit benanntem Gegenstück (enthaltene Regeln trotzdem übernehmen); **c** = iOS-Mechanik entfällt; **d** = nach V1. Standardbibliothek, Geometrietypen und Nebenläufigkeit werden sinngleich übersetzt, keine Swift-APIs in Kotlin nachgebaut.
| Quelldateien (Zeilen je Datei) | Kategorie | Zweck / Android-Ziel |
| --- | :---: | --- |
| `K/PublicAPI` (197) | a | Definiert Einstellungen, Ergebnisse und Fehlercodes der Diktat-Pipeline. |
| `K/Text/PolishPrompt` (113); `K/Text/WhisperPrompt` (107); `K/Text/CodeSwitchPrimer` (65) | a | Baut unveränderte Polier- und Whisper-Prompts samt Sprachwechsel-Beispielen. |
| `K/Text/Pattern` (45); `K/Text/TextAnalysis` (207); `K/Text/Lexicon` (104); `K/Text/EditCheck` (348); `K/Text/PolishSafetyNet` (169); `K/Text/TranscriptCleanup` (88) | a | Prüft Texttreue, Zahlen und Verneinungen und entfernt Halluzinationen sowie Prompt-Echos. |
| `K/Text/LanguageGuard` (61) | a | Entscheidet je Stück Sprache und Korrekturversuch; Geräte-Locale als Eingabe injizieren. |
| `K/Text/LanguageDetection` (10) | b | Ersetzt NLLanguageRecognizer durch einen lokalen Sprachdetektor hinter einem Port. |
| `K/Audio/ChunkPlanner` (49); `K/Audio/MicSilence` (254); `K/Audio/SilenceFilter` (240); `K/Audio/VoiceActivityDetector` (351) | a | Erkennt Stimme, Stille und tote Mikrofone und plant Schnitte; Accelerate-Vektorrechnung mathematisch gleich in Kotlin abbilden. |
| `K/Audio/AudioEncoder` (102) | b | Kodiert PCM16/WAV/FLAC; Android-Codec hinter Encoder-Port, WAV-Rechnung in :core. |
| `K/Audio/ObjCException` (10) | c | Fängt Objective-C-Ausnahmen; Kotlin/JVM hat diese Laufzeit nicht. |
| `K/DictationPipeline` (482) | b | Orchestriert Aufnahme-Stücke bis Polieren; Regeln nach :core, Tasks/Lock/HTTP/Encoder über Coroutines und Ports ersetzen. |
| `K/Groq/GroqModels` (51) | a | Fixiert Modelle, Reasoning-Optionen, Tokenbudget und Whisper-Sprachcodes. |
| `K/Groq/GroqClient` (593); `K/Groq/GroqConnection` (81); `K/Groq/PolishService` (196) | b | Implementiert HTTP/SSE, Vorwärmen, Modellcache und Wiederholen; geteilter JVM-HTTP-Client mit abbrechbaren Coroutines, Parser/Regeln nach :core. |
| `K/Display/RawTitle` (84); `K/Display/TaskAgenda` (163); `K/Display/TaskDigest` (120); `K/Display/TaskReminderPlan` (279); `K/Display/TopicColorRegister` (138) | a | Leitet Titel, Aufgabenlisten, Widget-Inhalt, Erinnerungsplan und stabile Themenfarben aus Daten ab. |
| `K/Display/TopicImageFile` (206) | b | Prüft und erzeugt lokale Themenbilder; Android Bitmap/EXIF-Verarbeitung statt ImageIO. |
| `K/Thoughts/Contracts` (471) | a | Definiert Gedanken, Themen, Aufgaben, Besitzregeln und Verarbeitungsschnittstellen. |
| `K/Thoughts/Model/SupportTypes` (66); `K/Thoughts/Model/ThoughtCoding` (100) | a | Kodiert JSON und Hilfstypen; JVM-Serializer, Mutex/Flow und identische Hash-Regeln verwenden. |
| `K/Thoughts/AI/ThoughtPrompt` (324); `K/Thoughts/AI/ThoughtSchema` (54); `K/Thoughts/AI/SpokenNumbers` (306); `K/Thoughts/AI/SpokenTime` (306); `K/Thoughts/AI/TaskText` (246); `K/Thoughts/AI/TopicHygiene` (313) | a | Definiert Ordnungsprompts, Schemata, Zahlen-/Uhrzeitregeln, Aufgabenbereinigung und Themenpflege. |
| `K/Thoughts/AI/ThoughtValidator` (487) | b | Validiert KI-Felder; Prüfregeln nach :core, NLTagger-Lemmata durch lokalen NLP-Port ersetzen. |
| `K/Thoughts/AI/ThoughtStructurer` (247) | b | Steuert Schema-Aufrufe und begrenzte Wiederholungen; Entscheidungslogik nach :core, HTTP/Timer/Ledger injizieren. |
| `K/Thoughts/Budget/TokenLedger` (125) | b | Reserviert und verbucht Tokens/Audio persistent; Rechenregeln nach :core, atomare JVM-Dateiablage als Adapter. |
| `K/Thoughts/Local/Search` (205); `K/Thoughts/Local/LocalIndex` (196); `K/Thoughts/Local/TopicIndex` (97) | a | Berechnet lokale Suche, BM25/Index und aktive bzw. vorläufige Themen. |
| `K/Thoughts/Local/CandidateFinder` (390) | b | Wählt semantisch und lexikalisch Kandidaten; Ranking nach :core, NLP/Embedding/Speicher injizieren. |
| `K/Thoughts/Local/EmbeddingIndex` (202); `K/Thoughts/Local/Keywords` (93); `K/Thoughts/Local/TopicMentions` (223) | b | Ermittelt Vektoren, Lemmata und Namenshinweise mit NaturalLanguage; lokale Android-NLP-Adapter plus unveränderte Listen/Ranking. |
| `K/Thoughts/Map/MapLayout` (1159); `K/Thoughts/Map/MapViewport` (163); `K/Thoughts/Map/MapInbox` (184) | a | Berechnet Kartenanordnung, Kamera und Eingangsflüge; CGPoint/CGRect durch eigene JVM-Geometrietypen ersetzen. |
| `K/Thoughts/Map/MapAnchorFile` (128) | b | Speichert feste Kartenplätze samt Lesezustand; MapAnchorState nach :core, Dateiadapter neu. |
| `K/Thoughts/Processing/ThoughtProcessor` (1010); `K/Thoughts/Processing/PartSplitter` (159) | b | Verarbeitet eine persistente Queue und Textteile; Regeln nach :core, Satzsegmentierung/NSDataDetector/Timer/IO ersetzen. |
| `K/Thoughts/Processing/FileTranscriber` (98) | b | Verschriftlicht gesicherte Audiodateien über dieselbe Pipeline; WAV-/Altformat-Decoder statt AVAudioFile. |
| `K/Thoughts/Processing/ThoughtTrace` (64) | a | Definiert strukturierte Diagnoseereignisse ohne Nutzertexte. |
| `K/Thoughts/Processing/TopicHygieneRunner` (82) | b | Fragt selten Zusammenführungsvorschläge ab; Scheduler, HTTP und persistente Ablage als Adapter. |
| `K/Thoughts/Store/ThoughtStore` (888); `K/Thoughts/Store/FileSafety` (88); `K/Thoughts/Store/WAVWriter` (176) | b | Sichert Gedanken und laufendes WAV absturzfest; JVM-Dateioperationen/fsync plus Android-Dateischutz und Backup-Regeln. |
| `App/PaplyApp` (125) | b | Verdrahtet Lifecycle, Navigation und Dienste; Application/Activity und Compose-Einstieg. |
| `App/Intents/PaplyShortcuts` (19) | b | Veröffentlicht Systemaktionen; Android Shortcuts/Quick-Settings-Einstiege. |
| `App/Session/AudioEngineHost` (393); `App/Session/AudioTapProcessor` (323); `App/Session/DeviceMonitor` (93); `App/Session/NetworkMonitor` (44) | b | Betreibt Mikro, Resampling, Vorlauf, Routen und Netzstatus; AudioRecord/AudioManager/ConnectivityManager. |
| `App/Session/SessionController` (1502) | b | Verwaltet Diktat und konkurrierende Aufnahmen; neuer IME-/Service-Zustandsautomat, iOS-Bereitschaft darin streichen. |
| `App/Session/SharedIO` (12) | c | Aliasiert iOS-App-Group-Befehle; entfällt bei gemeinsamem Android-Prozess. |
| `App/Session/ShortcutBridge` (167); `App/Session/ThoughtBridge` (386); `App/Session/ThoughtCapture` (630) | b | Koordiniert Schnellstart, Gedankenaufnahme und Live-Anzeigen; FGS, Benachrichtigung und idempotente Android-Aktionen. |
| `App/Store/AppSettings` (345); `App/Store/HistoryStore` (129); `App/Store/Keychain` (48); `App/Store/SetupStatus` (136) | b | Verwaltet Einstellungen, Verlauf, Geheimnis und Einrichtung; DataStore/Dateiablage, Android Keystore und Berechtigungs-/IME-Status. |
| `App/Thoughts/ThoughtsModel` (797); `App/Thoughts/ThoughtsEnvironment` (306); `App/Thoughts/MapAnchors` (106); `App/Thoughts/TopicImages` (475); `App/Thoughts/TaskWidgetSync` (214) | b | Verbindet Speicher, Queue, Kartenanker, Bilder und Widgets mit der App; ViewModel/StateFlow, WorkManager, Bildpicker und Widget-Updates. |
| `App/Reminders/TaskReminders` (705); `App/Reminders/TaskReminderViews` (175) | b | Plant Erinnerungen samt Einwilligung und Aktionen; Alarm-/Notification-Adapter und Compose-Einstellungen. |
| `App/Reminders/TaskReminderDebug` (44) | d | Erzeugt Entwickler-Testmitteilungen; nach V1. |
| `App/UI/RootView` (216); `App/UI/SettingsView` (917); `App/UI/DictationTab` (291); `App/UI/HistoryDetailView` (125); `App/UI/Components` (91); `App/UI/BetaViews` (69) | b | Stellt Navigation, Einstellungen, Diktatverlauf und Beta-Zustände dar; Compose nach UI-Inventar, Entwicklerteile von Settings erst später. |
| `App/UI/FlashView` (126) | c | Zeigt das iOS-Aufblitzen beim Aktivieren der Mikro-Sitzung; Android-IME soll selbst aufnehmen. |
| `App/UI/TestPageView` (238); `App/UI/DiagnosticsView` (170) | d | Bietet Höhenmessung und Diagnoseansicht für Entwickler; nach V1, technische Logs bleiben V1. |
| `App/UI/Thoughts/CaptureFlow` (308); `App/UI/Thoughts/CaptureBar` (252); `App/UI/Thoughts/CaptureView` (293); `App/UI/Thoughts/EchoOrb` (242) | b | Zeigt Aufnahmezustände, Leiste, Vollbild und animierte Kugel; Compose/StateFlow mit denselben Zustands- und Zeitregeln. |
| `App/UI/Thoughts/ThoughtsHome` (442); `App/UI/Thoughts/ThoughtsHomeHeader` (116); `App/UI/Thoughts/ThoughtsEmptyState` (245); `App/UI/Thoughts/SetupCard` (250) | b | Zeigt Gedankenstart, Suche, Leerzustand und Einrichtung; Compose-Screens und Android-Anleitungen. |
| `App/UI/Thoughts/ThoughtCard` (373); `App/UI/Thoughts/ThoughtRow` (363); `App/UI/Thoughts/ThoughtDetailView` (655); `App/UI/Thoughts/ThoughtOriginalView` (54); `App/UI/Thoughts/ThoughtTasksView` (183) | b | Zeigt, bearbeitet und verknüpft Gedanken samt Original und Aufgaben; Compose-Ansichten. |
| `App/UI/Thoughts/TasksTab` (603); `App/UI/Thoughts/TaskWidgetPreview` (160) | b | Zeigt Aufgaben nach Fälligkeit und Widget-Vorschau; Compose mit gemeinsamer Darstellungslogik. |
| `App/UI/Thoughts/TopicSheets` (548); `App/UI/Thoughts/TopicsEditView` (475); `App/UI/Thoughts/TopicPanel` (516); `App/UI/Thoughts/TopicPalette` (312); `App/UI/Thoughts/TopicImageViews` (73) | b | Bearbeitet Themen, Bilder, Verknüpfungen und Papierkorb; Compose-Sheets, Panel und System-Fotoauswahl. |
| `App/UI/Thoughts/ThoughtsUI` (794) | b | Bündelt Farben, Motion, Haptik, Datumstexte und Komponenten; Compose-Tokens und Android-Haptik, Datumsregeln extrahieren. |
| `App/UI/Thoughts/ThoughtsDebug` (320); `App/UI/Thoughts/ThoughtsDeveloperViews` (141) | d | Bietet Demo-Daten und Entwicklerkontrollen; nach V1, keine Beispieldaten in echte Speicher übernehmen. |
| `App/UI/Thoughts/Map/ThoughtMapView` (243); `App/UI/Thoughts/Map/MapCanvas` (1081); `App/UI/Thoughts/Map/MapStageView` (460); `App/UI/Thoughts/Map/MapScene` (430); `App/UI/Thoughts/Map/MapStyle` (104); `App/UI/Thoughts/Map/MapInboxOrb` (243) | b | Rendert Karte, Gesten, Zoom, Themenpanel und Eingangsanimation; Compose Canvas mit JVM-Layoutkern. |
| `App/UI/Thoughts/Map/MapDebugScreen` (315) | d | Zeigt Karten-Testfälle und Messungen; nach V1. |
| `Keyboard/KeyboardViewController` (978); `Keyboard/PanelView` (433) | b | Startet Diktat beim Tastaturwechsel und setzt Text ein; InputMethodService/InputConnection, Compose-Panel und Wechsel zur vorigen IME. |
| `Keyboard/AppOpener` (113) | c | Öffnet die iOS-Host-App für Mikro-Bereitschaft; dieser Umweg soll auf Android entfallen. |
| `Widgets/PaplyWidgets` (113); `Widgets/ThoughtControl` (31); `Widgets/ThoughtWidget` (143); `Widgets/TasksWidget` (104); `Widgets/ThoughtLiveActivity` (254) | b | Bietet Diktat/Gedanken-Steuerung, Aufgaben-Widgets und Aufnahmeanzeige; Glance/RemoteViews, Quick Settings und sichtbare Aufnahmebenachrichtigung. |
| `Shared/Core/BetaFeatures` (55); `Shared/Core/TaskSnapshot` (234) | a | Definiert Beta-Startschutz und Widget-Snapshot/Abhaken; Defaults-Zugriff injizieren. |
| `Shared/Core/Brand` (97) | b | Enthält Markenfarben, Logo-Geometrie und Federn; Compose-Farben/Pfade bei identischen Werten. |
| `Shared/Core/AppGroup` (93); `Shared/Core/DarwinBus` (91); `Shared/Core/LevelChannel` (122); `Shared/Core/SharedSettings` (117); `Shared/Core/SharedStore` (88); `Shared/Core/SharedModels` (191) | c | Implementiert iOS-Container, Signale, Pegeldatei und Prozess-Handshake; Android-intern StateFlow/Service-Zustand, fachliche Ereignisse übernehmen. |
| `Shared/Core/TaskWidgetFiles` (115) | b | Sichert Widget-Snapshot und idempotente Erledigt-Befehle; Android-Datei-/Repository-Adapter statt App Group. |
| `Shared/Core/Diag` (152); `Shared/Core/MonoClock` (35) | b | Protokolliert inhaltsfreie Abläufe und monotone Zeiten; Android-Logging und elapsedRealtimeNanos. |
| `Shared/Core/ProcessMetrics` (40); `Shared/Core/StorageSelfTest` (91) | d | Misst Prozessressourcen und prüft App-Group-Speicher; Android-Diagnose erst nach V1. |
| `Shared/Intents/TaskIntents` (106); `Shared/Intents/ThoughtIntents` (289); `Shared/Intents/ToggleDictationIntent` (115) | b | Verbindet Systemaktionen mit Aufnahme und Aufgaben; PendingIntent/Receiver/Service statt AppIntent und Face-ID-Schalter. |
| `Shared/UI/BrandUI` (74); `Shared/UI/LucideGlyph` (354); `Shared/UI/LucideIcons` (141); `Shared/UI/TopicIconKey` (36); `Shared/UI/TaskWidgetViews` (616) | b | Zeichnet Marke, Lucide-Icons und Widget-Ansichten; Compose-Vektoren bzw. RemoteViews mit gleichen Formen. |
| `Shared/UI/DictationActivity` (21); `Shared/UI/ThoughtActivity` (24) | c | Definiert ActivityKit-Attribute; keine Android-ActivityKit-Laufzeit, äquivalenter Status gehört ins Notification-Modell. |

Umfang: 154 Swift-Dateien, **39.040 Zeilen**: K 13.563; App 20.011; Keyboard 1.524; Widgets 645; Shared 3.297. Kategorie a: **7.776** Zeilen direkt übertragbarer Logik; b: 28.897; c: 1.008; d: 1.359. Weitere Logik steckt in b; die 7.776 Zeilen sind deshalb eine konservative Untergrenze, keine Aufwandsschätzung der gesamten Logik. UI-nahe Ordner `App/UI` + `Keyboard` + `Widgets` + `Shared/UI`: **16.272 Zeilen**, inklusive Controller/Debug; übrige **22.768** sind Kern, Integration und Infrastruktur, nicht alles reine Logik.
Außerhalb der Swift-Zählung: `App`, `Keyboard`, `Widgets` enthalten Info.plist/entitlements/PrivacyInfo (**b**, AndroidManifest, Rechte, Backup-/Datenschutzregeln); Asset-Kataloge in App/Widgets (**b**, Android-Ressourcen). `electron-menubar/brand/{mark,app-icon,app-icon-small,app-icon-windows,tray-color,tray-template,wortmarke,wortmarke-hell}.svg` nur als Markenquelle lesen. `ios/PaplyKit/Sources/paply-bench/` (**d**) gehört nicht in die Android-App.

## 2. Unverändert zu übernehmende Quellen

Wörtlich bleiben Prompt-Inhalte, Modell-IDs, Listen/Regex und fachliche Werte; nur Syntax/API und notwendige Plattformmechanik ändern sich. Referenzen zeigen jeweils den Einstieg; auch weitere Regeln derselben Datei gehören zum Port. Keine Prompt-Texte werden hier dupliziert.
| Datei:Zeile | Verbindlicher Inhalt |
| --- | --- |
| `K/Text/PolishPrompt.swift:10`, `K/Text/PolishPrompt.swift:32`, `K/Text/PolishPrompt.swift:55` | Vollständiger Systemprompt, Begriffe, Unsicherheitsmarkierung und Aufbau der Nutzernachricht samt Verlauf. |
| `K/Text/WhisperPrompt.swift:7`, `K/Text/CodeSwitchPrimer.swift:19` | Promptbudget, Token-Schätzung, Begriffs-/Vorstück-Anteile und alle mehrsprachigen Beispielbausteine (Codebudget ist 200, nicht die in älteren Texten genannte Whisper-Grenze 224). |
| `K/Thoughts/AI/ThoughtPrompt.swift:20`, `K/Thoughts/AI/ThoughtPrompt.swift:24`, `K/Thoughts/AI/ThoughtPrompt.swift:91` | Version, sämtliche Systembausteine sowie Kurzprompt für Folgeteile übernehmen. |
| `K/Thoughts/AI/ThoughtPrompt.swift:156`, `K/Thoughts/AI/ThoughtPrompt.swift:191`, `K/Thoughts/AI/ThoughtPrompt.swift:229`, `K/Thoughts/AI/ThoughtSchema.swift:1` | Kontextkappen, Aliasse, lokale Aufnahmezeit, Ausgabebudget, Kürzungsreihenfolge und beide strikten Schemata erhalten. |
| `K/Thoughts/AI/TopicHygiene.swift:260`, `K/Thoughts/AI/TopicHygiene.swift:270`, `K/Thoughts/AI/TopicHygiene.swift:275` | Hygiene-Schema, Systemprompt und Nutzer-Nachricht unverändert übernehmen. |
| `K/PublicAPI.swift:22`, `K/Groq/GroqModels.swift:5`, `K/Thoughts/AI/ThoughtStructurer.swift:26`, `K/Thoughts/Processing/TopicHygieneRunner.swift:8` | Alle Standard-/Ausweichmodelle und modellabhängigen Reasoning-Optionen fixieren. |
| `K/Groq/GroqClient.swift:11`, `K/Groq/GroqClient.swift:132`, `K/Groq/GroqClient.swift:166`, `K/Groq/GroqClient.swift:210`, `K/Groq/GroqClient.swift:297`, `K/Groq/GroqClient.swift:518` | Fehlerklassen, Transport-/Leerlaufgrenzen, Retry-After-Auswertung und Wiederholungen erhalten. |
| `K/Groq/PolishService.swift:69`, `K/Groq/PolishService.swift:146`, `K/Groq/GroqConnection.swift:5` | Modellcache, Ausweichregeln, Vorwärmen und Schlüsselprüfung erhalten. |
| `K/Text/LanguageGuard.swift:16`, `K/Text/LanguageGuard.swift:21`, `K/Text/LanguageGuard.swift:41`, `K/Text/CodeSwitchPrimer.swift:59`, `App/Store/AppSettings.swift:1` | Sprachwache: ≤ 5 s gesprochene Zeit bevorzugt gültige Vorstücksprache, sonst Hauptsprache; länger automatisch, fremd außerhalb Nutzerliste einmal wiederholen, Gerätesprachen-Ermittlung neu anbinden. |
| `K/Text/Pattern.swift:1`, `K/Text/TextAnalysis.swift:1`, `K/Text/Lexicon.swift:14` | Unicode-/Regex-Semantik und alle Füllwort-, Verneinungs-, Korrektur- und Metaantwortlisten erhalten. |
| `K/Text/EditCheck.swift:10`, `K/Text/EditCheck.swift:130`, `K/Text/EditCheck.swift:208`, `K/Text/EditCheck.swift:310` | Zahlen, Selbstkorrektur, Schreibvarianten, Zusammenziehungen und Edit-Abgleich unverändert übersetzen. |
| `K/Text/PolishSafetyNet.swift:6`, `K/Text/PolishSafetyNet.swift:71`, `K/Text/TranscriptCleanup.swift:8` | Thinking-/Steuertoken-Regex, getrennte Diktat-/Gedanken-Schwellen und Echo-/Zusammenfüge-Regeln erhalten. |
| `K/Audio/VoiceActivityDetector.swift:27`, `K/Audio/VoiceActivityDetector.swift:165`, `K/Audio/ChunkPlanner.swift:17`, `K/Audio/MicSilence.swift:1` | Sämtliche VAD-, Pausen-, Frequenz-, Stille- und Mikro-Neustartschwellen samt Fensterrechnung übernehmen. |
| `K/Audio/SilenceFilter.swift:69`, `K/Audio/SilenceFilter.swift:98`, `K/Audio/SilenceFilter.swift:143`, `K/Audio/AudioEncoder.swift:7` | Halluzinationslisten/-Regex, Segmentfilter sowie Abtastrate und PCM-Konvertierung erhalten. |
| `K/DictationPipeline.swift:34`, `K/DictationPipeline.swift:251`, `K/DictationPipeline.swift:417`, `App/Session/AudioTapProcessor.swift:15`, `App/Store/HistoryStore.swift:29` | Stückgrenzen, Vorstückwartezeit, Fehlerplan, Vorlauf und Verlauf-/Kontextgrenzen erhalten; Kontext sind die letzten drei Rohdiktate jünger als 30 min (`App/Store/HistoryStore.swift:109`). |
| `K/Thoughts/AI/ThoughtValidator.swift:53`, `K/Thoughts/AI/ThoughtValidator.swift:147`, `K/Thoughts/AI/ThoughtValidator.swift:255`, `K/Thoughts/AI/ThoughtValidator.swift:279`, `K/Thoughts/AI/ThoughtValidator.swift:347` | Feldgrenzen, Zitat-/Wortbeleg, Aufgaben-/Link-Schwellen, Wortlisten und Normalisierungen erhalten. |
| `K/Thoughts/AI/SpokenNumbers.swift:135`, `K/Thoughts/AI/SpokenNumbers.swift:169`, `K/Thoughts/AI/SpokenTime.swift:77`, `K/Thoughts/AI/TaskText.swift:35` | Alle Zahlen-/Monats-/Uhrzeitlisten, Parser, Füllwort-/Präpositionslisten und Negationsschutz erhalten. |
| `K/Thoughts/AI/TopicHygiene.swift:7`, `K/Thoughts/AI/TopicHygiene.swift:29`, `K/Thoughts/AI/TopicHygiene.swift:101`, `K/Thoughts/AI/TopicHygiene.swift:207` | Themenlimit, verbotene Namen, sichere Doppel-Schranke und Hygiene-Intervalle/-Schwellen erhalten. |
| `K/Thoughts/Local/CandidateFinder.swift:12`, `K/Thoughts/Local/Keywords.swift:77`, `K/Thoughts/Local/LocalIndex.swift:1`, `K/Thoughts/Local/Search.swift:1`, `K/Thoughts/Local/TopicIndex.swift:7`, `K/Thoughts/Local/TopicMentions.swift:1` | Ranking, BM25, Rückbezug, Treffer-/Altersgrenzen und sämtliche Such-/Namens-/Stoppwortregeln erhalten. |
| `K/Thoughts/Budget/TokenLedger.swift:12`, `K/Thoughts/AI/ThoughtStructurer.swift:80`, `K/Thoughts/Processing/ThoughtProcessor.swift:17`, `K/Thoughts/Processing/ThoughtProcessor.swift:390`, `K/Thoughts/Processing/TopicHygieneRunner.swift:19` | Budgets, Reservierung, Warte-/Retry-Regeln und Priorität des Diktats erhalten. |
| `K/Thoughts/Processing/PartSplitter.swift:13`, `K/Thoughts/Processing/PartSplitter.swift:87`, `K/Thoughts/Processing/ThoughtProcessor.swift:877`, `K/Thoughts/Processing/ThoughtProcessor.swift:933` | Teilegrenzen, Rohtext-Absätze, Selbstkorrektur-/Aufgaben-Deduplikation und Fälligkeitsregeln erhalten. |
| `K/Thoughts/Contracts.swift:7`, `K/Thoughts/Contracts.swift:234`, `K/Thoughts/Store/ThoughtStore.swift:57`, `K/Thoughts/Store/ThoughtStore.swift:704` | IDs, Beschreibungslänge, Papierkorbfrist und Recovery-/Aufräumgrenzen erhalten. |
| `K/Display/TaskReminderPlan.swift:1`, `K/Display/TaskAgenda.swift:1`, `K/Display/TaskDigest.swift:1`, `K/Display/RawTitle.swift:1`, `Shared/Core/TaskSnapshot.swift:1` | Kalender-/Uhrzeitlogik, Sortierung, Titelkürzung, Widget-Auswahl und Abhaken identisch abbilden. |
| `App/Session/ThoughtCapture.swift:80`, `App/UI/Thoughts/CaptureFlow.swift:1`, `App/Session/ThoughtBridge.swift:1` | Doppeldruckschutz, Zehn-Minuten-Grenze, Warnung/Nudges und Anzeige-/Widerrufsfristen erhalten. |
| `K/Thoughts/Map/MapLayout.swift:1`, `K/Thoughts/Map/MapViewport.swift:1`, `K/Thoughts/Map/MapInbox.swift:1`, `K/Display/TopicColorRegister.swift:1`, `K/Display/TopicImageFile.swift:1` | Geometrie, Zoom-/Flugparameter, Farbzuordnung und Bildgrenzen erhalten. |

## 3. Groq-Verträge und Upload während des Sprechens

- Basis `https://api.groq.com/openai/v1/`, authentifizierte Anfragen mit `Authorization: Bearer …`; keine Inhalte/Keys im Log. Gemeinsamer Transport ohne Cookies/Cache; Leerlauf standardmäßig 60 s, Ressourcenlimit faktisch 30 min, kein absichtlicher kurzer Gesamt-Abbruch beim Polieren (`K/Groq/GroqClient.swift:132`).
- `GET models`: aktive IDs aus `data`, kein automatischer Listen-Retry; Cache pro Schlüssel-Hash 5 min, veraltete Liste sofort liefern und auffrischen. Vorwärmen: Liste falls fehlt/älter als 6 h, sonst `HEAD models` ohne Schlüssel. Schlüsselprüfung: 15-s-Leerlauf, vorübergehende Fehler einmal wiederholen, Retry-After-Obergrenze 0; 429 gilt als gültiger Key, 401/403 ungültig (`K/Groq/GroqConnection.swift:18`).
- `POST audio/transcriptions`: Multipart `file` (`audio.flac`/`audio/flac`, Fallback `audio.wav`/`audio/wav`), `model=whisper-large-v3`, `response_format=verbose_json`, `temperature=0`, optional `language`, `prompt`; 16 kHz mono PCM16. Timeout `max(30,15+5*Audiominuten)` s. Antwort: Text, Sprache, Dauer, optionale Segmente einschließlich Wahrscheinlichkeiten; keine automatische Whisper-Modellumschaltung. Ein Sprachwache-Neuversuch nutzt wieder denselben Transkriptionsvertrag; scheitert er, bleibt das erste Ergebnis mit `redoFailed` erhalten (`K/DictationPipeline.swift:281`). Turbo ist eine Entwickler-Testoption (`K/Groq/GroqClient.swift:301`).
- Transkriptions-Transport: maximal ein Retry bei Netzwerk, ungültigem HTTP-Antworttyp, 408/409/429/5xx; sonst keiner. Ohne Retry-After 0,4 s, bei 429 1 s; Header-Zahl/HTTP-Datum vor Groq-Fehlertext, über 20 s kein Retry. JSON-Dekodierung erfolgt NACH `sendWithRetry`, ein defekter erfolgreicher JSON-Body löst dort keinen zweiten Versand aus (`K/Groq/GroqClient.swift:210`, `K/Groq/GroqClient.swift:314`).
- Polieren: `POST chat/completions`, `model`, `messages`, `temperature=0`, `max_tokens=min(32768,max(4096,ceil(UTF16-Länge/3)*2))`, `stream=true`; Qwen `reasoning_effort=none`, OSS `reasoning_effort=low, reasoning_format=hidden`. SSE nur an LF trennen; JSON-Fallback lesen, fehlendes DONE UND finish_reason ist unvollständig. Nicht-stop-Finish oder Sicherheitsnetz-Verstoß → Rohtext (`K/Groq/GroqClient.swift:368`, `K/Groq/PolishService.swift:180`).
- Polieren nimmt verfügbares bevorzugtes Modell, bei fehlender Modellliste zunächst das Wunschmodell. Genau eine zweite Chat-Anfrage: fehlendes Modell oder langes 429 → verfügbares Ausweichmodell; sonst wiederholbarer Fehler → dasselbe Modell nach Wartezeit. Kein Retry wegen abgelehntem Inhalt. Fehler/Abbruch bleiben unterscheidbar (`K/Groq/PolishService.swift:146`).
- Gedanken: gleicher Chat-Endpunkt ohne Stream, System-/User-Nachricht, `temperature=0.1`, `reasoning_effort=low`, `max_completion_tokens`, `response_format.type=json_schema` mit Name/Schema/`strict=true`; 120-s-Leerlauf, Antwort inklusive `usage`. Primär `openai/gpt-oss-120b`, Ausweich `openai/gpt-oss-20b`; niemals Qwen. Ausgabebudget `min(6000,max(1500,ceil(ceil(UTF8-Bytes/3)*1.3)+900))`, Kürzung exakt aus `K/Thoughts/AI/ThoughtPrompt.swift:191`; Request-Obergrenze 7.600 geschätzte Tokens. Finder liefert maximal 7 Kandidaten, Prompt akzeptiert höchstens 8; diese zwei Grenzen nicht vereinheitlichen.
- Gedanken-Retries sind getrennte einmalige Budgets: kurzes 429 mit bekanntem Retry-After ≤ 20 s → gleiches Modell; danach/lange/ohne Retry-After → einmal Fallback; erneut limitiert → mindestens 15 min warten. Fehlendes Modell → einmal Fallback, dann Rohtext; 401/403 → auf geänderten Schlüssel warten. Schemafehler/ungültige Ausgabe/Finish ≠ stop → einmal `medium`, dann Rohtext; mehrere Retry-Arten können zusammen mehr als zwei Aufrufe ergeben. Netz/5xx → persistente Queue (`K/Thoughts/AI/ThoughtStructurer.swift:91`).
- Queue: exponentiell 30 s bis 600 s; Server-/unlesbare Transkription nach 5 Fehlversuchen Aufmerksamkeit, Netzwerk erst bei zusätzlich ≥ 24 h Alter; bereits vorhandener Rohtext bleibt nutzbar. Ledger: gleitend 24 h, 80.000 Tokens/7.200 Audiosekunden; pro Modell/Minute 7.600 Tokens bzw. 1.800 Audiosekunden und 15 Anfragen; bei vollem Minutenfenster 61 s warten, Tagesbudget mindestens 60 s bzw. bis zur ältesten auslaufenden Buchung. Erst reservieren, dann tatsächlichen Verbrauch buchen, unklaren Verbrauch vorsichtig geschätzt lassen (`K/Thoughts/Processing/ThoughtProcessor.swift:390`, `K/Thoughts/Budget/TokenLedger.swift:78`).
- Hygiene: ab 8 aktiven Themen, frühestens alle 7 Tage, höchstens 5 lokale Paare → ein Aufruf an OSS-20b, `low`, 1.200 Completion-Tokens, `topic_pairs`; höchstens 2 geprüfte Vorschläge, nie automatisch anwenden, kein Netzwerk-Retry (`K/Thoughts/Processing/TopicHygieneRunner.swift:28`).
- Stücke: 0,5 s RAM-Vorlauf; Float32→PCM16 und VAD mit 30-ms-Fenstern. Vor echter Sprache kein Audio-Upload; nach ≥ 10 s Stücklänge an ≥ 0,6-s-Pause schneiden, nach 20 s genügen 0,4 s, Schnitt mitten in der Pause. FLAC/WAV-Stücke laufen schon während weiterer Aufnahme; maximal 1,5 s auf Vorstücktext für Promptkontext warten, sonst ohne ihn senden (`K/DictationPipeline.swift:198`).
- Abschluss wartet auf laufende Stücke, übernimmt erfolgreiche Ergebnisse in Reihenfolge, fasst gescheiterte/nicht gesendete Bereiche zusammen und lädt nur offene Bereiche/Rest nach; endgültiger Stückfehler stoppt neue Live-Stücke. Teile maximal 600 s, Schnitt an leisester Stelle der letzten 30 s vor Grenze; Stille am Ende kann entfallen. Cleanup/Sprachwache pro Stück, Polieren erst auf Gesamttext; `retry()` bewahrt erfolgreiche Teile, `cancel()` bricht Uploads ab (`K/DictationPipeline.swift:330`).
- Gedanken können ebenfalls live transkribieren, gleichzeitig WAV dauerhaft sichern; Polieren ist dabei aus, Ordnung folgt einmal auf Gesamtrohtext. Nach Neustart/Live-Fehler Dateiweg ohne Stücke-Upload; Queue wartet höchstens 15 min auf erwartetes Live-Ergebnis. Lange TEXTE werden intern für KI geteilt (> 1.800 geschätzte Tokens, ≤ 1.400 pro Teil, 60 s Abstand); daraus bleibt EIN Gedanke, kein automatisches Aufteilen in mehrere Gedanken (`K/Thoughts/Processing/FileTranscriber.swift:20`, `K/Thoughts/Processing/PartSplitter.swift:13`).

## 4. Gedanken: Modell, Speicher und Versionierung

- App-private Wurzel iOS `Library/Application Support/Gedanken` (`App/Thoughts/ThoughtsEnvironment.swift:24`), Android entsprechender interner Ordner; kein Server, keine gemeinsame Datenbank. `thoughts/<id>/thought.json`, unveränderliches `source.json`, `ai-result.json`, `ai-parts.json`, temporär `audio.wav`; Altbestand `audio.m4a`. Oben `topics.json`, `topics.prev.json`, `topic-suggestions.json`, `ledger.json`; Kartenanker/Farben/Bilder und Widget-Snapshot als getrennte Ableitungen.
- `Thought`: schemaVersion/id/kind, createdAt/durationMs/trigger/state, title/text/topicId mit jeweils Owner, textIsRaw, tasks/links/languages/keywords, ai/audio/status, rev/updatedAt/deletedAt (`K/Thoughts/Contracts.swift:84`). IDs: s_/t_/k_ + 32 Kleinbuchstaben-Hex; Owner ai/user/system. Alle Enum-Rohwerte und null/fehlend-Semantik erhalten, UI-Texte nicht als IDs verwenden.
- `ThoughtTask`: id/text/quote/dueHint/dueAt/dueHasTime/done/doneAt/owner/createdAt; `ThoughtLink`: target/kind/reason/origin/createdAt; `Topic`: id/title/icon/owner/createdAt/mergedInto/note, Beschreibung normalisiert/maximal 200 Zeichen; beschriebene Themen gelten als nutzerdefiniert (`K/Thoughts/Contracts.swift:37`, `K/Thoughts/Contracts.swift:234`).
- `ThoughtSource`: text/sentences mit id und text/model/createdAt/languages/audioSeconds; Rohtext nur einmal schreiben. KI-Metadaten speichern Modell, Promptversion, Tokens, Zeitpunkt und Verwerfcodes; Status speichert Nachricht, Versuche und retryAt. Nutzerfelder nie von KI überschreiben; erledigte/bearbeitete Aufgaben, Änderungen während eines Aufrufs und gelöschte Gedanken respektieren (`K/Thoughts/Processing/ThoughtProcessor.swift:589`).
- JSON camelCase, sortierte Schlüssel, Datumswerte gerundete ganze Unix-Millisekunden, Decoder akzeptiert Zahlen als Double (`K/Thoughts/Model/ThoughtCoding.swift:5`); API-JSON mit snake_case ist ein separater Vertrag. `rev` erhöht sich bei Änderung; Topics-Dokument trägt zusätzlich declinedMerges/lastHygieneAt (`K/Thoughts/Store/ThoughtStore.swift:757`).
- Haltbarkeit: Nachbardatei → fsync → rename; Rohtext von Platte lesbar plus Verzeichnis synchronisieren, ERST DANN Audio löschen. Beschädigte Dateien als damaged-<ms>.json sichern, Topics-Backup nutzen; gesperrte/unlesbare Daten niemals als leeren Speicher überschreiben (`K/Thoughts/Store/FileSafety.swift:35`, `K/Thoughts/Store/ThoughtStore.swift:174`, `K/Thoughts/Store/ThoughtStore.swift:472`).
- Recovery repariert WAV-Kopf, recording→captured, entfernt tonlose Platzhalter und alte temporäre Dateien; transcribing/structuring werden fortgesetzt. KI-Ergebnis und Teilefortschritt vor Übernahme speichern, damit Neustart nicht erneut kostet; Audio auch im Papierkorb nach gesichertem Rohtext entfernen. Papierkorb 30 Tage; endgültiges Löschen räumt verwaiste Themen auf, manuell angelegte bislang leere Themen bleiben (`K/Thoughts/Store/ThoughtStore.swift:704`).
- Versionierung vorhanden, aber kein allgemeines Migrationssystem: Thought/Topics/AIResult schemaVersion=1, Promptversion=6 separat, Kartenanker version=1; optionale neue Felder und Default-Decoder sichern ausgewählte Altformate (etwa note/dueHasTime, Topics-Felder). Housekeeping entfernt altes m4a mit Rohtext. Keine iOS→Android-Import-/Sync-Migration implementiert; künftige Schema-Upgrades und unbekannte Versionen benötigen explizite Strategie, nicht still verwerfen.

## 5. Tests und Pflichtumfang

Es sind **Swift-Testing-Suiten (`@Suite`/`@Test`), keine XCTestCase-Suiten**. Statisch gezählt: **649 @Test-Deklarationen**; parametrisierte Fälle können mehr Ausführungen ergeben, kein Test wurde hier gestartet. Pfade relativ zu `ios/PaplyKit/Tests/PaplyKitTests/`; alle folgenden fachlichen Suiten sind V1-Pflicht als JVM-/Adaptertests, außer ausdrücklich entfällt.
| Testdatei | Suiten: ungefähre Testzahl | Zu prüfender Port |
| --- | --- | --- |
| `AudioTests.swift` | VoiceActivityDetectorTests 14; ChunkPlannerTests 7; AudioEncoderTests 5 | VAD, Schnitte, Encoder |
| `BetaFeaturesTests.swift` | BetaFeaturesTests 4 | Beta und Startabbruch |
| `DisplayTests.swift` | TopicColorRegisterTests 7; RawTitleTests 6 | Farbregister/Rohtitel |
| `FollowUpTests.swift` | EditAlignmentTests 2; SentenceStartNegationTests 1; LowFrequencyNoiseTests 5; StreamCompletenessTests 6; ShortTailTests 2; NumberFormatTests 3; TranscriptionTimeoutTests 1 | Edit-/Negationsregeln, Rauschen, Streamabschluss, Reststücke, Zahlen, Timeout |
| `GroqClientTests.swift` | TranscriptionClientTests 10; PolishServiceTests 15 | Multipart, HTTP-Fehler, Polieren/Modelle |
| `LanguageGuardTests.swift` | LanguageGuardTests 12 | Kurzsatz-/Vorstücksprache und Wiederholen |
| `MicSilenceTests.swift` | MicSilenceTests 16; NoSpeechStreakTests 8 | Digitalstille, Heilung und No-Speech-Folge |
| `ObjCExceptionTests.swift` | ObjCExceptionTests 2 | Entfällt (c); Android-Audioausfälle separat testen |
| `PipelineTests.swift` | PipelineTests 17 | Gesamte Diktat-Pipeline |
| `PromptTests.swift` | PolishPromptTests 6; WhisperPromptTests 5; GroqModelTests 5 | Prompts/Sprachwechsel/Modelloptionen |
| `ReviewTests.swift` | PipelineGuaranteeTests 3; RetryAndReleaseTests 5; ConcurrencyAndCancelTests 7; NoiseAndCutTests 3; NetRuleTests 8; TextJoinTests 4; ClientDetailTests 7; KeyCheckTests 1; TempFileTests 1 | Garantien, Retry, Abbruchrennen, Filter, Join, Key und Tempdateien |
| `SafetyNetTests.swift` | DesktopSafetyNetTests 8; MultilingualSafetyNetTests 9 | Texttreue in mehreren Sprachen |
| `SilenceFilterTests.swift` | RelativeVoiceActivityTests 6; SilenceFilterTests 25 | Rauschen/echte Stimme/Halluzinationsfilter |
| `TaskAgendaTests.swift` | TaskAgendaTests 13; SpokenTimeTests 12 | Fälligkeitsgruppen und gesprochene Uhrzeit |
| `TaskReminderPlanTests.swift` | TaskReminderPlanTests 20 | Planung, Zeitzone, Stale-Aktionen/Snooze |
| `TaskWidgetTests.swift` | TaskWidgetTests 13 | Snapshot, Sortierung, idempotentes Abhaken |
| `Thoughts/AIClientTests.swift` | AIChatStructuredTests 7; AIStructurerTests 17 | Striktes JSON und unabhängige Retry-Budgets |
| `Thoughts/AILedgerPromptTests.swift` | AILedgerTests 10; AIPromptTests 12; AITopicHygieneTests 8; AISafetyNetProfileTests 3; AIPromptConceptTests 1 | Ledger, Prompt-Pinning, Hygiene und Sicherheitsprofil |
| `Thoughts/AINumbersTests.swift` | AINumbersTests 12 | Zahlenwerttreue |
| `Thoughts/AIValidatorTests.swift` | AIValidatorTitleTests 10; AIValidatorTextTests 11; AIValidatorTopicTests 11; AIValidatorTaskTests 17; AIValidatorRelatedTests 9; AIValidatorPartTests 3; AITaskTextTests 8; AITaskWordingV4Tests 4; AIPrompt4FixtureTests 1 | Titel/Text/Thema/Aufgabe/Link/Teile samt Wortlaut-Regressionen |
| `Thoughts/CaptureFlowTests.swift` | CaptureFlowTests 5 | Aufnahmezustände als Android-ViewModel-/Integrationstests |
| `Thoughts/DescribedTopicsTests.swift` | DescribedTopicsTests 24 | Beschreibung, Namenshinweise und Doppel-Schranke |
| `Thoughts/LocalTests.swift` | LocalTests 14 | Schlagwörter, Suche, Kandidaten, Index (NLP separat vergleichen) |
| `Thoughts/MapAnchorFileTests.swift` | MapAnchorFileTests 5 | Persistenz-/Lesesperren von Ankern |
| `Thoughts/MapInboxTests.swift` | MapInboxTests 12 | Eingangszustände und Flüge |
| `Thoughts/MapLayoutTests.swift` | MapLayoutTests 37 | Deterministische kollisionsarme Anordnung |
| `Thoughts/MapViewportTests.swift` | MapViewportTests 8 | Pan/Zoom und Begrenzungen |
| `Thoughts/ProcessingTests.swift` | ProcessingTests 40 | Queue, Priorität, Neustart, Konflikte und Rohtext-Fallback |
| `Thoughts/StoreTests.swift` | StoreTests 29 | Persistenz, Recovery, Papierkorb und Audio-Löschung |
| `Thoughts/ThoughtTraceTests.swift` | ThoughtTraceTests 6 | Keine Inhalte in Ereignissen |
| `TopicImageFileTests.swift` | TopicImageFileTests 21 | Bilder, Metadaten, Größen-/Dateigrenzen |
Fixtures in `ios/PaplyKit/Tests/Fixtures/Thoughts/` sowie Synth/MockServer als Offline-Goldstandard nutzen; Werte/Erwartungen erhalten, Swift-Harness neu schreiben. `Shared/` enthält eingebundene Produktquellen, keine zusätzlichen Tests. Besonderes Abnahmekriterium: Upload-Abbruch unter Last (laut STAND noch wackelig), Unicode-Längen/Regex, Reboots und Disk-full. EVAL belegt bekannte KI-Fehler; Prompt v6 hat keine eigene vollständige Online-Messung.

## 6. Oberflächen-Inventar für Design-Gleichheit

Jede Zeile ist ein Abnahmeobjekt; b wird in Compose/Android umgesetzt, c entfällt mit Plattformbegründung, d bleibt nach V1. Aktuelle SwiftUI-/UIKit-Ansichten sind die visuelle Vorlage.
| Oberfläche / Option | Quelle und Portvorgabe |
| --- | --- |
| Reiter Gedanken · Aufgaben · Diktat; Zahnrad-Sheet | `App/UI/RootView.swift`, `App/UI/BetaViews.swift`; Gedanken zuerst, Beta-Markierung, bei Beta aus nur Diktat. |
| Landkarte mit festen Themenplätzen, Fokus-Zoom, echten Links, Eingangskugel und „Weitere Themen“ | `App/UI/Thoughts/Map/{ThoughtMapView,MapStageView,MapCanvas,MapScene,MapInboxOrb,MapStyle}.swift`. |
| Themen-Panel mit offenen Aufgaben und Gedanken | `App/UI/Thoughts/TopicPanel.swift`; eigenes Panel über Karte mit freier Tab-/Aufnahmebedienung. |
| Gedankenliste/Filter, Header und Suche | `App/UI/Thoughts/{ThoughtsHome,ThoughtsHomeHeader,ThoughtRow,ThoughtCard,TopicPalette}.swift`; alle/ohne Thema/noch nicht geordnet, Treffer und Leerzustände. |
| Leerer Gedankenstart und Knopf-Anleitung | `App/UI/Thoughts/ThoughtsEmptyState.swift`; iOS-Sperrbildschirm-/Kontrollzentrum-/Aktionstasten-Anleitung durch Android-Einstiege ersetzen. |
| Einrichtungskarte | `App/UI/Thoughts/SetupCard.swift`: Mikro erlauben; Groq-Schlüssel; Tastatur mit Vollzugriff; Gedanken-Knopf – auf Android IME aktivieren/auswählen statt Vollzugriff. |
| Große Aufnahme, kompakte Leiste und Echo-Kugel | `App/UI/Thoughts/{CaptureView,CaptureBar,EchoOrb,CaptureFlow}.swift`; Zeit/Pegel, Fertig, Verwerfen, Widerrufen, Verarbeitung/gesichert/wartend/Fehler. |
| Gedankendetail mit Bearbeiten/Kopieren/Teilen/Löschen | `App/UI/Thoughts/ThoughtDetailView.swift`; Titel/Text/Thema, Status, Aufgaben und Verwandte. |
| Originaltext | `App/UI/Thoughts/ThoughtOriginalView.swift`; nur Rohtext, kein Player. |
| Aufgaben im Detail | `App/UI/Thoughts/ThoughtTasksView.swift`; Abhaken, Textbearbeitung und Herkunft beibehalten. |
| Themenauswahl-Sheet | `App/UI/Thoughts/TopicSheets.swift:10`; vorhandenes/kein/neues Thema. |
| Themeneditor und Symbol-/Fotoauswahl | `App/UI/Thoughts/TopicSheets.swift:123`, `App/UI/Thoughts/TopicImageViews.swift`; Titel, Beschreibung, Symbol oder Bild, quadratisch ≤ 512 px JPEG ohne Metadaten, rein lokal. |
| Themenverwaltung, Vorschläge, Umbenennen, Entfernen | `App/UI/Thoughts/TopicsEditView.swift:7`, `App/UI/Thoughts/TopicSheets.swift:410`. |
| Zusammenführen-Sheets inkl. Ziel/Name | `App/UI/Thoughts/TopicSheets.swift:363`, `App/UI/Thoughts/TopicsEditView.swift:268`; nur nach Nutzeraktion. |
| Verknüpfen-Sheet | `App/UI/Thoughts/TopicsEditView.swift:422`; keine automatische Zusammenführung von Gedanken. |
| Zuletzt gelöscht | `App/UI/Thoughts/TopicsEditView.swift:328`; Wiederherstellen, einzelnes/alles endgültig löschen, Bestätigungsdialoge. |
| Aufgaben-Reiter | `App/UI/Thoughts/TasksTab.swift`; Überfällig/Heute/Demnächst/Irgendwann/Erledigt, Themenbezug, Bearbeiten, Abhaken, Sprung zum Gedanken. |
| Erinnerungseinladung | `App/Reminders/TaskReminderViews.swift:12`; Erinnern/Nicht jetzt (7 Tage), nur bei künftigem Termin mit Uhrzeit. |
| Diktat und Verlauf | `App/UI/DictationTab.swift`, `App/UI/HistoryDetailView.swift`; Status, Text kopieren/teilen, Roh-/Poliertext und Fehler; iOS-Sitzungsstart/-ende durch Android-Aufnahmestatus ersetzen. |
| Groq-Schlüssel | `App/UI/SettingsView.swift:255`; Schlüssel einfügen, Sichern, Prüfen, Entfernen, Einrichtungslink/Anleitung und Fehlerstatus. |
| Sprachen automatisch | `App/UI/SettingsView.swift:419`; aus Geräte-/Tastatursprachen, bei nur einer Sprache Englisch ergänzen; Android-Ermittlung neu. |
| Sprachen manuell | `App/UI/SettingsView.swift:433`; Mehrfachauswahl de/en/fr/es/it/pt/nl/tr/pl (`AppSettings.commonLanguages`) plus erkannte/gespeicherte Sprachen. |
| Hauptsprache | `App/UI/SettingsView.swift:452`; Auswahl unter Nutzersprachen, Default aus Gerätesprache. |
| Eigene Begriffe | `App/UI/SettingsView.swift:515`; freies Textfeld mit Komma/Zeilen als Trennung. |
| Mikro bereit halten | `App/UI/SettingsView.swift:137`, `Shared/Core/SharedSettings.swift:4`; bis Neustart/8 Stunden/1 Stunde/15 Minuten, Code-Default bis Neustart; c, sofern IME selbst bedarfsgerecht aufnehmen kann. |
| Beta „Gedanken & Aufgaben“ | `App/UI/SettingsView.swift:237`; Default an, aus blendet Funktionen aus und stoppt neue Starts, löscht keine Daten. |
| Gedanken-Knopf einrichten | `App/UI/SettingsView.swift:156`; Android-Kachel/Widget-Anleitung. |
| Erinnerungen zur Uhrzeit | `App/Reminders/TaskReminderViews.swift:95`; an/aus, bei verweigertem Recht Systemeinstellungen öffnen; nur Tag bleibt still. |
| Tastatur einrichten | `App/UI/SettingsView.swift:597`; Anleitung plus System-Einstellungen, erscheint wenn Einrichtung fehlt. |
| Feedback senden | `App/UI/SettingsView.swift:187`; Sharesheet mit inhaltsfreier Diagnose, kein automatischer Versand. |
| Version / Entwicklerbereich freischalten | `App/UI/SettingsView.swift:204`; Versionsanzeige, fünfmal tippen öffnet Entwicklerzugang (d). |
| Entwickler: Transkription und Stücke-Upload | `App/UI/SettingsView.swift:672`; large-v3/turbo und Upload an/aus, Polier-Modell nur als Anzeige (d). |
| Entwickler: Mikro im Leerlauf pausieren und Art | `App/UI/SettingsView.swift:692`; an/aus, engine.pause()/engine.stop(), iOS-Experiment (c). |
| Entwickler: App automatisch öffnen / Host-App protokollieren | `App/UI/SettingsView.swift:710`; iOS-Experiment, Host-Protokoll nur Debug (c). |
| Entwickler: Upload-Format / Sprachwechsel-Beispiel / Polieren / strenge Prüfung / Standard zurücksetzen | `App/UI/SettingsView.swift:775`; FLAC/WAV, drei Schalter und Zurücksetzen (d). |
| Entwickler: Gedankenmodell / Tagesbudget / Verbrauch / Queue / vorläufige Themen / Themenpflege jetzt | `App/UI/Thoughts/ThoughtsDeveloperViews.swift`; 120b/20b, 20.000–150.000 in 10.000er-Schritten (d). |
| Entwickler: dringliche Erinnerungen / Abhaken nur mit Face ID / Test in 5 s | `App/Reminders/TaskReminderViews.swift:133`; Plattformrechte/Auth entsprechend neu, Kontrollseite d. |
| Entwickler: Testseite / Diagnose / Speicher-Selbsttest / Info / Entwicklerbereich anzeigen | `App/UI/SettingsView.swift:725`, `App/UI/{TestPageView,DiagnosticsView}.swift`; d, App-Group-Selbsttest c. |
| Karten-Debug und Demo-/Gedanken-Prüfansichten | `App/UI/Thoughts/Map/MapDebugScreen.swift`, `App/UI/Thoughts/ThoughtsDebug.swift`; d. |
| Widget-Vorschau | `App/UI/Thoughts/TaskWidgetPreview.swift`; echte Darstellung für Aufgaben-Widget, keine Demo-Aufgaben speichern. |
| Paply-Gedanke-Widget | `Widgets/ThoughtWidget.swift`; rund/rechteckig unter iOS-Uhr, Android Home-/verfügbare Sperrbildschirmfläche separat prüfen. |
| Paply-Aufgaben-Widgets | `Widgets/TasksWidget.swift`, `Shared/UI/TaskWidgetViews.swift`; rund/rechteckig/inline sowie Home klein/mittel, Zahl/nächste Aufgaben, direkt abhaken. |
| Gedanken- und Diktat-Steuerelemente | `Widgets/ThoughtControl.swift`, `Widgets/PaplyWidgets.swift`, `Shared/Intents/`; Android Quick Settings/Shortcuts mit gleicher Toggle-Semantik. |
| Gedanken Live Activity / Dynamic Island | `Widgets/ThoughtLiveActivity.swift`, `App/Session/ThoughtBridge.swift`; Aufnahmezeit, Fertig/Verwerfen, Ergebnis/Wartegrund → sichtbare FGS-Benachrichtigung mit Aktionen; keine dauerhafte Leerlaufanzeige nachbauen. |
| Diktat Live Activity | `Widgets/PaplyWidgets.swift:35`; Schnellstartstatus/Abschluss → Android-Benachrichtigung. |
| Tastatur-Panel | `Keyboard/{KeyboardViewController,PanelView}.swift`; große grüne Fläche, Zeit/Welle, Tipp fertig, links wischen verwerfen, Haptik erst bei Stimme, kein Live-Text, Ergebnis einmal einsetzen und zurückwechseln; Fehler/Neuversuch/ausstehender Text erhalten. |
| Aufblitzen | `App/UI/FlashView.swift`, `Keyboard/AppOpener.swift`; c, iOS-Mikro-Umweg. |

Marke: `Shared/UI/BrandUI.swift:3` ist nur die SwiftUI-Brücke; Werte kommen aus `Shared/Core/Brand.swift:5`: Grün #22B45F, hell #3AD879, dunkel #13803F; Wald #0F2C20/#0A1D15; Schnabel #FFC233; Mint #E8F8EE; Text #EEF5F0; Aufnahme #45E086→#22B45F mit #05210F; Mikropunkt #FF9F0A; Gefahr #FF6B5E. Logo-Verläufe #7CF29A→#22B45F und #FFE066→#FFA51F, Geometrie aus `electron-menubar/brand/mark.svg`; Federn k=520/c=24 und k=420/c=30, Masse 1.
Zusätzliche UI-Tokens: `App/UI/Components.swift:7` Hintergrund #1D4A35→Wald→#08160F; `App/UI/Thoughts/ThoughtsUI.swift:12` Mint #D8F39A, Blatt #7ED957, Limette #DCE568, Gold #F5BF50, blass #BFEEC4, Swipe #B8862B, Textopazität 0,62/0,42, Zeilen weiß 0,07; Themenpalette aus TopicPalette/TopicColorRegister. Schrift ist iOS-Systemschrift mit gerundeten Überschriften (31 bold/17 semibold), Dynamic Type und tabellarischen Ziffern, keine eingebettete Marken-Fontdatei; Android-Schriftmetriken bewusst abgleichen. Lucide v0.561.0, 24×24, meist Strich 2, Pfade/Lizenz in `Shared/UI/LucideIcons.swift:1`, Zeichnung in `Shared/UI/LucideGlyph.swift:64`; vereinzelte SF Symbols passend ersetzen. Reduce Motion, Schriftvergrößerung, Screenreader und Haptik gehören zur Gleichheit.

## 7. Kotlin-Struktur und V1-Etappen

- `:core` (reines Kotlin/JVM): `dictation`, `audio` (VAD/Schnitt/PCM), `text`, `groq.contracts` (DTO/Parser/Retry), `thoughts.model`, `thoughts.ai`, `thoughts.processing`, `thoughts.search`, `thoughts.budget`, `thoughts.map`, `tasks`; Uhr, NLP, Encoder, Transport und Ablage als Interfaces, Tests ohne Android.
- `:data` (JVM soweit möglich): `groq` (geteilter HTTP-Client/SSE), `storage` (JSON/WAV/Recovery), `ledger`; `:platform` (Android Library): `audio`, `nlp`, `security`, `notifications`, `background`, `images`, `settings`; keine API-Keys in Ressourcen.
- `:design` (Compose Library): Farben, Typografie, Lucide/Logo, Motion und gemeinsame Komponenten; `:app`: Screens/ViewModels plus `ime`, `widgets`, `tiles`, `shortcuts` und Service-Einstiege. Ein APK, vorzugsweise gemeinsamer Prozess; keine vorschnelle Modulaufteilung je Bildschirm.
- **0 · Machbarkeit (S):** Auf MacBook später IME-Aufnahme→Feld, Kachel→sichtbare Gedankenaufnahme, Stop/Verwerfen und Sperr-/Hintergrundverhalten beweisen; Plattformdetails mit PLATTFORM.md abgleichen.
- **1 · Diktat komplett (L):** JVM-Text-/Audio-/Prompttests, HTTP/SSE/Sprachwache, Chunking, IME, Key/Sprachen/Begriffe, Verlauf und Einrichtung; Unterbrechung/Abbruch/Einfügen abnehmen.
- **2 · Gedanken durchgängig (L):** Contracts, atomarer Store/Recovery/WAV, Ledger, NLP/Kandidaten, Validator/Ordnung/Hygiene, Queue mit Diktat-Vorrang, Kachel/Widget/Benachrichtigung und Aufnahme-/Detailansichten.
- **3 · Karte und Aufgaben (L):** deterministisches Layout/Anker, Compose-Karte/Panel/Suche, Themenbilder/Editor/Papierkorb, Aufgaben-Reiter, Erinnerungen samt Abhaken/Snooze und Aufgaben-Widgets.
- **4 · Gleichheit und Robustheit (M):** Beta/Feedback/Leer-/Fehlerzustände, Motion/Schrift/Haptik, echte Geräte (Anruf, Bluetooth, Netzausfall, Prozessende, wenig Speicher), Bildvergleich mit iOS, APK für Freunde; Debug-Seiten/Bench danach.

## 8. Risiken und Unklarheiten (maximal zehn)

1. Android-Aufnahme aus IME/Kachel/Sperrbildschirm und FGS-Startrechte sind hier absichtlich nicht online verifiziert; PLATTFORM.md und Phase 0 entscheiden, kein iOS-Bereitschaftsmikro blind übernehmen.
2. NaturalLanguage ist kein portierbares Modell: Keyword-/Lemma-/Embedding-Ergebnisse können Kandidaten, Thema und Validator verändern; deterministische Testadapter plus getrennte Qualitätsabnahme des lokalen Android-Ersatzes.
3. NSDataDetector-Datumsdeutung relativ zur Aufnahmezeit, Sommerzeit und gemischte gesprochene Uhrzeiten sind besonders fehleranfällig; unklare Angaben dürfen keine falsche Erinnerung auslösen.
4. Swift Character/UnicodeScalar/UTF16-Längen, ICU-Regex und Rundung unterscheiden sich von Kotlin String; pro Regel den ursprünglichen Zählmaßstab erhalten, sonst verändern sich Budgets und Sicherheitsnetz.
5. Audio-Fokus, Bluetooth/Telefonate, digitale Stille, Service-/IME-Lifecycle und Abbruchrennen müssen auf Hardware geprüft werden; iOS-Audiofixes sind keine Android-Garantie.
6. fsync/rename, WAV-Recovery, nicht lesbar versus leer sowie Feldbesitz und parallele Widget-Aktionen entscheiden über Datenverlust/Doppelverarbeitung; Android-Backup und Schlüsselablage ausdrücklich konfigurieren.
7. „Nie unbemerkt aufnehmen“ ist kritisch: Build 7 ergänzt Banner/Nudges nach realem Zehn-Minuten-Mitschnitt; Android muss Aufnahme und Stop/Verwerfen durchgehend sichtbar machen.
8. Dokumente enthalten alte Scope-Angaben (Aufgaben-Chip, Widgets später, Prompt v2, 384 Tests); aktueller Code ist Maßstab, Entwicklerseiten d, vorhandene Produkt-Widgets/Erinnerungen V1.
9. Groq-Modellverfügbarkeit/Free-Tier-Limits sind nur aus dem lokalen Vertrag dokumentiert; echte aktuelle Verfügbarkeit wurde auftragsgemäß nicht geprüft, Fallback/429 und getrennte Retry-Budgets testen.
10. Pixelgleiche Systemschrift, Tastaturhöhe, Dynamic Island und Sperrbildschirm-Widgets sind plattformabhängig; Markenwerte und Bedienabläufe erhalten, sichtbare Ersatzformen und NLP-Abweichungen vor V1-Abnahme benennen.
