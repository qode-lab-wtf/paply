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
