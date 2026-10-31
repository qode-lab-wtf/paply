# paply — Diktat, Gedanken und Gespräche

Für Mac, Windows, iPhone und Android.

Mac und Windows: **Cmd+X** diktieren (Groq Whisper, behutsames Polieren; abschaltbar im Entwicklerbereich), **Cmd+Y** Gedanken,
**Cmd+Shift+X** Gespräch aufnehmen → Gemini-Audio-Auswertung mit Sprechern, Wortlaut, Bericht. Ton wird nach der Auswertung gelöscht; bei Fehlern bleibt er höchstens 30 Tage für den Neuversuch.

## Download

Aktuelle Version: https://github.com/qode-lab-wtf/paply/releases/latest
(Apple Silicon: `paply-<version>-arm64.dmg`). Die App ist nicht signiert — beim ersten Start
Rechtsklick → Öffnen. Installierte Apps aktualisieren sich danach selbst.

## Projektaufbau

- `electron-menubar/` — Mac und Windows (Electron, React/Vite, Tests mit Vitest)
- `ios/` — iPhone (Swift), `android/` — Android (Kotlin)
- `REGELN.md` — Verhalten aller Apps, `shared/` — gemeinsame KI-Texte, Prüffälle und der Regel-Wächter
- `docs/STAND.md` — kanonischer Stand · `docs/ENTSCHEIDUNGEN.md` · `docs/instinct/` — Wegweiser und Zielnotiz
- `docs/RELEASE.md` — Release Mac und Windows (Tag `v*` → GitHub Action baut beide)
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
