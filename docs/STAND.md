# Paply — Stand

**Zeitpunkt:** 22.09.2026, früh · **Phase:** Betrieb (v1.13.0 veröffentlicht) + Entwicklung (Stimmerkennung)

## Bestätigtes Ziel

Siehe `docs/instinct/ZIEL.md`. Kurz: Diktat (Cmd+X) bleibt unverändert; Meeting per Cmd+Shift+X ohne
Konfiguration starten/stoppen, danach verständlicher Bericht mit Todos und darunter die Konversation;
kostenloser Betrieb. **Pflicht (Allan, 21.09.2026):** korrekte Personenzahl und korrekte Zuordnung
per Stimmerkennung.

## Was gilt

- **v1.13.0** ist auf GitHub veröffentlicht (Mac arm64/universal, Windows) — Build 35660413738 grün,
  Release mit DMG/ZIP/EXE und Auto-Update-Dateien. Allans installierte App holt das Update selbst.
- Meeting-Modus v2: Gemini-Audio (Alias `gemini-flash-latest`, Ausweich `gemini-flash-lite-latest`),
  Bericht v2, Nachhören ab Textstelle, Audio 7 Tage, Groq-Whisper-Fallback ohne Sprecher.
- Prüfung 21.09.2026 (Allans Mac, echte 3-Personen-Aufnahme, `scripts/meeting-analyze-wav.js`):
  Wortlaut gut, Bericht inhaltlich richtig; Sprecherzahl schwankt (3–4), Zuordnung wechselt zwischen
  Durchläufen. 140 automatische Tests grün.
- Praxistest in der Alltags-App (Cmd+X, Cmd+Shift+X) steht bei Allan aus.

## In Arbeit

Lokale akustische Stimmerkennung als Vorgabe für Gemini (Versuch: sherpa-onnx + pyannote-Segmentierung +
wespeaker-resnet34; bei Schwelle 0,7 drei Stimmen, aber stark schwellenabhängig). Es fehlt eine Aufnahme
mit bekannter Wahrheit: nächste Mehrpersonen-Aufnahme mit Namensansage („Ich bin …“) und/oder gelabelte
Forschungsaufnahmen (Download-Freigabe von Allan offen).

## Offen / braucht Allan

- Praxistest v1.13.0 in der Alltags-App und Rückmeldung.
- „ok“ für den Download gelabelter Übungsaufnahmen (Stimmerkennung).
- Papierkorb leeren (`Paply_Codex_aufraeumen_2026-09-22`, `Paply_aufraeumen_2026-09-22`, ~44 GB).
- Nach Abschluss der Stimmerkennung: `~/.paply-test/` (gesicherte Testaufnahmen) entfernen.

## Aufräumen 22.09.2026 (ein Paply)

Entfernt: zweiter Projektordner `~/Vibe/paply-local-meetings` (Codex, 40 GB), Codex-Test-App + 27-GB-Modelle +
LaunchAgent, alte DMGs (Projekt `dist/`, Downloads), alte Web-Version (Next.js) im Repository-Hauptordner,
Zweige `codex/local-meeting-quality`, `claude/funny-hypatia-86wimp` (in main), `feature/meeting-recorder`,
`fix/meeting-mic-quality`, `claude/add-issue-creation-KPFtg` (paply.dev-Planung → `~/Vibe/paply.dev/docs/`),
`claude/evaluate-polishing-models-2MXQA` (überholter Windows-Signing-Fix). Codex-Unterlagen und
Messprotokolle liegen in `docs/archiv/codex-lokalversuch-2026-09-21/`.
