# Meeting-Modus v2 — Gemini-Audio-Auswertung, Nachhören, Bericht v2

**Datum:** 2026-09-21 · **Version:** 1.13.0 · **Status:** umgesetzt auf Branch `claude/funny-hypatia-86wimp`, wartet auf Praxistest auf Allans Mac

## Warum

Der bisherige Meeting-Modus (Groq-Whisper-Chunks live + Tonhöhen-Clustering in JS + „wer zuerst
spricht = Ich“) trennte reale Raumstimmen nicht und löschte das Audio nach dem Stop. Der lokale
Ansatz auf `codex/local-meeting-quality` (faster-whisper, MossFormer, pyannote, Ollama Qwen 27B)
brauchte 4 Minuten für 30 Sekunden Aufnahme und lieferte inkonsistente Sprecher und fehlerhafte
Berichte (siehe `docs/UEBERGABE-CLAUDE.md` auf jenem Branch).

Allans bestätigte Entscheidungen (21.09.2026): Gemini-Audio (kostenloses Free-Tier) statt lokaler
Modelle, Basis `main`, Audio 7 Tage behalten, neues Bericht-Layout direkt in der App. Diktat
unverändert.

## Ablauf

```
Cmd+Shift+X ─► MeetingController.start()
   Overlay (beim App-Start versteckt vorgeladen, AudioWorklet fertig) ─ getUserMedia ─► 16 kHz PCM
   audiotee (System-Audio, macOS)                                       ─► 16 kHz PCM
   Startlücke beider Spuren wird mit Stille aufgefüllt (Zeitachse = Sessionstart); Pill zeigt
   „startet …“ bis das erste Mikro-Paket da ist. Chunks (20–40 s, an Sprechpausen) = Absturzsicherung.
Cmd+Shift+X ─► stop() Phase 1 (schnell): Capture-Handshake (Restpuffer) → audio_mic.wav / audio_system.wav
   → Index status 'processing' → Overlay zu. Hotkey ist sofort wieder frei.
   Phase 2 (seriell, im Hintergrund): Fenster ≤ 25 min an Chunk-Grenzen → Gemini Flash (Alias `gemini-flash-latest`; 2.5 ist für neue Keys abgeschaltet) bekommt
   Spur A (Mikro) und ggf. Spur B (System, nur wenn Anruf erkannt / systemAudioMode) als Audio →
   JSON {sprecher, segmente} mit Zeitmarken → lokale Energieprüfung der Spurzuordnung, Echo-Dedupe →
   Labels „Sprecher 1..N“ / „Gegenstelle“ → transcript.json → Bericht v2 → status 'ready'
   → 'meetings:updated' ans Dashboard.
   Fallback ohne Gemini (kein Key / Kontingent / Fehler): Groq Whisper über die WAVs, ohne
   Sprechertrennung, Hinweis + „Neu auswerten“ in der App.
Aufbewahrung: audioExpiresAt = Stop + 7 Tage; Löschlauf beim App-Start, nach jeder Auswertung, täglich.
Wiederaufnahme: beim App-Start werden Meetings mit status 'recording'/'processing' aus Chunks/WAVs
   weiterverarbeitet (max. 3 Versuche).
```

## Module

| Datei | Aufgabe |
|---|---|
| `meeting/meeting-controller.js` | Phase 1/2, Warteschlange, `resumePending`, `reanalyze`, Retention-Aufruf |
| `meeting/gemini-audio.js` | Fensterplanung, Prompt + responseSchema, Files-API/inline, Retry, Spur-Korrektur, Labels |
| `meeting/gemini-files.js` | Resumable Upload / Delete (Files API) |
| `meeting/groq-fallback.js` | Whisper-Fallback ohne Sprecher (30-s-Fenster, Stille-Gate, Echo-Filter) |
| `meeting/summary.js` | Bericht v2 (titel, kurzfassung, themen, entscheidungen, offeneFragen, todos) |
| `meeting/audio-retention.js` | 7-Tage-Löschung |
| `meeting/llm-client.js` | Gemini zuerst, Groq als Fallback (Setting `llmProvider` erzwingt) |
| `src/lib/meeting-summary.ts` | Normalizer v1→v2, Markdown-Export |
| `src/apps/dashboard/views/MeetingDetail.tsx` | Bericht oben, Konversation mit ▶ ab Textstelle unten |
| `src/apps/meeting-overlay/MeetingOverlay.tsx` | Capture, Start-Stempel, Stop-Handshake |
| `scripts/meeting-analyze-wav.js` | Prüfwerkzeug: vorhandene WAV ohne App auswerten |

Entfernt: `meeting/diarize-local.js`, `meeting/diarize-refine.js`, Root-`meeting-controller.js`/
`transcript-merger.js` (tot), Setting „Sprecher trennen“, Live-Transkription während der Aufnahme.

## Grenzen (ehrlich)

- Audio geht an Google. Free-Tier-Daten können von Google zur Produktverbesserung genutzt werden.
- Free-Tier-Limits (Stand Erinnerung, nicht live geprüft): ~10 Anfragen/Min, ~250/Tag, 250k Tokens/Min.
  Audio kostet ~32 Tokens/s; zwei 25-min-Spuren ≈ 96k Tokens je Aufruf. Fenster laufen nacheinander.
- Zeitmarken von Gemini sind ±1–2 s genau; Sprecher-IDs über Fenstergrenzen werden per Legende
  weitergegeben, nicht akustisch verifiziert.
- Kein automatisches „Ich“: Allan benennt sich um (bleibt grün).
- Nicht in dieser Umgebung getestet: echte Mac-App, Mikrofon/Systemaudio, echte Gemini-Antworten.
  Alle Netzpfade sind mit Fake-Antworten getestet (140 Tests).

## Praxistest auf dem Mac

```sh
cd electron-menubar
npm ci
npm run compile:bin          # audiotee, Call-Detector, Globe-Listener
npm run dev:test             # eigener Datenordner ~/.paply-test, installierte App bleibt unberührt
```
In den Einstellungen Groq-Key und Gemini-Key (kostenlos: https://aistudio.google.com/apikey) eintragen. Dann:

1. Cmd+Shift+X → mit 2–3 Personen 1–2 Minuten reden → Cmd+Shift+X. Pill zeigt zuerst „startet …“,
   dann grün. Dashboard → Meetings: „wird ausgewertet …“, danach Bericht + Konversation mit mehreren
   Sprechern; ▶ vor einer Zeile spielt die Stelle.
2. Anruf über den Mac (FaceTime/WhatsApp/Teams): „Anruf“ in der Pill, Gegenstelle als eigener Sprecher.
3. Gemini-Key entfernen → Aufnahme → Hinweis „ohne Sprechertrennung“; Key eintragen → „Neu auswerten“.
4. Diktat (Cmd+X) unverändert.

Schnellprüfung der Gemini-Anbindung ohne App, mit einer vorhandenen Aufnahme (16 kHz mono 16 bit):
```sh
GEMINI_API_KEY=… node scripts/meeting-analyze-wav.js audio_mic.wav [audio_system.wav] --report
```
Erst nach bestandenem Praxistest: `npm run build` und DMG installieren.
