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
