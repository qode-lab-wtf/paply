# Paply — Projektregeln

Wegweiser: `docs/instinct/START.md`. Kanonischer Stand: `docs/STAND.md`. Entscheidungen: `docs/ENTSCHEIDUNGEN.md`.

- Es gibt genau ein Paply: dieses Repository, Branch `main`. Apps: `electron-menubar/` (Mac, Windows), `ios/`, `android/`. `paply.dev` ist ein anderes Produkt.
- Verhalten steht in `REGELN.md` und gilt für alle Apps. Änderungen dort beginnen, dann `node shared/regeln-pruefen.mjs`.
- Neue Funktion oder Änderung: zuerst klären, ob sie für alle Apps oder nur für eine gilt. Nur eine App: Die übrigen kommen unter „Nachzureichen“ in `docs/STAND.md`, damit der Gesamtstand sichtbar bleibt.
- Für jede Aufgabe ein kurzer Branch von `main`, nach dem Merge löschen. Keine langlebigen Plattform-Branches.
- Diktat (Cmd+X) nicht anfassen, ohne dass Allan es ausdrücklich will.
- Keine Keys ins Repository; Keys kommen in die App-Einstellungen.
- Release Mac/Windows: Tag `v*` pushen (siehe `docs/RELEASE.md`); Version in `electron-menubar/package.json` muss passen. iOS: `ios/docs/TESTFLIGHT.md`. Android: `android/docs/RELEASE.md`.
- Test-App: `npm run dev:test` startet mit leerem Datenordner `~/.paply-test` — Allan vorher sagen, dass sie leer aussieht.
