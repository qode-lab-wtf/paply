# Etappe 1 D · Android-Tastatur

Stand: 28.10.2026. Vorgängerstand fortgeführt, ausschließlich unter `android/`; kein Commit/Push.
`thoughts/` sowie dessen Änderungen an Core-Sichtbarkeiten, Settings und Versionskatalog unangetastet.

## Umsetzung
- `AudioCapture` speist PCM16/16 kHz fortlaufend in `DictationPipeline.append`; Stücke gehen schon beim Sprechen hoch.
- Konfiguration aus `SettingsRepository.snapshot()`, Schlüssel ausschließlich `KeyVault.read()`;
  `KeyVault.save()` bereinigt mit `sanitizeApiKey()`. Phase-0-`Settings.apiKey`/`client()` entfernt.
- Gedanken-Dienst nur auf KeyVault umgestellt; Lesen dort auf IO, sonst keine Dienst-Neuentwicklung.
- `LocaleList`, jüngste Rohdiktate, TextClassifier-Spracherkennung, monotone Uhr und ConnectivityManager angebunden.
- Netzwechsel setzt Groq-Verbindungen zurück. Vorwärmen neben Aufnahme, erst bei erkannter Stimme:
  auch ein stilles Durchschalten verursacht damit keinen Groq-Aufruf, nicht einmal `/models`.
- MediaCodec liefert vollständiges FLAC mit `fLaC`/STREAMINFO/Samplezahl, WAV bleibt verlustfreier Rückfall.
- Aufnahme ohne Sprechpausen-Stopp, kein Live-Text, kein automatisches Senden, kein Polier-Gesamtzeitlimit.
- Verlauf: PENDING während Verarbeitung/bei fehlendem Ziel, FAILED mit WAV, OK nach Erfolg.
  Dauerhafter Text wird atomar vor Audio-Löschung geschrieben. Retry in App/IME aktualisiert dieselbe ID.
  Gelöschte Einträge werden durch späte Ergebnisse nicht wiederhergestellt; Prozessabbruch wird lokal erkannt.
- Compose-Panel: hört zu → schreibt → Eingesetzt/Fehler; Setup, Wiederholen, Kopieren, Links-Wischen.
  Haptik erst bei VAD-Stimme. Höhe am AVD wie Gboard: etwa 336 dp hochkant / 260 dp quer, inklusive Navigation.
- Editoridentität wird geprüft; aktuelle InputConnection desselben Feldes wird verwendet.
  `commitText=true` ist nur „gesendet“: lesbarer Gegencheck, bei Widerspruch Zwischenablage + PENDING.
  Ohne lesbaren Gegencheck heißt der Zustand ausdrücklich „An Textfeld gesendet“; Verlauf bleibt erhalten.
- Passwortvarianten Text/Web/Zahl/sichtbar gesperrt. Bei verborgenem Panel wird das Mikro freigegeben.
- Android-ICU lehnt `UNICODE_CHARACTER_CLASS` ab: einmaliger Plattform-Probe, Unicode-JVM-Verhalten erhalten.
- `set-test-key.py` räumt die Übergabedatei auch bei Broadcast-Fehler im `finally` auf.

## Abnahme auf dem MacBook
AVD `paply`, Android 17/API 37, 1080×2424/420 dpi, Gboard `18.0.3.954559732-preload-arm64-v8a`.
Nur `PAPLY_WORK=ime`; vor Neuinstallation deinstalliert. Kein Gradle/SDK/Download auf dem Mac mini.
`GRADLE_TASKS=":core:test :app:assembleDebug :app:lintDebug"`: **284 Tests**, Build grün, Lint 0 Fehler/3 Warnungen.
`GRADLE_TASKS=":app:connectedDebugAndroidTest"`: **8 Tests grün** (ICU 3, Adapter 3, dauerhafte Speicherung 2).
Lint-Warnungen: externe Lifecycle-Lint-API, Panel-Configuration-Höhe, Test-Runner-Version außerhalb Katalog.

