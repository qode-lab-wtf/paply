# Paply Android — Verlauf

Übersicht aller Apps: [../STAND.md](../STAND.md).

## Paply Android — V1 im Aufbau (28.10.2026, Branch `feat/android-v1`, Ordner `android/`)

- **Ziel:** gleiche Qualität, gleiches Design und gleiche UX wie Paply iOS V1, als APK-Testversion für Freunde.
  Kotlin + Jetpack Compose, nativ. `ios/` ist nur Vorlage.
- **Arbeitsteilung:** Claude (Opus 5.5) plant und entscheidet, Codex setzt um, Sonnet 5.5 prüft jedes Ergebnis.
- **Rechner:** Gebaut und getestet wird nur auf dem MacBook (M5, 32 GB, 136 GB frei). Dort liegen Java, Android-Werkzeuge
  und der Emulator `paply` in `~/Android`; mit `rm -rf ~/Android` ist alles wieder weg. Allan hat das am 28.10.
  freigegeben. Der Mac mini ist knapp an Platz, dort entsteht nur Quelltext; nach dem T3-Update kann das MacBook
  direkt als Umgebung verknüpft werden.
- **Phase 0 bestanden (28.10., Emulator Android 17/API 37, `android/docs/PHASE0.md`):**
  - Die Paply-Tastatur nimmt beim Erscheinen sofort selbst auf, ohne Bereitschafts-Mikro, und setzt polierten Text
    (de/en) in ein fremdes Feld (Kontakte) ein. Danach geht es zurück zu Gboard, links wischen verwirft.
  - Die Gedanken-Kachel startet eine Aufnahmekarte und einen Mikro-Vordergrunddienst. Die Benachrichtigung zeigt
    einen Zähler sowie „Fertig“ und „Verwerfen“. Ein Live-Update-Chip mit Zähler steht in der Statusleiste.
  - Das klappt auch bei gesperrtem Gerät. Nach 10 Min. ist automatisch Schluss.
  - Der Mikro-Punkt erscheint nur während der Aufnahme.
  - Groq: 8 Aufrufe.
- **Review Phase 0** (Sonnet): 18 Funde mit Zuordnung in `android/docs/REVIEW-P0.md`. Vor Gerätetests Pflicht:
  - Mikro-Recht vor dem Dienststart
  - kein Auto-Start nach Drehen
  - kein Datenverlust bei Lesefehler oder Anruf
- **Einstieg** (`android/docs/EINSTIEG.md`): Auf Pixel mit Android 16/17 wechselt ein Tipp auf die Systemtaste unten rechts
  direkt zur nächsten Tastatur. Das ist ein Ein-Tipp-Start wie 🌐 bei iOS (im Emulator noch zu bestätigen).
  Samsung: Navigations-Tastaturtaste. Eine schwebende Taste wie bei Wispr Flow ist erst nach V1 eine Option
  (Overlay + Bedienungshilfe).
- **Etappe 1 (Diktat komplett), im Emulator abgenommen (`android/docs/E1-IME.md`):**
  - Der Diktat-Kern aus iOS ist portiert (`android/docs/E1-CORE.md`, 284 Tests).
  - Die App-Oberfläche ist in Compose gebaut, der Schlüssel liegt im Keystore.
  - Die Tastatur lädt Stücke schon beim Sprechen hoch (FLAC −36 bis −57 %).
  - Tempo: Tipp → Text im Feld in 0,9 s (kurz) bzw. 1,1 s (26 s langes Diktat).
  - Richtig erkannt: „Testname“ über die Eigenen Begriffe, „Hi, wie geht's?“ auf Deutsch, Englisch unübersetzt.
  - Bei Stille gibt es keinen Groq-Aufruf. In Passwortfeldern nimmt Paply nicht auf.
  - Im Flugmodus wird das Diktat als fehlgeschlagen gespeichert, „Erneut versuchen“ klappt danach.
  - Ein Tipp auf die Systemtaste genügt, bei Gboard mit zwei Sprachen teils zwei Tipps.
  - Offen: ein gebündeltes Review samt Korrekturrunde.
- **Etappen 2 und 3 gebaut (29.10. nachts):**
  - Gedanken: Kern `:thoughts`, E0 10/11, Aufnahme-Dienst, WorkManager, Oberfläche, Landkarte
  - Aufgaben-Reiter, Erinnerungen, Aufgaben-Widgets
  - Release-Vorbereitung: Icon, R8, signierte APK 0.1.0, `android/docs/FREUNDE.md`
  - Endreviews: kein Blocker. Endkorrekturen (`REVIEW-P0.md`, „Endreview“) laufen.
