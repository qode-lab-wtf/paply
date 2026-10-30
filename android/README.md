# Paply Android · Phase 0

Native Sprach-IME und Gedanken-Kachel; einfache View-Oberfläche. Die Machbarkeitsprüfung steht in [docs/PHASE0.md](docs/PHASE0.md), die verbindlichen Plattformannahmen in [docs/PLATTFORM.md](docs/PLATTFORM.md).

## Aufbau

- `core/`: Android-freies Kotlin/JVM-Modul; Groq HTTP/SSE, unveränderter iOS-Polierprompt, Pipeline, PCM-WAV und elf lokale Fake-Server-Tests.
- `app/`: `AudioCapture`, `PaplyIme`, `ThoughtTile`, sichtbare `CaptureActivity`, `ThoughtService`, privater `ThoughtStore` und Einrichtung.
- `scripts/`: ausschließlich auf dem MacBook bauen, installieren und testen; Screenshots werden zum Mac mini übertragen.

AGP 9.5.0, Gradle 9.6.0, Kotlin 2.4.21 im Core, AGP-eigenes Kotlin im Android-Modul, JDK 21. Installierte stabile Plattform: API 37.2; Target 37, Minimum 29; Build Tools 37.0.0. Compose-BOM 2026.09.00 ist für V1 im Katalog reserviert; Phase 0 verwendet Views. Kein zweites Kotlin-Android-Plugin.

## Bauen vom Mac mini aus

Auf dem Mac mini keine Android-/Gradle-Werkzeuge installieren oder ausführen. Voraussetzung ist die vorhandene MacBook-Einrichtung mit `~/Android/env.sh`, SDK, JDK und AVD `paply`.

```sh
ssh macbook 'test -x ~/Android/emu-start.sh && test -d ~/Android/sdk/system-images'
android/scripts/mb.sh sync
android/scripts/mb.sh build
android/scripts/mb.sh install
android/scripts/mb.sh shot beispiel
android/scripts/mb.sh logs
```

`build` führt `:core:test :app:assembleDebug` aus. APK: auf dem MacBook unter `~/Android/work/paply-android/app/build/outputs/apk/debug/app-debug.apk`. Gradle-Cache, temporäre Dateien und Debug-Keystore bleiben unter `~/Android/work/`; der SDK-Autodownload ist deaktiviert. `sync` erhält Build-Ausgaben und `.local/`, entfernt keine Remote-Dateien und überträgt keine Keystores.

App öffnen, Mikrofon und Benachrichtigungen erlauben, Groq-Schlüssel speichern, Tastatur aktivieren und auswählen. Der Schlüssel liegt in app-privaten Preferences, wird nicht vorbefüllt/geloggt und ist von Backups ausgeschlossen. Ein sichtbares Fremd-App-Textfeld muss beim Wechsel zu Paply fokussiert sein. Das Hardwarekeyboard des Emulators blendet sonst die Bildschirmtastatur aus:

```sh
ssh macbook 'source ~/Android/env.sh; adb -s emulator-5580 shell settings put secure show_ime_with_hard_keyboard 1; adb -s emulator-5580 shell ime enable com.paply.android/.PaplyIme; adb -s emulator-5580 shell cmd statusbar add-tile com.paply.android/.ThoughtTile'
```

## Spracheinspeisung und Debug-Zugang

Alle folgenden Hilfsskripte laufen **auf dem MacBook** nach `source ~/Android/env.sh`, aus `~/Android/work/paply-android`:

```sh
scripts/bootstrap-audio.sh
scripts/start-audio-emulator.sh
/usr/bin/python3 scripts/set-test-key.py
# Erst Paply-Aufnahme starten, dann:
~/Android/venv/bin/python scripts/inject-audio.py ~/Android/work/audio-test/de.wav
~/Android/venv/bin/python scripts/inject-audio.py ~/Android/work/audio-test/en.wav
```

Der Bootstrap verwendet macOS `say` und installiert fest gepinnte gRPC-Pakete ausschließlich in `~/Android/venv`. Protobufs und WAVs liegen in `~/Android/work/audio-test`. Der Test-Launcher ergänzt den unveränderten AVD um lokal authentifiziertes gRPC. Die Injektion überprüft zuerst einen aktiven Paply-Recorder. Emulator 37.2.12 kann dennoch im nativen `audio_forwarder_enable` abstürzen; neu starten und erst nach bestätigtem Recorder erneut injizieren. Es gibt keinen synthetischen Audio-Ersatz in der App.

`set-test-key.py` liest den vorhandenen Desktop-Schlüssel nur zur Laufzeit aus der MacBook-Konfiguration, übergibt ihn per stdin an `run-as` und löscht die private Übergabedatei beim Import. Niemals Schlüssel als Shell-Argument oder Intent-Extra übergeben. Der Receiver existiert ausschließlich im Debug-Source-Set und verlangt `android.permission.DUMP` (ADB-Shell/System).

```sh
adb -s emulator-5580 shell am broadcast -n com.paply.android/.DebugControlReceiver --es command direct-on
# Weitere Kommandos: direct-off, finish, discard. direct-off ist der Standard.
```

Die Kachel muss bei `cmd statusbar click-tile` gebunden sein: vorher `cmd statusbar expand-settings` und auf sichtbare Kachel warten. Ein während fehlender Bindung gesendeter Klick kann später nachgeliefert werden; keine Klick-Schleifen verwenden. UI-Hilfe: `/usr/bin/python3 scripts/device-ui.py [--tap TEXT]`.

## Lebensdauer und Daten

