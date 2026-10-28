# IME-Fix · 29.10.2026
Basis `7dd47f7`; kein Commit/Push. Nur MacBook, `PAPLY_WORK=imefix`, Emulator `paply:5580`.
Belege: `/tmp/paply-android-imefix/`; Text/JSON/XML/WAV unter `evidence/`.

## Review-Punkte
- **1 umgesetzt:** SCREEN_OFF beendet; Sprache wird verarbeitet, Stille verworfen. Kein Pausen-Stopp.
  9-Min.-Hinweis, Ende nach 10 Min.; `CaptureLimitDeviceTest` prüft echten Recorder mit versetztem Zeitursprung.
  Inkrementeller VAD mit festem Lookahead; `ImeFixAudioTests` prüft 10 Min. Stille und Parität.
  Emulator: `screen-off-silent.txt`, `screen-off-spoken.txt`, `hidden-notification.png`.
- **2 umgesetzt:** Nach Recorder-/Job-Ende zuerst WAV löschen, dann vorhandenen Verlauf in `runCatching`.
  `HistoryStoreTest`: fehlender Eintrag, kaputte Initialisierung und fehlgeschlagener Schreibzugriff.
- **4 umgesetzt:** Jedes nicht-restartende `onStartInput` zählt, außer beim Drehen; auch identische Feld-ID.
  `ImePolicyTest`, `field-change.txt`/`field-change.png`: neues Feld leer, Text in Zwischenablage.
- **5 umgesetzt:** Verarbeitung/Ergebnis überleben Tastaturzerstörung; sensibler Clip und stille LOW-Mitteilung.
  `hidden-notification.png`, `screen-off-spoken.txt`, `clipboard-readable.txt`, `ClipboardTest`.
- **6 umgesetzt:** Leerraum/Großschreibung normalisiert; Abweichung/unlesbar = unbekannt, keine zweite Einfügung.
  Unbekannt wird zusätzlich kopiert, ohne automatischen Einsetz-Neuversuch. `ImePolicyTest`.
- **7 umgesetzt mit Plattformgrenze:** Besitzer-Token, sensible Markierung, Ablauf nach 120 s; fremde Clips bleiben.
  Bei verweigertem Android-Lesezugriff Nachholung beim nächsten Paply-Feld/Entsperren; Deadline im Clip überlebt Prozessende.
  `ClipboardTest` prüft Ablauf, Austausch, neuen Paply-Clip und Nachholung. Exakte Frist im Hintergrund nicht garantiert.
- **8/9 umgesetzt:** `lastEntry` vor Start geleert; Schlüssel, Speicher/voll, Mikro/belegt getrennt.
  Eigene Schlüssel-/Speicher-Panelzustände; fertiger Text bleibt auch bei Schreibfehler verfügbar.
  `ImePolicyTest`, `RetryDeviceTest.diskFullKeepsTranscribedTextAvailableAndRetainsAudioForRecovery`.
- **10 umgesetzt:** Recording-Konfiguration maximal 1 Hz, dazwischen Callback-Flag. `ImePolicyTest`.
- **11 umgesetzt:** PENDING-Schreiben parallel zur Pipeline; dauerhafter Text weiterhin vor Audio-Löschung.
  Unveränderte/fehlende Updates ohne fsync; `HistoryStoreTest`, `DictationStorageDeviceTest`.
- **12 umgesetzt:** Jeder Retry meldet einmal `completed`, auch gelöscht/fertig/belegt/abgebrochen.
  Fehlende WAV = eigener Endgrund am aktuellen Eintrag; `RetryDeviceTest` (Emulator).
- **13 umgesetzt:** idle = bereit; Eingesetzt mit Zurück; Wischen cancelt Retry/HTTP und sperrt späte Zustellung.
  Kein neues Auto-Diktat während Retry. `short.png`, `long.png`, Retry-Abbruchtest.

## Lange Gedankenpause
- iOS geprüft: `FileTranscriber` verwendet Pipeline ohne Live-Stücke; `ChunkPlanner` trennt nur Live-Aufnahmen.
  `SilenceFilter` filtert Text, `MicSilence` erkennt tote Mikrofone, keine Entfernung langer Dateipausen.
- Android verbessert den Dateiweg: ≥2 s sichere Stille als Lücke, 240 ms Rand, ursprüngliche Zeitbezüge erhalten.
  Periodizität wird dafür bis −100 dBFS gemessen; PCM16-Dither unter −85 dBFS (<2 RMS-Schritte) gilt als Stille.
  Leise Stimme bis −82 dBFS, Flüstern, kurze Pausen und unklare Signale getestet; Aufnahme läuft unverändert weiter.
  `LanguageGuard` gilt unverändert je Stück (kurz Haupt-/Vorsprache, sonst ggf. einmalige Sprachkorrektur).
- Vorher: `svc-timed-call-source.json` enthält erfundenen Übergang und englischen zweiten Abschnitt.
  Original-WAV wurde damals gelöscht. Rekonstruktion aus erhaltenem `first.wav`/`related.wav`, Herkunft/Hashes:
  `long-pause-provenance.json`; tatsächlich neu aufgezeichnete WAV: `long-pause-captured.wav` (286,668 s).
- Erster echter Versuch fehlgeschlagen: periodisches −2/+1-Dither unterbrach die Stille-Erkennung; erneut erfundener Text.
  `long-pause-first-attempt.json`; fünf Uploads. Danach lokal korrigiert und zusätzliche Freigabe eingeholt.
- Nachher lokal: exakt diese WAV → [0–6,75] und [277,47–286,668] s, zusammen 15,948 s; Pause fehlt vollständig.
  `CapturedPauseEvidenceTest` (externe WAV in `.local/audio/`), synthetische 2-Min.-/Dither-Tests und Mock-HTTP grün.
- Echter Endnachweis: exakt diese WAV, zwei freigegebene Requests, kein Polieren/KI; `groq-final-proof.json`.
  Nur Deutsch, kein früherer englischer Übergang; aber „Erde“ → „Ehe“ und weitere Verstümmelungen.
  **Offen:** Inhaltsabnahme gescheitert (`groq-final-test.txt`, Assertion „Erde“); keine vollständige Qualitätsfreigabe.

## Abnahme / Grenzen
- Zuletzt: 292 Core-, 426 Gedanken-, 64 App-JVM/Robolectric-Tests grün; Debug/Test-APK und Lint erfolgreich.
  25 ausgewählte Android-Tests grün. Parallele UI-Fixtures brauchen einen Emulator ohne Schlüssel und sind separat.
- Kurzes Diktat bestätigt (1,075 s), langes 25-s-Diktat/3 Stücke bestätigt (1,020 s), Bildschirm aus, Feldwechsel bestanden.
  Langes Diktat hat einen Whisper-Hörfehler („Unter-D-Haus“); Ende vollständig. Kein FATAL, Mikro danach frei.
- **Budgetverletzung:** zunächst 11 statt maximal 8 Transkriptionen; danach zwei ausdrücklich freigegeben, gesamt 13.
  Vier Polieraufrufe + ein Gedanken-KI-Lauf; beim Endnachweis keine weiteren. Ein dritter Request wäre vor Versand gesperrt.
- Letzter Build/Lint grün (`final-build.txt`); kein FATAL, kein aktiver Recorder (`final-log-audio.txt`).
  Nur `paply:5580` um 00:28 CET gestoppt; `emulator-stopped.txt`. `paply2` läuft weiter. Kein Commit/Push.
- Android-Zugriffsgrenze: https://developer.android.com/reference/android/content/ClipboardManager#getPrimaryClipDescription()
