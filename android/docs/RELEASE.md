# Paply Android 0.1.0 (1) · Release
Stand: 29.10.2026, 01:40 MEZ · signierte APK gebaut und geprüft.
- MacBook-Keystore: `~/Android/keys/paply-release.jks` (RSA 4096, CN Paply, 30 Jahre, Rechte 600).
- MacBook-Properties: `~/Android/keys/paply-release.properties` (Rechte 600); Geheimnisse nur dort bzw. in `PAPLY_RELEASE_*`.
- Beide Dateien sicher außerhalb des Repos sichern: Nur derselbe Schlüssel erlaubt Updates über bestehende Installationen. Verlust erzwingt Neuinstallation und gefährdet lokale Daten.
- Nächste Version: `versionName` ändern, `versionCode` erhöhen; `PAPLY_WORK=rel android/scripts/mb.sh sync`, dann `PAPLY_WORK=rel android/scripts/mb.sh release`.
- Ausgabe Mac mini: `/tmp/paply-android-release/Paply-0.1.0.apk` und `Paply-0.1.0.apk.sha256` (SHA-256 geprüft).
- `apksigner verify --print-certs` erfolgreich, Zertifikat CN=Paply; APK ca. 4,2 MB. Installation als Update mit gleichem Schlüssel ebenfalls erfolgreich.
- Ohne Signierdatei: `assembleRelease` erfolgreich UNSIGNIERT mit klarer Meldung; `apksigner` lehnt diese APK ab. `mb.sh release` prüft aktuelle Build-Metadaten gegen versehentlich alte signierte Artefakte.
- R8: Minify + Ressourcenverkleinerung aktiv; Serialisierer/JSON-Modelle, Worker und Receiver abgesichert, AndroidX-/Compose-Consumer-Regeln. Keine R8-Fehler, keine nachträglichen Keep-Korrekturen nötig.
- Debug-Receiver ausschließlich in `src/debug`; R8-Discard-Prüfungen für DebugControlReceiver und CaptureDebug bestanden. Release ist nicht debuggable; kein Beispieldaten-Import.
- Gerät: `paply3`, `emulator-5600`, Android 17/API 37; Debug-App samt Testpaket zuerst deinstalliert, danach Release frisch installiert.
- Einrichtung: Mikro und Benachrichtigungen erlaubt; Schlüssel einmal über `adb shell input text` ins Passwortfeld, Quelle nur zur Laufzeit wie `set-test-key.py`; gespeichert und erfolgreich geprüft. Kein Debug-Receiver.
- Tastatur aktiviert (Android zeigt zwei Bestätigungen); über System-Tastaturauswahl in Kontakte geöffnet. gRPC-Sprache → bestätigtes Einsetzen ins fremde Textfeld nach ca. 1,0 s.
- Diktat-Befund: 1,74-s-synthetischer Satz ungenau erkannt („Hallo Ellen, Tester Public.“). Kein Absturz. Erfolgsfläche bleibt laut aktuellem Code bis „Zurück zur Tastatur“ sichtbar; Anleitung angepasst.
- Gedanken-Kachel hinzugefügt, neuer weißer p-Kopf sichtbar; Aufnahme und Ende über die Kachel. gRPC-Sprache → Thema „Garten“, Aufgabe „Tomaten gießen“, fällig morgen.
- Gedanken- und Aufgaben-Reiter geprüft. Kleines Aufgaben-Widget über den Launcher hinzugefügt: Aufgabe, Datum und Zähler korrekt.
- Einstellungen zeigen `0.1.0 (1)`. Nach neuestem Release-Update und App-Kaltstart bleiben Thema, Gedanke, Aufgabe und Widget vorhanden.
- Groq: 2 Transkriptionen (je 1 Stück), 1 Diktat-Polieren, 1 erfolgreicher KI-Lauf, kein Retry/Fallback. Zusätzliche stumme IME-Aufnahme wurde ohne Upload verworfen; Diagnose gesichert.
- Kein Paply-FATAL, keine ClassNotFound-/Serialization-/WorkManager-Fehler. `rel-runtime-logcat.txt` leer; `rel-app-logcat.txt` und `rel-diagnostics.txt` liegen beim APK.
- Emulator-Systemdienst `android.hardware.uwb-service` wirft unabhängig SIGABRT wegen fehlendem `/dev/uwb0`; kein Paply-/R8-Absturz.
- Screenshots und Buildprotokolle: `/tmp/paply-android-release/rel-*`. Play-Protect-Verhalten beim Browser-Download und echte Samsung-/Pixel-Hardware bleiben offen (hier ADB-Installation).
- Neue Ressourcen: adaptiver Launcher (Wald + p-Kopf), Android-13-Monochrom, `ic_stat_paply` weiß und `ic_paply` farbig. Kachel-Manifest, Erinnerungen und Zwischenablage-Mitteilung umgestellt.
- Bauleitung, nicht geändert: `thoughts/ThoughtNotifications.kt:33,48,66` → `R.drawable.ic_stat_paply`; diese Mitteilungen nutzt `ThoughtService.kt` (dort aktuell kein eigener Icon-Verweis).
- Bauleitung, außerhalb meines Bereichs: `ui/SetupStatus.kt:54` (Kachel-Dialog) → `ic_stat_paply`; `res/layout/thought_widget.xml:5` → `ic_stat_paply` mit Tint oder `ic_paply` ohne Tint.
- `paply3` nach der Prüfung gestoppt; `paply` und `paply2` laufen unverändert weiter.
- Anleitung: `FREUNDE.md`; WhatsApp-Text: `FREUNDE-NACHRICHT.txt` (7 Zeilen). Kein Commit, Push oder Upload.

