# E2 Teil S — Android-Gedanken

Stand: 28.10.2026, Abnahme auf MacBook, `PAPLY_WORK=svc`, Emulator API 37 / arm64.
Kein Commit/Push. `android/thoughts/**` und die reservierten Settings-/History-Dateien nicht bearbeitet.

## Umsetzung
- Phase-0-Dienst/-Store ersetzt; Kern-`ThoughtStore` unter `filesDir/thoughts`.
- Einmalige, wiederholbare Migration von Phase-0-JSON/WAV/ready, einschließlich defektem WAV-Header.
  Fehlerhafte Altdateien bleiben erhalten; sie blockieren andere Datensätze nicht.
- `AudioCapture` besitzt den gemeinsamen Mikro-Lease für Gedanken und IME; Teil-WAV bleibt bei Fehlern.
  Unterbrechungen werden ausgelassen, nach Anruf/Stummschaltung weitergeschrieben; DEAD_OBJECT wird einmal ersetzt.
- Mikro-FGS endet nach dem Schließen der Aufnahme. Keine HTTP-/KI-Arbeit im Mikro-Dienst.
- LOW-Kanal ohne eigenen Ton/Vibration, Sekundenzähler, Fertig/Verwerfen, promovierte Benachrichtigung/Chip.
- Karte aus bestehendem Theme/Komponenten; kein Lifecycle-Autostart; ohne Benachrichtigungen nicht wegwischbar.
  Home ohne Benachrichtigungen beendet/sichert. Normales Verlassen vibriert sofort, dann alle 2 Minuten.
- Hinweis nach 9 Minuten, Ende nach 10 Minuten; keine zusätzlichen Produkteinstellungen.
- WorkManager: expedited mit normalem Fallback, Netzbedingung, exponentieller Backoff und dauerhafte Retry-Jobs.
  Kern-FileTranscriber → dauerhafter Rohtext → Audio löschen → ThoughtProcessor → TopicHygieneRunner.
  Echte CandidateFinder/TopicIndex aus Teil B, keine produktiven Test-Adapter.
- Tastatur-Diktat hat Vorrang; TokenLedger liegt unter `thoughts/ledger.json`.
  Netz-/Schlüsselwechsel und Prozessstart holen Wartendes nach. Täglicher Wartungsjob ergänzt die App-Wartung.
- Fehlgeschlagenes Audio: höchstens 30 Tage, Ablaufdatum im Repository und Übergangs-UI; danach erklärter Fehler.
  Erfolgreiches Audio wird bereits nach dauerhaftem Rohtext gelöscht. Papierkorb folgt der Kern-Hygiene.
- Verwerfen hat ein dauerhaftes Journal: nach einem Prozessabbruch keine versehentliche Wiederaufnahme/Transkription.
- Kachel und Home-Widget gehen immer über die Karte. Wiederholter Tipp beendet; Beta aus verhindert Starts und beendet Laufendes.
  CLEAR_TOP und erneuerte PendingIntents halten die Karte auch nach einem Besuch der Haupt-App vorn.

## Anschluss für den UI-Helfer
- `com.paply.android.thoughts.ThoughtsRepository.get(context)` ist der einzige App-Zugang; Application-Kontext.
- StateFlows: `thoughts`, `deleted`, `topics`, `tasks`, `status`, `recording`, `isLoaded`, `error`, `usage`, `suggestions`.
- `status` ist eine ID→Status-Map: RECORDING / WAITING / PROCESSED / ERROR, Nachricht und optional `audioExpiresAt`.
- Suspend-Aktionen: `setTitle`, `setText`, `edit`, `setTopic`, `createTopic`, `trash`, `restore`, `permanentlyDelete`,
  `setTaskDone`, `toggleTask`, `retry`; außerdem `thought(id)` und unveränderlicher `source(id)`.
- Aktionen kehren nach dem Speichern zurück; Fehler am Aufrufer anzeigen. Nutzeränderungen setzen die Kern-Owner.
  Kern schützt Nutzerfelder/Themen vor KI-Überschreiben; die App dupliziert keine KI-Rechteprüfung.
- `PaplyApp` nutzt nur die neue Datenquelle mit einfacher Liste; Themen-/Aufgaben-/Papierkorb-Oberfläche folgt separat.

