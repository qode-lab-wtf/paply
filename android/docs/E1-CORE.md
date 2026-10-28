# Etappe 1 · Diktat-Kern

Stand: 28.10.2026. Implementierung ausschließlich in `android/core`; diese Datei ist die Abschlussnotiz.
Keine Änderungen an iOS/Desktop/App oder Versionskatalog durch Teil A; kein Commit/Push.

## Zuordnung Swift → Kotlin

Quelle relativ zu `ios/PaplyKit/Sources/PaplyKit`, Ziel relativ zu `android/core/src/main/kotlin/com/paply/core`.

| Swift-Datei(en) | Kotlin-Datei(en) |
| --- | --- |
| `Text/LanguageGuard.swift` | `LanguageGuard.kt` |
| `Text/PolishPrompt.swift`, `Text/WhisperPrompt.swift` | `PolishPrompt.kt`, `WhisperPrompt.kt` |
| `Text/PolishSafetyNet.swift`, `Text/EditCheck.swift` | `PolishSafetyNet.kt`, `EditCheck.kt` (Diktatprofil) |
| `Text/TranscriptCleanup.swift`, `Text/CodeSwitchPrimer.swift` | `TranscriptCleanup.kt`, `CodeSwitchPrimer.kt` |
| `Text/Lexicon.swift`, `Text/TextAnalysis.swift`, `Text/Pattern.swift` | `Lexicon.kt`, `TextAnalysis.kt`, `Pattern.kt`; Unicode-Helfer in `Platform.kt` |
| `Text/LanguageDetection.swift` | `Platform.kt`: `detectLanguage`, `LanguageDetector` |
| `Audio/VoiceActivityDetector.swift`, `Audio/ChunkPlanner.swift` | `VoiceActivityDetector.kt`, `ChunkPlanner.kt` |
| `Audio/SilenceFilter.swift`, `Audio/MicSilence.swift` | `SilenceFilter.kt`, `MicSilence.kt` |
| `Audio/AudioEncoder.swift` | `AudioEncoder.kt`; ObjCException entfällt |
| `Groq/GroqClient.swift` | `GroqClient.kt` (inkl. Transport), `ChatStreamParser.kt`, DTOs in `PublicAPI.kt` |
| `Groq/GroqModels.swift`, `Groq/GroqConnection.swift`, `Groq/PolishService.swift` | `GroqModels.kt`, `GroqConnection.kt`, `PolishService.kt` (inkl. ModelCatalog) |
| `DictationPipeline.swift`, `PublicAPI.swift` | `DictationPipeline.kt`, `PublicAPI.kt` |
| Phase-0-Aufrufer | `LegacyAPI.kt`, veraltete Überladungen und `WavWriter.kt`, jeweils `@Deprecated` |

## Tests und Prüfung

MacBook, eigener Arbeitsordner `core`: `PAPLY_WORK=core android/scripts/mb.sh sync`, danach
`PAPLY_WORK=core GRADLE_TASKS=":core:test :app:compileDebugKotlin" android/scripts/mb.sh build`.
Ergebnis: **264 Tests grün**, App-Kotlin kompiliert. Nur lokale MockWebServer-Anfragen; kein Emulator/Groq.

| iOS-Datei/Suite | iOS-Deklarationen | Kotlin-Tests |
| --- | ---: | ---: |
| GroqClientTests | 25 | 25 |
| LanguageGuardTests | 12 | 12 |
| MicSilenceTests | 24 | 24 |
| PipelineTests | 17 | 17 |
| PromptTests | 16 | 16 |
| SafetyNetTests | 17 | 17 |
| SilenceFilterTests | 31 | 31 |
| AudioTests | 26 | 26 |
| ReviewTests | 39 | 39 = ReviewText 10 + ReviewClient 11 + ReviewPipeline 18 |
| FollowUpTests | 20 | 20 = FollowUpText 6 + FollowUp 14 |
| Zusätzlich: Phase 0 / JVM-Parität | – | 11 / 26 |

Parametrisierte Swift-Deklarationen bleiben jeweils ein JUnit-Test mit allen Vektoren; insgesamt 227 portierte Deklarationen.
`Support/MockServer.swift` → `support/MockServer.kt`, `Support/Synth.swift` → `support/Synth.kt`.
Bewusste Abweichungen: nativer FLAC-Roundtrip/Kompressionsgrad und temporäre FLAC-Dateibereinigung werden durch WAV-Roundtrip, Encoder-Injektion und Fehler-Fallback geprüft; echte FLAC-Abnahme folgt mit MediaCodec.
Der kalte Modellcache blockiert ausdrücklich ebenfalls nie (Auftrag/Fund 12, iOS wartet dort noch); Modellwahl-Tests wärmen ihren Cache gezielt vor, Abbruchtest hält zusätzlich die Transkription offen.
MockWebServer bindet IPv4 explizit; hängende Antworten nutzen NO_RESPONSE statt schlafender Server-Threads. Phase-0-Fixture korrigiert für die strenge iOS-Längenprüfung; Fehlercode jetzt `unauthorized`.
Zusatztests belegen Skalar-/UTF16-/Graphemzählung, Foundation-Leerraum, Unicode-Regex, 64-Bit-Zahlen, Rundung, Cache-Rennen, Retry/Abbruch, PCM-Blöcke und Aufnahmen >10 Minuten. Systemprompt per SHA-256 bytegleich geprüft.