## Sicherung des Signierschlüssels (29.10.)
- Die Bauleitung verwaltet die Sicherung, Allan muss sich nicht darum kümmern.
- Original: MacBook `~/Android/keys/` (`paply-release.jks`, `paply-release.properties`).
- Kopie: Mac mini `~/Paply-Android-Schluessel/`, Rechte 700/600, SHA-256 gleich, nicht im Repo.
- Ohne diesen Schlüssel lassen sich Updates nicht über bestehende Installationen spielen. Freunde müssten neu installieren
  und verlören ihre lokalen Daten.

## Hotfix 0.1.2 (3), 29.10.2026
Startabsturz auf Android 10–13 durch Java `Stream.toList()` im JVM-Modul behoben;
zusätzliche isolierte Fehlerseite mit teilbarem, inhaltsfreiem Bericht.
Reproduktion, Retrace, vollständige Acht-Versionen-Matrix, Prüfsumme und Auslieferung:
[STARTUP-0.1.2.md](STARTUP-0.1.2.md).

## Kompatibilitätsfix 0.1.3 (4), 29.10.2026

Animal Sniffer prüft `:core` und `:thoughts` automatisch gegen API 29;
`InputStream.readNBytes` beim Lesen des WAV-Headers durch kompatibles
`DataInputStream.readFully` ersetzt. Core-Library-Desugaring bleibt aus.
Methode, Negativkontrolle, Test- und DEX-Befunde: [API-29.md](API-29.md).
850 Tests, 0 Fehler, 1 übersprungen; Debug, signierter Release und Release-Lint
mit 0 NewApi erfolgreich. Release auf API 30 und 37 einschließlich Update über
0.1.2, Kachel/Verarbeitung, Diktat, Landkarte, Aufgaben und Widget geprüft.

APK SHA-256: `354011c083bde263104e174676a422e49b221988a1780cf78c6193429699c441`.
MacBook: `~/Desktop/Paply-Android/Paply-0.1.3.apk`, `Paply-0.1.3.zip`,
`FREUNDE.md`, `FREUNDE-NACHRICHT.txt`; 0.1.2-Ausgaben entfernt, keine
Prüfsummendatei auf dem Schreibtisch. Signierschlüssel unverändert.

## Einrichtungskorrektur 0.1.4 (5), 29.10.2026

Der Tastatur-Test ist dauerhaft erledigt, sobald Paply einmal in `onStartInputView`
erschienen oder aktuell ausgewählt ist. Der normale Rückwechsel zur vorherigen
Tastatur öffnet keinen Einrichtungsschritt mehr. Wird Paply deaktiviert, löscht die
Statusprüfung die Markierung. Einrichtung, Diktat-Karte, Gedanken-Fortschritt und
Einstellungen verwenden denselben Status. Ein Testfeld steht in der Tastatureinrichtung;
nach Abschluss bleibt nur der Hinweis auf das Tastatur-Symbol.

- Ausschließlich auf dem MacBook: `PAPLY_WORK=v014 android/scripts/mb.sh sync`,
  `build` mit `:core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:lintRelease`,
  danach `release`; alles erfolgreich, einschließlich Animal Sniffer und signiertem R8-Release.