IME und Gedanken teilen eine exklusive Mikrofon-Lease. Aufnahme: `VOICE_RECOGNITION`, eingebautes Mikro bevorzugt, 16 kHz mono PCM16, kein Audiofokus/SCO. Negative `read()`-Werte beenden den Recorder. Jede Freigabe meldet `audio.released`; `isClientSilenced` und PCM-Pegel werden separat geprüft. Stille oder irgendwann stummgeschaltetes Audio wird nicht hochgeladen. Ein einfacher RMS-Schwellwert ersetzt in Phase 0 noch kein VAD.

IME: sichtbare Ansicht startet nach 120 ms Callback-Entprellung, Tipp beendet, Links-Wischen verwirft. Nach vollständigem Whisper/Polieren folgt `commitText`, dann Rückwechsel oder Systemauswahl. Kein Gesamt-Zeitlimit beim Polieren; 60 Sekunden Stream-Inaktivität gelten als Netzwerkfehler. Abbruch cancelt HTTP. Die temporäre WAV wird nach Ende/Abbruch gelöscht; nach Prozessabbruch beim nächsten App-Start.

Gedanken: maximal zehn Minuten; Karte wegwischen oder Home beendet die Aufnahme nicht. Nach bestätigtem Audioabschluss wird eine `.ready`-Datei geschrieben. Rohtext wird mit `AtomicFile` dauerhaft gespeichert, erst danach WAV und Marker gelöscht. Netzwerkfehler behalten Audio für einen expliziten Neuversuch. Unbestätigte Aufnahmen nach Prozessabbruch werden niemals automatisch gesendet und können in der App gelöscht werden. Kein Polieren der Gedanken in Phase 0.

Diagnoseprotokoll: ausschließlich Zustände, Dauer, Pegel, Zeichenlängen und Modellnamen; keine Transkripte, Schlüssel oder HTTP-Antworten. V1-Arbeit: vollständige PaplyKit-Portierung, echtes VAD, Historie/Vokabular, Safety-Net sowie Pixel-/Samsung-/Bluetooth-/Anruf-Tests.

Nach Tests eine gesetzte Test-PIN wieder entfernen und den Emulator mit `ssh macbook 'source ~/Android/env.sh; ~/Android/emu-stop.sh'` stoppen. Echte Groq-Aufrufe bewusst zählen; Unit-Tests verwenden ausschließlich MockWebServer.

## Release für Freunde (0.1.0)

Gebaut wird ausschließlich auf dem MacBook. `release` prüft die Signatur und holt nur die signierte APK
samt SHA-256-Datei nach `/tmp/paply-android-release/` auf den Mac mini:

```sh
PAPLY_WORK=rel android/scripts/mb.sh sync
PAPLY_WORK=rel android/scripts/mb.sh release
cd /tmp/paply-android-release && shasum -a 256 -c Paply-0.1.0.apk.sha256
```

Die Signierung liest auf dem MacBook `~/Android/keys/paply-release.properties` (Rechte `600`):
`storeFile` (absoluter Pfad außerhalb des Repos), `storePassword`, `keyAlias`, `keyPassword`.
Alternativ gelten `PAPLY_RELEASE_STORE_FILE`, `PAPLY_RELEASE_STORE_PASSWORD`, `PAPLY_RELEASE_KEY_ALIAS`
und `PAPLY_RELEASE_KEY_PASSWORD` in der **MacBook-Buildumgebung**; sie überschreiben Properties einzeln.
Ohne `keyPassword` gilt `storePassword`. Geheimnisse nie in Befehlszeilen, Logs oder das Repository schreiben.
Ohne Signierdaten erzeugt `assembleRelease` mit deutlicher Meldung eine unsignierte APK;
`mb.sh release` bricht dann ab, ohne sie zu verteilen. Unvollständige Angaben sind ein Konfigurationsfehler.

Keystore: `~/Android/keys/paply-release.jks`. Keystore **und** Properties außerhalb des Repos sicher sichern:
Updates müssen mit demselben Schlüssel signiert werden, sonst ist eine Neuinstallation mit Datenverlust nötig.
Für die nächste Version `versionName` ändern und `versionCode` erhöhen (`app/build.gradle.kts`).
Release verwendet R8 und Ressourcenverkleinerung, keine Debug-Receiver oder Testdaten.
Freundes-Anleitung: [FREUNDE.md](docs/FREUNDE.md), Begleittext: [FREUNDE-NACHRICHT.txt](docs/FREUNDE-NACHRICHT.txt).
Prüfstand und offene Punkte: [RELEASE.md](docs/RELEASE.md).

### PCM-Regression (Debug / lokale Fake-Server)

Der DUMP-geschützte Debug-Befehl `retain-pcm-on` behält die nächste und folgende
Live-IME-Aufnahmen als app-private `files/debug-live.wav` (jeweils überschrieben).
Nach Aufnahmeende per `adb exec-out run-as com.paply.android cat files/debug-live.wav`
abholen; `retain-pcm-off` deaktiviert und löscht die Datei. Standard ist aus.
Keine echten Stimmen als Testressourcen einchecken.

`RegressionAudioTest` prüft synthetische PCM mit MockWebServer. Optional führt
`-Ppaply.regression.fixtures=/absoluter/pfad` zusätzlich `testname.wav` und `long.wav`
aus (PCM16, mono, 16 kHz); explizit angegebene fehlende Dateien schlagen fehl.
Die beiden WAVs werden auch in 320er-Blöcken mit 20-ms-Takt geprüft.
`scripts/compare-capture.py quelle.wav aufnahme.wav` benötigt NumPy/SciPy und
liefert globalen Kreuzkorrelationsversatz sowie lokale 20-ms-Fenster.
Schwache Korrelation ist ein Hinweis auf verändertes Audio, kein alleiniger
Beweis für fehlende Wörter; periodische Sprache kann mehrdeutige Treffer liefern.
