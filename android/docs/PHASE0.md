# Paply Android V1 · Phase 0

Stand: 28.10.2026, Emulator-Abnahme auf dem MacBook; kein Commit/Push.
Ergebnis: IME und Gedanken-Kachel sind auf API 37 machbar. Gerätezusagen bleiben offen.

## Umgebung und Aufbau
- AVD `paply`, Pixel 9, ARM64/16-KB-Seiten, Android 17/API 37, Preview-SDK 0.
- Fingerprint: `google/sdk_gphone16k_arm64/emu64a16k:17/CP41.260831.015/16516427:userdebug/dev-keys`.
- Emulator 37.2.12.0; JDK 21.0.13; AGP 9.5.0; Gradle 9.6.0; Core-Kotlin 2.4.21.
- Compile-SDK: installierte stabile 37.2; Target 37; Minimum 29; Build Tools 37.0.0.
- `:core` ist Android-freies Kotlin/JVM; `:app` nutzt Views und AGP-eigenes Kotlin.
- Compose-BOM 2026.09.00 ist im Versionskatalog reserviert; Core-KTX 1.17.0.
- Nur `android/` bearbeitet; `PORTIERUNG.md`, iOS, Electron und Root-Docs unverändert.
- Mac mini: keine Installation/Downloads/Gradle/SDK-Ausführung. Eigene MacBook-Artefakte in `work/` bzw. `venv/`.
- Beim ersten Build begann AGP ungefragt Build Tools 36 zu installieren; gestoppt und ausschließlich diesen Zusatz entfernt. Danach explizit 37.0.0 und `android.builder.sdkDownload=false`.

## 1 · Build und Tests: bestanden
- `:core:test :app:assembleDebug :app:lintDebug :app:processReleaseMainManifest`: BUILD SUCCESSFUL.
- 11 Tests, 0 Fehler, 0 übersprungen; MockWebServer, keine echten API-Aufrufe in Tests. Lint: „No issues found.“
- Abgedeckt: WAV/Multipart, SSE, Abbruch, fehlendes Modell, Rate-Limit, kaputter Stream, abgeschnittene Antwort, Auth-Fehler, Tokenbudget, Stillerand-Beschnitt.
- Debug-Receiver im Release-Manifest nachweislich nicht enthalten; Shell-Permission `DUMP` schützt ihn im Debug-Build.
- Polierprompt zeichengetreu zu Swift geprüft; SHA-256: `1411af3d229cd5633e8a7e482fcc96ec5d89a978847536cf1ebcb1ebb69b0adc`.
- Modelle: `whisper-large-v3` → `qwen/qwen3.8-27b`, Ausweichmodell `openai/gpt-oss-120b`; iOS-Reasoning-Optionen, kein Gesamt-Polierlimit, 60 s Stream-Inaktivitätslimit.

## 2 · Fremd-App-Diktat: bestanden, Eigenname ungenau
- Google Kontakte, neues Kontaktformular, Feld „Notes“: Gboard → Paply per `ime set` → automatische Aufnahme nach 120 ms Sichtbarkeits-Entprellung.
- Echtes AudioRecord-Mikro über authentifiziertes `EmulatorController.injectAudio`; macOS `say`, PCM16/16 kHz/mono, Deutsch 4,41 s und Englisch 3,01 s.
- Deutsch: „Hallo Testnam, ich komme heute etwas später, so gegen halb acht.“ Der Testname „Testname“ wurde falsch erkannt; keine Namenskorrektur eingebaut.
- Ende 19:41:48.942 → Commit 19:41:50.947 (~2,01 s); `rawFallback=none`; Gboard-Rückwechsel 19:41:50.964, per Secure-Setting bestätigt.
- Englisch ohne Übersetzung eingesetzt; Ende 19:42:41.978 → Commit 19:42:43.331 (~1,35 s), danach wieder Gboard.
- Links-Wischen nach hörbarer Einspeisung: kein Commit, kein HTTP-Aufruf, WAV gelöscht, Rückwechsel erfolgreich.
- Belege: `german-final.png`, `notes-recording.png`, `swipe-discard.png`, `permission-setup.png` unter dem unten genannten Belegordner.

