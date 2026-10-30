# Paply iOS — Verlauf

Übersicht aller Apps: [../STAND.md](../STAND.md).

## Paply iOS — „Gespräche“ (29.10.2026, in `feat/ios-v1` zusammengeführt; Weiterbau auf `feat/ios-gespraeche`, Build 9)

- **Was:** iPhone liegt beim Meeting, Gespräch vor Ort oder Telefonat (anderes Handy auf Lautsprecher) daneben und
  nimmt auf; danach Personen, Wortlaut, Zusammenfassung, Aufgaben, Thema. Bauplan `ios/docs/gespraeche/KONZEPT.md`,
  Messung `ios/docs/gespraeche/MESSUNG.md`.
- **Allans Vorgaben (29.10.):** nur Mikro dieses iPhones (keine iOS-Anrufaufnahme, kein Import); Ton nach fertiger
  Auswertung löschen, kein „Erneut auswerten“, kein Anhören; „Person 1/2/3“, bis der Besitzer sicher erkannt oder per
  Tipp bestätigt ist – erst dann landen seine Aufgaben im Reiter; Pause/Weiter wie Sprachmemos, Pausen im Wortlaut.
- **Technik:** Sprechererkennung auf dem Gerät (FluidAudio Nemotron-3 fast128 FP16 + CAM++-Stimmabdrücke, Modelle
  199 MB werden beim ersten Gebrauch geladen), Text Groq `whisper-large-v3` (eigenes Kontingent, Diktat behält turbo),
  Auswertung `gpt-oss-120b`/`-20b` (nie qwen). Eigene Stimme lernt Paply nebenbei aus Gedanken (≥ 3 stimmige Clips),
  Rückfall „Jetzt einsprechen (20 s)“.
- **Geprüft:** 723 PaplyKit-Tests, App Debug/Release (Xcode 26.0.1 Mac mini, 26.5 MacBook), zwei Sonnet-Reviews mit
  allen Befunden behoben, Bildschirmfotos im Simulator. Messung: deutsche Simulationen fast fehlerfrei, echte englische
  Meetings 12–19 % falsch zugeordnete Wörter (v. a. kurze Einwürfe; dafür Einwurf-Regeln und KI-Plausibilisierung).
- **29.10., 16:23:** Debug-Build 9 drahtlos auf Allans iPhone (kein TestFlight-Upload). Offen: echte Aufnahmen von
  Allan (Telefon über Lautsprecher, Runde mit 3+), Gerätemessung Tempo/Speicher/Hitze (auch iPhone 12 Pro).
- **29.10., abends:** auf Allans Wunsch in `feat/ios-v1` zusammengeführt, damit iOS beisammen ist. Beta „Gespräche“
  ist in TestFlight/Release ohne gespeicherten Wert AUS (Debug AN), bis der Gerätetest bestanden ist; einschalten unter
  Einstellungen → Beta. Neue Gespräche-Stände kommen per Merge aus `feat/ios-gespraeche` nach.

## Paply iOS — Version 1 für TestFlight (27.10.2026, Branch `feat/ios-v1`)

- **Phase 0 auf dem Gerät bestätigt** (iPhone 14 Pro Max, iOS 18.0): 🌐 → Paply-Tastatur → sprechen → Tipp →
  polierter Text im Feld. Gedanken-Knopf startet das Mikro auch ohne laufende App im Hintergrund (S1,
  `ios/docs/gedanken/S1-TEST.md`). iOS zeigt bei Hintergrund-Mikro ein Mikro-Symbol, nicht nur den Punkt.
- **Version 1 (Scope eingefroren):** Diktat über 🌐 und „Gedanken“ (Knopf auf Sperrbildschirm/Kontrollzentrum,
  Fertig/Verwerfen in der Live Activity, KI ordnet Titel/Thema/Aufgaben/Verknüpfungen, Reiter Gedanken),
  Einrichtungskarte, Datenschutz-Klartext, Feedback senden. Konzept `ios/docs/gedanken/KONZEPT.md`,
  KI-Bewertung `ios/docs/gedanken/EVAL.md`, TestFlight-Ablauf und Texte `ios/docs/TESTFLIGHT.md`.
- **TestFlight (27.10., abends):** 0.1.0 Builds 1, 2, 3 per SSH vom MacBook hochgeladen (Ablauf in der Erinnerung
  „TestFlight-Upload per SSH“). Build 3: Landkarte, Aufgaben-Reiter, Themenbilder, KI-Regeln v6, Mikro startet erst bei
  aktiver App, Selbstheilung bei stummem Mikro. Build 4 (28.10., 03:41): Aufgaben-Widgets, Erinnerung zur Uhrzeit,
  Beta-Schalter, neue Anleitung. Offen bei Allan in App Store Connect: externe Gruppe „Freunde“, Testinformationen,
  Prüf-Schlüssel für Apple, dann öffentlicher Link.
