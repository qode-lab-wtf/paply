# Entscheidungen

Frühere Entscheidungen des lokalen Codex-Versuchs: `docs/archiv/codex-lokalversuch-2026-09-21/ENTSCHEIDUNGEN.md`.
Weiter gültig daraus: kostenloser Betrieb, Diktat unverändert, Deutsch, neutrale Sprecher-Labels mit
nachträglicher Benennung, Auswertung nach dem Stop, Originalton 7 Tage, Transkript/Bericht dauerhaft.

## 2026-09-21 — Gemini-Audio statt lokaler Modelle (von Allan bestätigt)

Meeting-Auswertung über Gemini-Audio (kostenloses Free-Tier) statt lokaler Modelle; Basis `main`;
Audio 7 Tage behalten; neues Bericht-Layout direkt in der App. Der lokale Ansatz
(faster-whisper, MossFormer, pyannote, Ollama) ist verworfen: zu langsam, inkonsistente Sprecher.

## 2026-09-21 — Update der Alltags-App ohne vorherigen Praxistest (von Allan bestätigt)

Allan: Meeting-Modus „hat vorher auch nicht funktioniert richtig“, daher Update freigegeben,
solange das Diktat (Cmd+X) weitergeht. v1.13.0 veröffentlicht; Diktat-Code ist vom Umbau unberührt.

## 2026-09-21 — Technisch (Claude)

- `gemini-2.5-flash`/`-lite` sind für neue Keys abgeschaltet (404) → Alias `gemini-flash-latest`,
  Ausweich-Modell `gemini-flash-lite-latest`; Bericht weicht auch bei 500/503 aus.
- Gemini allein liefert Sprecherzahl und -zuordnung nicht stabil (gleiche Aufnahme: 3–4 Sprecher,
  wechselnde Zuordnung). Allans Pflicht-Anforderung (korrekte Personenzahl + Zuordnung per Stimme)
  wird über eine zusätzliche lokale akustische Stimmerkennung verfolgt; Gemini bleibt für Wortlaut + Bericht.

## 2026-09-22 — Ein Paply (von Allan bestätigt)

Nur noch ein Paply: installierte App, `~/Vibe/paply-main`, GitHub `main`. Alte Zweige, der zweite
Projektordner, die Codex-Test-App, alte Installationsdateien und die alte Web-Version im Repository-Hauptordner
werden entfernt. Beurteilung „wichtiger“ Zweige überließ Allan Claude: Codex-Unterlagen und Messprotokolle
ins Archiv übernommen; paply.dev-Planung (Feb. 2026) nach `~/Vibe/paply.dev/docs/` gerettet;
Windows-Signing-Fix vom Feb. 2026 ist überholt (Windows-Build läuft).

## 2026-10-21 — Abrunden + Weitergabe an Windows (von Allan bestätigt)

- Meeting-Modus „funktioniert sehr schlecht“ → ausgeblendet, als Beta in den Einstellungen zuschaltbar
  (Code und Meetings bleiben).
- Logo **B „p-Kopf“**, Aufnahme-Animation **„Echo“ mit Timer**, **veredelter Ton** (Allans Wahl aus drei
  Opus-5.5-Entwürfen).
- Der Windows-Freund holt sich einen eigenen kostenlosen Groq-Schlüssel (Ersteinrichtung führt hin).
- Release v1.14.0 veröffentlichen, sobald Tests und Opus-Review grün sind.
- Alle Änderungen gleichwertig für macOS und Windows.
- Diktat: Stille-Fix ausdrücklich gewünscht; übriger Diktat-Ablauf auf dem Mac bleibt gleich
  (gleiche Einfüge-Methode). Nicht umgesetzt, weil Verhalten ändernd: Zwischenablage nach dem Einfügen
  wiederherstellen; Schlüssel per Schlüsselbund verschlüsseln (unsignierte App → Passwortabfragen).


## 2026-10-26 — Notes bauen (von Allan bestätigt)