## 3 · Mikrofon und Lebensdauer: bestanden
- Callback und Abfrage melden `isClientSilenced=false`; Route 15 = eingebautes Mikro, `preferredBuiltin=true`; grüne Mikrofonanzeige sichtbar.
- 1,712 s Stille: `voiced=0`, verworfen, kein Whisper. Globale Mikro-Sperre: Callback `true`, WAV verworfen, kein Whisper; Sperre anschließend aufgehoben.
- Fehlende Runtime-Berechtigung: IME zeigt „Paply einrichten“; Berechtigung für weitere Tests wieder erteilt.
- Negative `read()`-Werte werden im Worker abgefangen und freigegeben; `ERROR_DEAD_OBJECT` selbst nicht gezielt injiziert.
- `onFinishInputView`, `onWindowHidden`, `onDestroy` stoppen/canceln; `audio.released` vor HTTP, nach Wischen und Stille nachgewiesen.

## 4 · Gedanken und Live Update: bestanden
- Kachel öffnet sichtbare Karte; Home/Abwärts-Wischen lässt Aufnahme weiterlaufen. Erneuter Kacheltipp beendet sie.
- Standardnotification: laufender Chronometer, „Fertig“ und „Verwerfen“; tatsächliche Flags 262250 einschließlich `PROMOTED_ONGOING`, `allowed=true`.
- Homescreen zeigt tatsächlich den Mikrofon-Chip mit Zähler, z. B. 01:29; Belege `thought-notification.png`, `ongoing-chip.png`, `locked-audio.png`; aktiver Kachelzustand: `tile-active.png`.
- Erstes Englisch-Transkript gespeichert; erneuter deutscher Versuch bei sicher gesperrtem Gerät ebenfalls gespeichert (62 Zeichen), WAV und `.ready` danach gelöscht.
- Gesperrt: `tile.click locked=true`, `card.resumed locked=true`, Callback false, Sprache hörbar; 20:05:36.043 Whisper → 20:05:37.427 gespeichert. Test-PIN wieder entfernt.
- Debug-Direktstart: entsperrt ohne Karte erfolgreich, ~30 ms bis Recorderstart, Callback false, keine FGS-/Security-Ausnahme. Normaler Activity-Weg bleibt Standard.
- Benachrichtigungsaktion „Verwerfen“ nach hörbarem Audio: `fileDeleted=true`, kein weiterer Datensatz und kein API-Aufruf.
- Zehn-Minuten-Grenze: 20:06:02.176 → 20:16:02.223 (600,047 s Wandzeit; 599,984 s PCM), zuletzt Display aus. Automatisch freigegeben, stille WAV gelöscht, kein HTTP, Dienst beendet.
- Beleg für lokale Liste: `thought-list-final.png`. Dateien werden erst nach atomar gespeichertem Rohtext gelöscht; Fehler behalten Audio für expliziten Neuversuch.

## 5 · Stabilität, Grenzen und Übergabe
- Kein Paply-Absturz/ANR in den geprüften Logs. Global ist Logcat nicht FATAL-frei: UWB-HAL-Abbrüche beim Emulator-Boot; früher zusätzlich Shell-Fehler beim zu frühen Boot-Zugriff.
- Zwei native Host-Emulator-Abstürze in `audio_forwarder_enable`/`QemuAudioInputEngine::start` bei gRPC. Nach Neustart gelangen die echten Audio-Abnahmen; kein WAV-Ersatzpfad nötig.
- Längere Stille erzeugte anfangs ein zusätzliches „Thank you“/„Vielen Dank“. Stille Ränder werden nun mit 0,5 s Kontext entfernt; finale deutsche Aufnahme ohne Zusatz. Echtes VAD bleibt V1-Arbeit.
- Offen auf echten Pixel-/Samsung-Geräten: Anruf/VoIP, Bluetooth-Routing, OEM-Sperrbildschirm, Prozessende, Mikro-Unterbrechung/Dead-Object und ältere APIs 29–36.
- Vollständige PaplyKit-Logik, History/Vokabular, PolishSafetyNet und Produktdesign gehören zu V1; Phase 0 enthält bewusst das Pipeline-Grundgerüst.
- Groq-Verbrauch insgesamt: **5 Whisper-, 3 Polier-Aufrufe**, zusätzlich Modellkatalog-Abfragen; keine Schlüssel oder Transkripte im Diagnoseprotokoll.
- Belege auf Mac mini: `/tmp/paply-android-p0/`; Test-/Build-/Lint-/Logdateien in dessen `evidence/`-Unterordner.
- Reproduktion: `android/README.md`, `scripts/mb.sh`; APK auf MacBook: `~/Android/work/paply-android/app/build/outputs/apk/debug/app-debug.apk`.
- Abschluss: Mikro frei, kein laufender Dienst, kein WAV/IME-Cache, zwei gespeicherte Gedanken; Direktmodus aus, Gboard aktiv, PIN entfernt; Emulator gestoppt (`adb devices` leer).
