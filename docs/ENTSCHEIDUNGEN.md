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