- Eine gemeinsame visuelle Gedankenablage, keine getrennten Notizbücher. Themenchips springen zu Bereichen auf derselben Fläche. Karte, freier Text, Haftnotiz, Mindmap, Vergleich und Ablauf je nach Inhalt.
- Konfigurierbares eigenes Aufnahme-Kürzel (Mac-Voreinstellung Cmd+Y) und Öffnen-Kürzel; eigenständige Mint-Gold-Pille in Paply CI. Diktatbedienung unverändert, minimale Vorrang-Haken sichern getrennte Aufnahmen.
- Offlinefähige Originale und manuelle Bearbeitung; KI erzeugt begrenzte Darstellungspläne ohne ausführbaren UI-Code oder recherchierte Inhalte. OpenUI rendert kontrollierte Paply-Bausteine, ReactFlow übernimmt Canvas-Interaktion.
- Bestehender Groq-Key; kurze Gedanken 20B, komplexere 120B, Whisper-Turbo für Audio, optionale gecachte Qwen-Bildbeschreibung. Lokale Budgets und eine serielle Queue, kein stündlicher autonomer Agent.
- Vor-/Nachreview durch Opus 5.5 Extra High und unabhängige QA, danach lokale Test-App. Ein öffentliches Release ist damit nicht beauftragt.

## 2026-10-26 — Notes veröffentlichen (von Allan bestätigt)

Nach dem MacBook-Test und der Y/Z-Korrektur in `1.15.0-notes.2`: „ok passt … kannst das ganze pushen, auf github etc und meine version updaten. ich werds testen.“ Damit sind Commit/Push auf `main`, Release-Tag `v1.15.0`, Veröffentlichung über den vorhandenen GitHub-Workflow und Aktualisierung der installierten MacBook-App beauftragt. Die vorhandenen Test-Notes werden zusätzlich ins normale Profil übernommen; bestehende Einstellungen, Diktatverlauf und Meetings bleiben erhalten.

## 2026-10-27 — Paply iOS V1: Rahmen (von Allan bestätigt)

Übernahme aus dem UX-Thread „Paply iOS – UX“ (26./27.10.2026). Native iPhone-App (Swift/SwiftUI) plus
Paply-Tastatur unter `ios/`, Branch `feat/ios-v1`. V1 kann nur Diktieren und Einsetzen; kein Notes-Canvas,
keine Recherche. Global gedacht, auch für Mehrsprachige. Vorgehen: Phase 0 Machbarkeit auf dem echten
iPhone, Phase 1 V1 bauen, Phase 2 TestFlight erst auf Allans Wunsch.

- **Apples Tastaturen bleiben unangetastet** (Sprachen, Autokorrektur, Tippgefühl). Eine eigene Taste in
  Apples Tastatur erlaubt iOS nicht; einen Nachbau der Apple-Tastatur hat Allan verworfen.
- **Paply ist eine schlanke Sprach-Tastatur in der 🌐-Liste.** 🌐 antippen startet die Aufnahme sofort,
  ohne extra Knopf; 🌐 halten bleibt Apples Liste. Wer nur durchschaltet, bekommt keine Aufnahme: still
  verwerfen, nichts senden oder speichern; Haptik erst bei echter Sprache.
- **Gleiche Höhe wie Apples Tastatur**, große grüne Fläche mit Wellenform und Zeit. Tipp irgendwo = fertig,
  nach links wischen = verwerfen.
- **Einsetzen** per `textDocumentProxy`, danach `advanceToNextInputMode()` zurück. Rückgängig über Apples
  Drei-Finger-Wisch (auf dem Gerät prüfen).
- **Sprache erkennt Paply selbst** (Deutsch, Englisch, gemischt), ohne Tastatursprache umzustellen.
- **Kein Live-Text**; der Text kommt am Ende auf einmal.
- **Sitzung:** Tastaturen haben kein Mikro, Aufnahmen starten nur im Vordergrund. Paply blitzt einmal nach
  Neustart kurz auf (ab iOS 26.4 wischt der Nutzer selbst zurück) und hält das Mikro danach bereit,
  Standard „bis Neustart“ (8 Std, 1 Std, 15 Min wählbar). Oben nur der orange Mikro-Punkt, kein
  dauerhaftes Paply-Symbol, keine Live Activity im Leerlauf.
