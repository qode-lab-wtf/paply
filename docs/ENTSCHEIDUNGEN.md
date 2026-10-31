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

## 2026-10-27 — Paply iOS: nur Transkripte, Themen gehen mit, Widget unter der Uhr (von Allan bestätigt)

Nach Allans Gerätetest.

- **Kein Ton behalten:** „Ich will nichts mit Audiospuren, ich will einfach nur Transkripte haben … verbraucht
  zu viel Platz.“ Die Aufnahme lebt nur, bis der Rohtext dauerhaft gespeichert ist, dann wird sie gelöscht.
  Ohne Rohtext (offline, ohne Schlüssel, Fehler) bleibt sie für den Neuversuch. Keine AAC-Umwandlung, kein
  Player; „Original“ zeigt nur den Rohtext. Vorhandene Aufnahmen mit Rohtext räumt die App beim Start weg.
- **Themen gehen mit ihren Gedanken:** Endgültig gelöschte Gedanken nehmen ihr Thema mit, sobald kein Gedanke
  (auch nicht im Papierkorb) mehr daran hängt – auch Nutzer-Themen. Ein von Hand angelegtes, noch leeres Thema
  bleibt. Themen, deren Gedanken alle im Papierkorb liegen, erscheinen nicht als Chip.
- **Widget „Paply-Gedanke“ unter der Uhr** (wie ChatGPT/Claude): Tippen nimmt wie das Steuerelement auf,
  nochmal tippen beendet; Einrichtungshilfe laienfest.

## 2026-10-27 — Paply iOS: Landkarte als Startseite, Aufgaben-Reiter, Themenbilder (von Allan gewählt, auf `feat/ios-v1`)

- **Landkarte als Startseite:** Der Reiter „Gedanken“ öffnet eine Landkarte der Themen – feste Plätze, gemerkte
  Anker, Fokus-Zoom, Linien nur für echte Verknüpfungen; ein Themen-Panel zeigt offene Aufgaben und die Gedanken des
  Themas.
- **Aufgaben als eigener Reiter:** Die Leiste lautet Gedanken | Aufgaben | Diktat. Alle Aufgaben aus allen Gedanken
  stehen auf einer Seite (Überfällig · Heute · Demnächst · Irgendwann · Erledigt). Das ersetzt den Chip „Aufgaben“
  und die Regel „Aufgaben sind kein Tab“ (`ios/docs/gedanken/KONZEPT.md` §2, §3.3); Paply bleibt kein
  Aufgabenmanager.
- **Themenbilder:** Ein Thema kann statt des Symbols ein eigenes Bild tragen (quadratisch, höchstens 512 px, JPEG
  ohne Metadaten). Die Bilder bleiben auf dem Gerät und gehen nie an die KI oder ins Netz.

## 2026-10-28 — Paply Android V1: Rahmen (von Allan bestätigt)

- **Ziel:** Paply Android mit gleicher Qualität, gleichem Design und gleicher UX wie Paply iOS V1, als APK-Testversion
  für Freunde. Kotlin und Jetpack Compose, nativ, Ordner `android/`, Branch `feat/android-v1`.
- **Arbeitsteilung:** Claude plant, entscheidet und prüft mit. Codex baut: astra die Kernteile, 6.1-sol die Routine.
  Sonnet reviewt.
- **Rechner:** Android-Werkzeuge und Emulator liegen nur auf dem MacBook (`~/Android`), weil der Mac mini zu wenig Platz
  hat.
- **Diktat-Einstieg:** Paply ist eine reine Sprach-Tastatur. Der Wechsel läuft über die System-Tastaturtaste unten
  rechts. Auf Pixel mit Android 16/17 reicht dafür ein Tipp, Gboard und die Samsung-Tastatur bleiben unangetastet.
  Einen **schwebenden Paply-Knopf** (Overlay plus Bedienungshilfe, wie bei Wispr Flow) gibt es bewusst nicht. Allan:
  „keine Lösung, die nur teilweise funktioniert“, denn in manchen Apps ließe sich der Text nicht einsetzen und das
  Einrichten wäre fummelig. Einen Knopf direkt in Gboard oder der Samsung-Tastatur erlaubt Android nicht.

## 2026-10-29 — Paply Android: Konto bzw. Abgleich später (von Allan bestätigt)

