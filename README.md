# paply — Diktat und Gesprächsaufnahme für den Mac

Menüleisten-App: **Cmd+X** diktieren (Groq Whisper, optional Groq-Llama-Polishing),
**Cmd+Shift+X** Gespräch aufnehmen → Gemini-Audio-Auswertung mit Sprechern, Wortlaut, Bericht und
Nachhören (Original-Ton 7 Tage). Windows-Build vorhanden.

## Download

Aktuelle Version: https://github.com/qode-lab-wtf/paply/releases/latest
(Apple Silicon: `paply-<version>-arm64.dmg`). Die App ist nicht signiert — beim ersten Start
Rechtsklick → Öffnen. Installierte Apps aktualisieren sich danach selbst.

## Projektaufbau

- `electron-menubar/` — die App (Electron, React/Vite, Tests mit Vitest)
- `docs/STAND.md` — kanonischer Stand · `docs/ENTSCHEIDUNGEN.md` · `docs/instinct/` — Wegweiser und Zielnotiz
- `docs/RELEASE.md` — Release auslösen (Tag `v*` → GitHub Action baut Mac + Windows)
- `docs/archiv/` — Historie, keine Wahrheit
- Meeting-Architektur: `electron-menubar/docs/superpowers/specs/2026-09-21-meeting-gemini-audio-design.md`

## Entwickeln

```bash
cd electron-menubar
npm ci
npm run compile:bin      # macOS: audiotee, Call-Detector, Globe-Listener (Swift)
npm run dev              # App mit normalem Datenordner
npm run dev:test         # App mit eigenem, leerem Datenordner ~/.paply-test (installierte App bleibt unberührt)
npm test
```

Keys (Groq, Gemini) werden in den Einstellungen der App eingetragen, nie im Repository.