- **Die App ist nur Einstellungen und Verlauf**, kein Aufnahme-Bildschirm. Verlauf: Liste, Antippen kopiert.
  Sitzung anzeigen, beenden, starten.
- **Einstellungen:** Groq-Schlüssel im Schlüsselbund; Sprache automatisch; Mikro bereit halten; „Eigene
  Begriffe“ (Whisper-`prompt` bis 224 Tokens und erlaubte Hörfehler-Korrekturen beim Polieren);
  Schnelltasten-Einrichtung je nach Gerät (Aktionstaste ab iPhone 15 Pro, sonst Rückseite, Kontrollzentrum
  für alle) über App Shortcuts und Control-Widget mit Sprung in die Einstellungen. Snippets vom Mac später.
- **Schnelltasten** starten und stoppen die Aufnahme; der Text wartet auf 🌐 oder liegt in der
  Zwischenablage. Ob das im Hintergrund geht, klärt Phase 0.
- **Bewusst nicht in V1:** automatisches Senden, Stopp bei Sprechpause, Sprachbefehle.
- **Qualität:** Groq Whisper `whisper-large-v3` als Standard (gegen `-turbo` messen), Apples
  SpeechAnalyzer nur als Offline-Ersatz. Immer leicht polieren wie am Mac (`qwen/qwen3.8-27b`, Ausweich
  `openai/gpt-oss-120b`), Prompt mehrsprachig („in der gesprochenen Sprache“), Sicherheitsnetz vom Mac
  portiert. **Kein Zeitlimit beim Polieren** („Tempo geht nicht vor Perfektion“); Rohtext nur bei echtem
  Fehler nach einem Neuversuch.
- **Tempo aus der Architektur:** Stücke schon beim Sprechen hochladen, Verbindung vorwärmen, 16 kHz mono,
  ~0,5 s Vorlauf nur im Speicher, winzige Tastatur ohne Netz, Arbeit in der App; Tastatur ↔ App über
  App Group und Darwin-Notifications.
- **Groq-Zugang:** V1 mit Allans eigenem Schlüssel in den Einstellungen; für globale Nutzer später ein
  Paply-Zugang über eigenen Server.

## 2026-10-27 — Paply iOS: „Gedanken“ als zweiter Weg (von Allan bestätigt)

Erweiterung von V1 (vorher „nur Diktat“), nachdem Phase 0 den Hauptweg 🌐 → Diktat → Text ins Feld auf
Allans iPhone bestätigt hat.

- **Zwei klare Wege:** 🌐 = Diktat (Text ins aktuelle Feld). Paply-Knopf auf Sperrbildschirm,
  im Kontrollzentrum, per Siri (Aktionstaste ab iPhone 15 Pro) = **Gedanke**.
- **Auslöser:** Ein Druck nimmt sofort auf, ohne Entsperren und ohne App, wie ein Diktiergerät. Oben bzw. auf
  dem Sperrbildschirm erscheint eine schöne Paply-Anzeige mit Zeit; Antippen öffnet die große Ansicht.
- **Beenden:** gleicher Knopf nochmal oder „Fertig“ in der Anzeige; kein Auto-Stopp.
- **KI (Groq-Schlüssel):** Titel und aufgeräumter Text (Original bleibt abrufbar), Themen automatisch,
  Aufgaben erkennen, verwandte Gedanken verbinden. Mit festem, kleinem Regelrahmen, damit es sich
  durchdacht anfühlt.
- **Gestaltung und Mac-Abgleich** überlässt Allan der Bauleitung: hochwertig, einfach, wenige Optionen,
  „wie eine Apple-App, die eine 10 von 10 ist“; nichts muss vom Mac übernommen werden.
- **Hardware-Tasten:** Laut/Leise und Seitentaste sind für Apps nicht belegbar, Rückseite-Tippen gefällt
  Allan nicht; Hauptersatz ist der Sperrbildschirm- bzw. Kontrollzentrum-Knopf.
- **Text aus der Schnelltaste:** Direkt ins Feld darf nur die gerade offene Tastatur einsetzen; ist Paply
  offen, wird eingesetzt, sonst Verlauf, Zwischenablage und Angebot beim nächsten 🌐.