- **0.1.0 freigabefähig (29.10. vormittags):**
  - Abschlussprüfung der Release-APK auf Android 17 und 14 (`android/docs/E2E-FINAL.md`): kein Blocker, kein Absturz,
    Kernfunktionen bestanden.
  - Die APK liegt mit Anleitung auf Allans MacBook unter `~/Desktop/Paply-Android/`, SHA-256 `1a00fd03…dae9`.
  - Der Signierschlüssel ist auf MacBook und Mac mini gesichert (`android/docs/RELEASE.md`).
- **0.1.1 (2) fertig** (`android/docs/V011.md`): Lange Stille im Live-Diktat geht nicht mehr an Whisper. Drehen auf Android 17
  sichert Gesprochenes (Zwischenablage + Hinweis). Update über 0.1.0 geprüft. APK `~/Desktop/Paply-Android/Paply-0.1.1.apk`
  (SHA-256 `59d4862d…c522`). Rest-Grenze: Periodisches Emulator-Rauschen gilt bewusst nicht als Stille.
- **0.1.2/0.1.3 (29.10.):**
  - Der erste echte Nutzer (Xiaomi Mi 9, Android 11) meldete einen Absturz beim Start. Ursache: `Stream.toList()` gibt es
    erst ab API 34. Behoben, Start auf API 29–37 geprüft (`android/docs/STARTUP-0.1.2.md`). Eine Fehlerseite ersetzt das
    stille Schließen.
  - Seit 0.1.3 prüft Animal Sniffer `:core`/`:thoughts` gegen API 29 (`android/docs/API-29.md`), dabei wurde
    `readNBytes` gefunden und ersetzt.
  - 0.1.4: Die Einrichtung fordert „Tastatur auswählen“ nicht mehr nach jedem Diktat neu (Samsung-Tester).
- **0.2.0 (29.10., Allans Entscheidung nach Testerfeedback):** Paply-Knopf neben der normalen Tastatur (Bedienungshilfe):
  1 Tipp aufnehmen, 1 Tipp einsetzen, eigene Tastatur bleibt. Auf API 29–32 setzt er direkt ins Feld (ohne Zwischenablage), ab
  API 33 per `commitText`. Gedanken-Karte blendet nach dem Speichern aus. Polier-Prompt aus `shared/polish`. Emulator-Abnahme
  API 30/34/37 (`android/docs/KNOPF.md`). Codex darf seit dem T3-Update keine Emulator-UI steuern → Abnahmen macht die
  Leitung per Claude-Helfer. Seit 29.10. abends: MacBook (T3 0.1.4) als Umgebung verknüpft (Tailscale, bis 28.11.,
  `t3 environment list`), SDK unter `~/Library/Android/sdk` verlinkt – Helfer können dort künftig selbst Emulatoren nutzen.
  - Branch `feat/android-v1` liegt als Sicherung auf GitHub (kein PR, `main` unberührt).
- **0.2.1 (29.10., nach S22-Test von Allan):** Einrichtung führt in richtiger Reihenfolge durch die Android-Sperre
  (Freigabe-Menü erscheint erst nach blockiertem Versuch; Samsung: „Installierte Apps“). Knopf mit Pegelringen statt Pille,
  Tipp = einsetzen, X = verwerfen, nur Haken statt Erfolgstext; sitzt über der Eingabezeile (Senden frei), bleibt während
  der Aufnahme immer sichtbar. Emulator-Abnahme API 30/34/36 bestanden (`android/docs/RELEASE.md`).
  - Aktuell zum Verschicken: `~/Desktop/Paply-Android/Paply-0.2.1.apk`.
- **Offen ohne echtes Gerät:** Pixel bzw. Samsung real, Anrufe, Bluetooth, Hersteller-Sperrbildschirm.
- **Danach V1 in Etappen:** Gedanken (Kachel, Widget, Benachrichtigung, KI ordnet) → Landkarte, Aufgaben,
  Erinnerungen → Feinschliff und Robustheit → APK für Freunde. Ein echtes Gerät entscheidet Allan.

## Ideen Android (Tester 29.10., noch nicht beauftragt)
- Konto bzw. Abgleich: Transkripte vom Handy auch am Laptop (Desktop-Paply). Das braucht einen Server oder Sync und
  widerspricht „Daten nur auf dem Gerät“. Allan entscheidet.
- Paply-Knopf in der Werkzeugleiste von Gboard bzw. Samsung-Tastatur: Fremde Apps können das nicht. Die Systemtaste unten
  in der Navigationsleiste ist der Weg.