- 852 Unit-Tests, 0 Fehler, 1 übersprungen. Neue Tests: erste Auswahl,
  Rückwechsel, wiederholte Auswahl, Deaktivieren und erneutes Aktivieren.
- Android 11/API 30 (`paply30`, neu angelegt) und Android 17/API 37 (`paply`):
  signierter Release als Update über 0.1.3 installiert; Schlüssel und Einrichtung erhalten.
  Je einmal Paply über die Systemtaste gewählt, gRPC-Sprache eingespeist,
  Diktat ins Kontakte-Textfeld eingesetzt und automatisch zu Gboard zurückgekehrt.
- Auf beiden Versionen nach App-Kaltstart: Einrichtungskarte weg (6/6),
  „Paply ist bereit“ mit ruhigem Nutzungshinweis und Einstellungen „eingerichtet“.
  Nachfolgend auch das finale APK mit vorgezogenem Testfeld installiert und kalt geprüft.
- Android 11 zusätzlich: Deaktivieren öffnet Aktivierung und Test erneut;
  erneutes Aktivieren allein schließt den Test nicht. Keine weitere Sprache hochgeladen.
- Groq: insgesamt 2 abgeschlossene Diktate, je eine Transkription und ein Polierlauf;
  keine manuellen Neuversuche oder Gedanken-Aufrufe. Synthetische deutsche Sprache wurde
  wegen der englischen Emulator-Sprache englisch ausgegeben; Einsetzen/Rückwechsel erfolgreich.
- Android-17-Emulator 37.2.12 stürzte zweimal bei gRPC im nativen Audio-Code ab
  (`Socket closed`, `Internal logic error voice 'unknown' has no hardware store`).
  Beide vor Aufnahmeabschluss/Upload. Mit `-audio none` funktionierte die echte
  gRPC-Einspeisung in den aktiven Paply-Recorder samt Transkription und Rückwechsel.
- Belege auf dem MacBook: `~/Android/work/v014-evidence/` (XML, Screenshots, Emulator-Logs),
  Build-/Release-Protokolle auf dem Mac mini: `/tmp/paply-v014-*-final.log`.
- APK SHA-256: `977a8244910842cb4ce28287899cb902175c5ac6061b65af6d37048c64e34658`.
- Auslieferung MacBook: `~/Desktop/Paply-Android/Paply-0.1.4.apk`, `Paply-0.1.4.zip`,
  `FREUNDE.md`, `FREUNDE-NACHRICHT.txt`. 0.1.3-Artefakte entfernt; keine `.sha256` dort.
  Signierschlüssel unverändert. Emulatoren nach der Prüfung gestoppt. Kein Commit/Push.

## 0.2.0 (6) – 29.10.2026
- Paply-Knopf (Bedienungshilfe) als Hauptweg; geprüft auf API 30/34/37 (Emulator), u. a. kein doppeltes Einsetzen, Zwischenablage bleibt auf API 29–32.
- SHA-256 `29d83a3a5236f9bfd9b3b4317d1b1fc0a5639154302e54b32e7d9363bc142955`, Commit `51028d9`.

## 0.2.1 (7) – 29.10.2026
- Tester-Feedback (Samsung S22, Android 16): Einrichtung führt in richtiger Reihenfolge durch die Android-Sperre („Eingeschränkte Einstellung“ erst nach blockiertem Versuch), Paply in der Bedienungshilfe hervorgehoben, Samsung-Pfad „Installierte Apps“.
- Knopf neu: Pegelringe statt Pille mit Zeit/„Fertig“, Tipp auf den Knopf = einsetzen, X = verwerfen, kurzer Haken statt Erfolgstext; sitzt über der Eingabezeile (Senden frei), weicht tippbaren Elementen aus, gleitet bei Feldwechsel, bleibt während Aufnahme immer sichtbar; Leerzeichen ab Android 13; 9-min-Vorwarnung mit Haptik.
- Abnahme Emulator API 30/34/36 (Sideload über Dateien-App, Instrumented + manuell, Google Messages): bereit. Rest klein: im Querformat mit mehrzeiligem Entwurf überlappt der Knopf die leere Feldecke; im Vollbild-Editor teils über der „Weiter“-Taste.
- SHA-256 `e3db4757a8b4edfcaf18aeaf0446e19d14bd866e8b2b6ccf35579b87b19dbbd3`, Commit `b075036`.