1. **Testname:** im Rohtext und poliert korrekt, Eigene Begriffe `Testname`; Vorgänger-Verlauf gegengeprüft.
2. **Kurz de:** „Hi, wie geht's?“ bei de+en/Hauptsprache de, 1,54 s Aufnahme, erneut im Feld bestätigt.
3. **Englisch:** 7,68 s, kompletter englischer Satz, keine Übersetzung; Verlauf/Screenshot gegengeprüft.
4. **Lang:** 26,304 s, 3 Stücke, vollständig bis „gehen nach Hause.“; Uploads nach ca. 11 und 22 s, vor Stopp.
5. **Stille/Durchschalten:** 0 Requests, 0 Haptik, 0 Einträge; Mikro frei. Finale Core-NoSpeech-Ergebnisse ebenfalls verwerfen.
6. **Passwort:** sichtbarer Sperrhinweis, keine Aufnahme; alle vier Varianten zusätzlich instrumentiert.
7. **Drehen:** Panel neu aufgebaut; wenn die Ziel-App dabei das Keyboard ganz entfernt, Aufnahme sicher beenden.
   Bereits Gesprochenes wird dann verarbeitet/gesichert, ohne unsichtbares Mikro. Nahtloses Weiterlaufen ist nicht garantiert.
8. **Feldwechsel beim Schreiben:** neues Feld bleibt leer, Zwischenablage + Hinweis + PENDING, Audio entfernt.
   Zusätzlich ablehnender echter Test-Editor: `sent=true`, `confirmed=false` → Kopier-Fallback; manuelles Einsetzen danach OK.
9. **Flugmodus:** zwei lokale Netzwerkversuche → FAILED, WAV 52.780 B erhalten; App-„Erneut versuchen“ → dieselbe ID OK, WAV weg.
10. **Ein-Tipp:** Gboard mit einem Untertyp + Paply: 1 Tipp. Gboard en+de: von EN zuerst DE, dann Paply = 2 Tipps;
    von DE sowie nach Paply-Rückwechsel zu DE = 1 Tipp. Einrichtung erklärt Systemtaste, weitere Sprache und Langdruck.
    Paply kann die Android-Reihenfolge nicht erzwingen und verändert keine Gboard-Sprachen automatisch.
11. **FLAC:** Android-Decoding bytegenau verlustfrei, echte Groq-Uploads erfolgreich. Kurz 21.140 statt 49.196 B (−57 %);
    lang über 3 Stücke 539.002 statt 841.860 B (−36 %). WAV-Fallback instrumentiert geprüft.
12. **Tempo:** final kurz Tipp→commit 784 ms, Tipp→im Editor bestätigt 866 ms; lang 1.061/1.148 ms (Vorgänger).
13. **Stabilität:** kein FATAL des Produktprozesses im Abnahmelog; Mikro nach Ende frei. Emulator zum Abschluss gestoppt.

## Verbrauch, Belege und Grenzen
Belegt inkl. Vorgänger: **12 Transkriptionsversuche, davon 2 offline**, also 10 erfolgreiche Groq-Transkriptionen;
**8 Polier-Aufrufe**. Vor 21:54 fehlt ein durchgehendes Log; konservativ etwa 12–14/8–10 budgetieren, unter 20/20.
Belege: `/tmp/paply-android-e1/ime-*.png`, `evidence/ime-*-logcat.txt`, `ime-*-history.json`,
`ime-offline-{before,after}-retry.txt`, `ime-device-tests-final.xml`, `ime-build-final.txt`, `ime-final-state.txt`.
`evidence/` liegt unter `/tmp/paply-android-e1/`; alte UI-C-Belege dort nicht überschrieben.
Vorläufige Kotlin-Test-Activity hatte einen Test-APK-Runtimefehler; Java-Fassung läuft separat, nie im Produkt enthalten.
Physische Pixel/Samsung, Bluetooth/Anrufe und ältere Android-Versionen sind durch diese Emulator-Abnahme nicht abgedeckt.
Wichtigste Quellen: `app/.../PaplyIme.kt`, `ImePanel.kt`, `dictation/{DictationSession,AndroidAdapters}.kt`,
`AudioCapture.kt`, `history/HistoryStore.kt`, `settings/KeyVault.kt`, `ui/{Setup,Dictation}Screens.kt`, `app/src/androidTest/`.