- **Build 5 (28.10., Kandidat für Freunde) – zwei Gerätefunde von Allan:**
  - Kurze Sätze („Hi, wie geht's“) kamen auf Englisch, einmal als „ru“: Whisper rät die Sprache je Anfrage. Jetzt
    gehen Stücke mit ≤ 5 s gesprochener Zeit direkt in der Hauptsprache raus (Einstellung „Hauptsprache“, Standard
    erste iPhone-Sprache); längere mit fremd erkannter Sprache werden einmal in der Hauptsprache wiederholt.
  - Anrufe klingelten und vibrierten in Bereitschaft nicht: `setPrefersNoInterruptionsFromSystemAlerts` stand
    dauerhaft an. Jetzt nur während einer Aufnahme. Offen: Ob Nachrichten in Bereitschaft vibrieren (Allan vermutet
    nein) – falls nicht, Mikro im Leerlauf anhalten (Experiment `idlePause`, auf dem Gerät noch ungetestet).
- **Build 6 (28.10., nachmittags):** Absturz nach Anrufen behoben (AVAudioEngine warf beim Wiederaufnehmen eine
  Objective-C-Ausnahme wegen eines veralteten Formats): frische Engine, Tap ohne festes Format, Ausnahmen über das
  neue Ziel `PaplyObjC` abgefangen. Auf drei Test-iPhones per Kabel/WLAN installiert (Debug).
- **„Alle sehen Daten von anderen“ (28.10.) – kein Datenleck:** Es gibt keinen Server und keine geteilte Datenbank,
  alles liegt nur auf dem jeweiligen iPhone. 
  
- **Build 7 (28.10., abends):** Verlässt man die App, während ein Gedanke läuft, erscheint oben sofort ein Banner
  (ohne Dynamic Island, z. B. iPhone 12 Pro) bzw. klappt die Dynamic Island auf – mit Sekundenzähler, „Fertig“
  und „Verwerfen“, dazu eine Vibration; alle 2 Min. wieder, „noch 1 Min.“ ebenso. Grenze bleibt 10 Min. (Allan).
  Hochgeladen und auf alle drei iPhones gespielt.
- **Build 8 (28.10., lokal):** Eigene Themen mit + vorab anlegen (auch leer als Chip); einzelne oder mehrere
  Themen wahlweise samt Gedanken nach „Zuletzt gelöscht“ verschieben. Noch nicht auf dem Gerät getestet oder hochgeladen.
- **TestFlight extern:** Gruppe „Testing“ mit öffentlichem Link <TestFlight-Link>
  (bis 10 Tester). Build 5 liegt bei Apple zur ersten Prüfung (eingereicht 28.10. mittags); Apple schickt eine
  E-Mail, wenn sie durch ist. **Danach (Allan):** neuesten Build (7) der Gruppe „Testing“ hinzufügen, Link
  verschicken und den Prüf-Schlüssel für Apple bei Groq löschen. Neue Tester bekommen danach jeden Build ohne
  lange Prüfung.
- **Offen – Gerätetests:** kurze Sätze in der Hauptsprache, Anruf in Bereitschaft (klingelt/vibriert?), Diktat
  direkt nach einem Anruf (kein Absturz), WhatsApp-Vibration in Bereitschaft, Banner und Vibration aus Build 7,
  Experiment `idlePause` (Mikro-Symbol weg? Diktat nach 5/30 Min.?). Klappt `idlePause`, wird es Standard und
  das Mikro wacht schon beim Erscheinen der Tastatur auf. Angeboten: Bereithalten standardmäßig „1 Stunde“.
- Offen: Test `cancelAbortsRunningChunkUploadImmediately` wackelt unter Last (einzeln grün).
- Geprüft: PaplyKit 384 Tests grün, App/Tastatur/Widgets bauen Debug und Release; mehrere Opus-Reviews und ein
  unabhängiger Sonnet-Produkttest. Der zusammengeführte Stand ist auf dem Gerät noch nicht getestet.
- Bauen/Signieren: Mac mini entwickelt, MacBook (Xcode 26.5, iOS-Plattform installiert) signiert; Signieren nur
  aus der Xcode-Oberfläche (Schlüsselbund über SSH gesperrt). App in App Store Connect angelegt.
- KI-Prompt v2; Bewertung E1 Tag 1 (v1) mit 18 Fällen, weitere Läufe im Free-Tier verteilt (≤ 60 000 Tokens/Tag,
  gpt-oss-120b, nie qwen).
- **Nach Version 1 (Allan zugestimmt bzw. vorgeschlagen):** Widget „Offen“ (Sperrbildschirm nur Zahl, Home bis
  3 Aufgaben abhakbar, keine Mitteilungen), Gedanken per Tastatur einsetzen, „In WhatsApp öffnen“ für erkannte
  Nachrichten, „Frag deine Gedanken“, Spotlight/Siri, Teilen → Paply, Mehrsprachigkeit der Oberfläche,
  Paply-Zugang ohne eigenen Groq-Schlüssel (Server).
- **Vorgemerkt, noch nicht bauen (Allan, 27.10.):** Eine Aufnahme mit klar getrennten Sachen in mehrere Gedanken
  aufteilen, jeder mit eigenem Thema. Nur aufteilen, wenn die Teile eindeutig nichts miteinander zu tun haben; im
  Zweifel bleibt es ein Gedanke. Die Teile verweisen aufeinander („Aus einer Aufnahme“). Heute wird aus einer
  Aufnahme genau ein Gedanke; Thema und Titel richten sich nach der Hauptsache, Aufgaben werden alle erkannt.
- **Vorgemerkt für später (Allan, 27.10.):** Meeting-Modus – mehrere Personen in einer Besprechung, daraus
  Protokoll und To-dos.
- Nebenwirkung 27.10.: Die Mac-Latenzmessung hat das Free-Tier-Polierkontingent (qwen) von Allans Groq-Schlüssel
  fast aufgebraucht; das Desktop-Diktat setzte bis zur Erholung Rohtext ein.