## Emulator-Abnahme / Belege
Alle PNGs: `/tmp/paply-android-e2/svc-*.png`; JSON, Logcat, Dumps und Testberichte: `/tmp/paply-android-e2/evidence/`.
- Kachel → Karte → gRPC-Sprache → Fertig → „Gedanke gespeichert“: bestanden; Titel/Thema/Aufgabe im Kernstore und UI.
  `svc-first-saved.png`, `evidence/svc-first-thought.json`.
- Zweiter verwandter Gedanke: gleiches Thema, `continues`-Link; `evidence/svc-related-thought.json`.
- Wegwischen → Vibration/Chip: bestanden; `svc-background-chip.png`, `svc-background-state.txt`, Vibrator-Dump.
  Zunächst 5-Sekunden-Debugprobe, zusätzlich echtes 2-Minuten-Intervall in der langen Aufnahme.
- Benachrichtigung „Verwerfen“: Gedanke und WAV entfernt; `svc-widget-discard-target.png`, `svc-discard-{before,after}.txt`.
- Stumm/DEAD_OBJECT: „Unterbrochen“, genau ein Ersatzrecorder, beide gesprochenen Abschnitte vollständig erhalten;
  `svc-interrupted-notification.png`, `svc-interruption-source.json`, `svc-interrupt-rotation-logcat.txt`.
- Simulierter GSM-Anruf wird angezeigt/angenommen; Gedankenaufnahme zeigt „Unterbrochen“ und läuft danach weiter.
  `svc-incoming-call.png`, `svc-call-interrupted.png`, `svc-call-resumed.png`.
- Flugmodus → wartend, Netz an → automatisch fertig; fehlender Schlüssel → waitingKey, Einsetzen → automatisch fertig.
  `svc-offline-waiting.png`, `svc-offline-thought-{before,after}.json`, `svc-missing-key-thought.json`.
- Ohne Mikrorecht: Systemdialog statt Absturz; `svc-microphone-permission.png`.
- Ohne Benachrichtigungsrecht: Zurück/Wischen blockiert, Home beendet; `svc-no-notifications-back.png`, zugehöriger Dump.
- Drehen/Dunkelmodus: kein neuer Recorderstart; `svc-recording-rotated.png`, `svc-recording-resumed.png`.
- Widget hinzugefügt/startet; Beta aus stoppt Laufendes, Widget/Kachel starten nichts; `svc-widget-reentry.png`, `svc-beta-*.png`.
- IME: „Hi, wie geht’s?“ eingesetzt, Mikro frei; `svc-ime-result.png`. Gleichzeitiger Versuch: „Mikro belegt“ (`svc-microphone-lease.png`).
- Echte 9-/10-Minuten-Probe: Hinweis/Vibration bei 9 Min., Mikro/Dienst nach 10 Min. aus, anschließend gespeichert.
  `svc-one-minute-left.png`, `svc-ten-minute-stop.png`, `svc-timing-*.txt`; wiederholte Vibrationen bei 2/4/6/8 Min.

## Prüfung und verbleibende Grenzen
- MacBook: `:core:test` 284 Tests, `:app:testDebugUnitTest` 34 Tests, Debug-APK/Test-APK und Lint erfolgreich.
- Instrumentierte Tests: final 19 grün, darunter Migration, Rohtext-vor-Audiolöschung, Teil-WAV-Recovery,
  Verwerfen nach Prozessabbruch, keine doppelte KI nach Migration, Diktatvorrang und Schutz gleichzeitiger Nutzeränderungen.
- Gesamt: 5 Gedanken-Transkriptionen + 5 KI-Läufe, ein zusätzliches IME-Diktat. Keine Gedanken-WAV verblieben.
- Offen: Whisper-Ausreißer bei minutenlanger stiller Pause im GSM-/10-Minuten-Test: erfundener Übergang,
  zweiter Abschnitt teils Englisch. Beleg `svc-timed-call-source.json`; unveränderter Kern-FileTranscriber/DictationPipeline.
  Kurze Aufnahmen und die Stumm-/DEAD_OBJECT-Probe korrekt. Kein pauschales Wegfiltern leiser Nutzersprache ergänzt.
- Keine Prüfung auf physischem Android-Gerät; OEM-Chip-/Energiesparverhalten bleibt Geräteabnahme.
- Finales Logcat ohne FATAL; Mikro nach allen Enden frei. Emulator um 23:38 CET gestoppt, `adb devices` leer.
- Installierbarer geprüfter Stand: `/tmp/paply-android-e2/paply-e2-service-debug.apk` (Debug, kein Release).