## Öffentliche API für die Integration

```kotlin
DictationPipeline(configuration: DictationConfiguration, options: PipelineOptions = PipelineOptions(),
  recentRawDictations: List<String> = emptyList(), encoder: AudioEncoding = DefaultAudioEncoding(),
  detector: LanguageDetector = NoLanguageDetector, clock: PaplyClock = SystemPaplyClock,
  reachability: NetworkReachability = AssumeReachable, onState: (DictationStatus) -> Unit = {})
fun append(samples: ShortArray) // mono PCM16, 16 kHz; fortlaufend, synchron/thread-sicher
suspend fun finish(): DictationOutcome; suspend fun retry(): DictationOutcome
fun cancel(); fun close(); fun releaseAudio(); fun discardSilentStart(): Boolean
```

`DictationConfiguration`: `keyProvider: () -> String`, `primaryLanguage`, `spokenLanguages`, `vocabulary`, `transcriptionModel` (large-v3/turbo), `chunkedUpload`; optional `language` fest, Poliermodelle und `deviceLanguages`. Schlüssel wird einmal je Sitzung abgefragt.
`DictationOutcome`: `text`, `raw`, `polished`, `language`/`languages`, `error`, `errorMessage`, `polishFailure`/`polishError`, `polishRejectionCode`, `timings`, `noSpeech`, `languageSources`.
Callbacks: recording/transcribing/polishing/finished/failed/cancelled plus Pegel/Sprache erkannt; serialisiert auf Aufrufer-/Worker-Thread, UI selbst auf Main dispatchen. `finish()` teilt laufende Arbeit; `retry()` erhält erfolgreiche Stücke; `cancel()` beendet Uploads.
Vorwärmen nebenläufig beim Aufnahmebeginn: `suspend GroqConnection.prewarm(apiKey: String, refreshModels: Boolean = false)`; Schlüsselprüfung: `suspend checkKey(apiKey: String): KeyCheck`; Netzwechsel: `GroqConnection.reset()`.

## Plattformgrenzen und offene Integration

- `LanguageDetector.detect(String): String?`: Android liefert lokale Sprachkennung, ohne Netz; JVM liefert null. Wird nur ohne Whisper-Sprache und ab zwei Wörtern benutzt. Modellqualität separat abnehmen.
- `Lemmatizer.lemmas(String): List<String>`: JVM normalisiert/zerlegt ohne Lemmatisierung; Diktat nutzt im Swift-Original keine NaturalLanguage-Lemmata. Android-NLP und Gedankenprofil/strukturierte Gedanken-Aufrufe gehören zur späteren Gedanken-Portierung.
- `AudioEncoding.encode(ShortArray, Boolean): AudioEncoder.Encoded`, `FlacEncoder.encode(ShortArray): ByteArray?`: JVM liefert verlustfreies WAV; Android liefert vollständiges FLAC mono PCM16/16 kHz, räumt Ressourcen auf; Fehler fallen auf WAV zurück.
- `PaplyClock`: `nowMillis(): Long`, `monotonicNanos(): Long`, `suspend sleep(Double)`; JVM Systemzeit/nanoTime/Coroutine-delay, Android kann elapsedRealtimeNanos einsetzen.
- `NetworkReachability.isReachable(): Boolean`: JVM optimistisch; Android ConnectivityManager anbinden, Netzwerkwechsel über reset. HTTP bleibt maßgeblich.
- Funde 11/12 erledigt: SSE-rate_limit → 429 samt Wartezeit; Modellcache 5 Minuten, schlüsselweise gehasht, geteilte Hintergrundabfrage, Polieren wartet nie. Kein Gesamtzeitlimit fürs Polieren, tote Verbindungen über Leerlauf erkannt; genau ein fachlicher Wiederholversuch.
- Geräte-NLP, echter FLAC-Codec, AudioRecord/IME-Lifecycle und Unicode-Versionen der Android-Laufzeit bleiben Integrationsabnahme; hier bewusst keine App-Klassen oder Emulatorprüfung.