Ein Konto, mit dem man sich von mehreren Geräten anmeldet und Transkripte vom Handy auch am Laptop sieht, ist der nächste
große Schritt. Er kommt aber **später**. Erst müssen die einzelnen Geräte solide laufen. Bis dahin bleiben alle Daten nur
auf dem jeweiligen Gerät.

## 2026-10-29 — Paply Android: Ein-Tipp-Diktat über einen Paply-Knopf (von Allan entschieden)

Echte Tester (Samsung, Xiaomi Android 11) fanden den Tastaturwechsel zu umständlich. Allan: Es „muss nativer wie bei
iPhone laufen … 1 Klick …, reinreden, 1 Klick stopp fertig … und dann kommt meine alte Tastatur … wenn nicht Icon World
oder Tastatur, dann eben ein Paply-Icon“.

Entscheidung:
- Ein **Paply-Knopf neben der normalen Tastatur**, wie bei Wispr Flow, über eine Bedienungshilfe.
- Ablauf: 1 Tipp zum Aufnehmen, 1 Tipp für fertig, der Text kommt ins Feld. Die eigene Tastatur bleibt.
- Die Paply-Tastatur bleibt als zweiter Weg erhalten.
- Das ersetzt die Entscheidung „kein schwebender Knopf“ vom 28.10.
- Bekannte Grenzen:
  - Einmalig muss man die Bedienungshilfe einschalten, bei der Testdatei vorher „Eingeschränkte Einstellungen
    zulassen“.
  - In Apps mit eigenen bzw. geschützten Eingabefeldern landet der Text in der Zwischenablage.
- Zusätzlich: Hinweise und Karten blenden sich nach wenigen Sekunden von selbst aus („smooth und clean, wie bei Apple“).

## 2026-10-30 — Ein Repository, `main` als einzige Wahrheit

Allans Auftrag: zentralisieren, einfach halten, Verhalten an einer Stelle festlegen.

- Mac/Windows, iOS und Android bleiben ein Repository und liegen auf `main`. Keine getrennten Projekte, weil sich die
  Apps Regeln, KI-Texte und Prüffälle teilen.
- Kein gemeinsamer App-Code über Swift, Kotlin und JavaScript hinweg. Gemeinsam sind `REGELN.md`, `shared/` und der
  Wächter `shared/regeln-pruefen.mjs`, der jede Abweichung meldet.
- Der Zusammenschluss ändert keine App. Abweichungen stehen als Ausnahmen in `REGELN.md`, bis Allan sie entscheidet.
- Für jede Aufgabe ein kurzer Branch von `main`, keine langlebigen Plattform-Branches.

## 2026-10-31 — Sprache: erkennen lassen, Gegenprobe statt Vorgabe (von Allan beauftragt)

Allan will fremde Sprache immer ausgeschrieben, nie übersetzt. Die Übersetzung entstand, weil kurze Stücke mit fester
Sprache rausgingen und fremde Sprachen neu in der Hauptsprache geschrieben wurden. Künftig erkennt Whisper immer selbst.
Weicht die Erkennung bei kurzen Stücken oder außerhalb der eigenen Sprachen ab, entscheidet eine Gegenprobe über die
Konfidenz. Messung und Regel: `REGELN.md`, Abschnitt 1.

Am selben Tag entschieden: Regel 1, `large-v3` und die lange Stille-Liste gelten auch auf Mac und Windows. Polieren ist
überall an, der Schalter wandert in einen Entwicklerbereich, den jede App bekommt. Ton bleibt nur bis zum gesicherten
Text, Nachhören entfällt. Das ersetzt „Originalton 7 Tage“ von 2026-09-21. Die Historie vor dem Merge wurde von
Tester-Namen, einem privaten Vorfall und dem TestFlight-Link bereinigt.

Ebenfalls am 31.10.: Gedanken auf Mac und Windows nutzen dieselben KI-Regeln wie iPhone und Android. Eigene Begriffe
bekommen eine akustische Gegenprobe statt einer Korrektur durch die KI, das war Allans Vorschlag. Der Code soll privat
werden, die Downloads ziehen dafür in ein eigenes öffentliches Repository um. Android-Gespräche warten auf den
bestandenen Gerätetest des iPhones.
