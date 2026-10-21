# Paply — Stand

**Zeitpunkt:** 21.10.2026, nachmittags · **Phase:** Betrieb v1.14.0 (veröffentlicht: https://github.com/qode-lab-wtf/paply/releases/tag/v1.14.0)

## v1.14.0 — Abrunden für Mac + Windows (21.10.2026)

Allans Auftrag: App abrunden, Fehler raus, schneller, schöneres Design (Logo, Aufnahme-Animation),
Weitergabe an einen Freund mit Windows; alles gleichwertig für macOS und Windows.

- **Stille statt „Vielen Dank“:** Groq Whisper liefert bei Stille „Vielen Dank.“ (`no_speech_prob` ist bei
  Groq immer 0). Pegelmessung während der Aufnahme relativ zum Grundrauschen; ohne Sprache wird Groq gar
  nicht gefragt, typische Stille-Phrasen werden bei kaum Sprachaktivität verworfen. Echt diktiertes
  „Vielen Dank“ bleibt. Durchlauf-Test mit echten Groq-Aufrufen (Stille, Rauschen −50/−40 dB, Klick,
  laut/leise gesprochen, Satz) bestanden.
- **Meeting-Modus (Cmd+Shift+X) ausgeblendet:** standardmäßig aus, in den Einstellungen als „Beta“
  einschaltbar; Meetings und 7-Tage-Löschung bleiben.
- **Ersteinrichtung** für neue Nutzer (Groq-Schlüssel mit Prüfung, Mikrofon, Bedienungshilfen, Kürzel).
  Anleitung zum Weitergeben: `docs/WINDOWS-INSTALLATION.md`.
- **Robustheit Diktat:** Start/Stop-Rennen, Mikrofonfehler, parallele Diktate (Ziel-App pro Diktat),
  Einfüge-Fehler → „In Zwischenablage kopiert“, Polish schneidet nicht mehr ab, transaktionaler
  Kürzel-Wechsel, Single-Instance, keine Diktat-Texte im Log, Backups ≤ 24 h. Windows: Einfügen ins
  Ausgangsfenster + schneller (langlebiger Fokus-Helfer, Ctrl+V über uiohook).
- **Absturz behoben (schon in v1.13.1):** Ohne Bedienungshilfen-Recht brach uiohook die App auf dem Mac
  ab — betraf jeden neuen Mac-Nutzer beim ersten Start.
- **Tempo:** Aufnahme startet ohne Warten auf die Ziel-App-Ermittlung (Test: 20–80 ms statt ~250 ms);
  keine Google-Fonts mehr (Systemschrift).
- **Design:** Logo „p-Kopf“ (Opus-5.5-Entwurf B, von Allan gewählt), neue Icons für Dock/Menüleiste/
  Windows-Tray/Installer, Aufnahme-Pille „Echo“ mit Zeitanzeige, veredelter Start-/Stopp-Ton,
  Markenfarben.
- **Geprüft:** 451 automatische Tests grün; drei Opus-5.5-Reviews (Diktat-Kern, Integration, Gegenprüfung der
  Fixes) — Befunde behoben; echter Durchlauf in der Test-App (Fake-Mikrofon-WAVs + echtes Groq) für Stille,
  Rauschen, Klick, kurze Wörter („Danke.“, „Tschüss.“), „Vielen Dank“ laut/leise/Café und ganze Sätze;
  gepacktes Mac-App-Bundle gestartet und diktiert; CI-Builds Mac + Windows grün.
- **Behoben aus Reviews u. a.:** Windows-Auto-Update (Installer-Name passte nicht zu `latest.yml`, seit
  v1.13.1 kaputt), Test-App startete nicht neben installierter App, Agent-Wechsel während des Diktats,
  Kürzel-Erfassung mit ⌥ auf dem Mac (seit v1.13.1) und QWERTZ unter Windows, Backups/Wiederholen.
- Je Diktat stehen Pegel-Kennzahlen (`level`: speechMs/peak/floor, kein Inhalt) in der Historie — zum
  Nachjustieren des Stille-Filters, falls bei Allan im echten Raum doch ein „Vielen Dank“ durchrutscht.
- Bekannte Restpunkte: Fokus-Helfer unter Windows nur per Code/Tests geprüft (Praxistest beim Freund);
  bei Gruppenrichtlinie „AllSigned“ fügt Windows ohne Fokus-Wiederherstellung ein.

## Offen / braucht Allan

- Praxistest v1.14.0 auf dem MacBook und Rückmeldung des Windows-Freunds (Einfügen, Tray, Pille).
- MacBook geprüft (21.10.2026, per `ssh macbook`, Benutzer `allanha`): dort liegt kein Paply-Repository
  (nur `~/Vibe/paply.dev`, anderes Produkt) → keine ungepushten Stände. App dort auf v1.14.0 aktualisiert,
  Einstellungen/Historie/Meetings erhalten.
- Stimmerkennung im Meeting-Modus (siehe unten) ruht, solange der Modus Beta ist.

---

## Stand 22.09.2026 (v1.13.1)

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
- Praxistest v1.13.0 in der Alltags-App (22.09.2026, Allan, 2 Personen, 2 Aufnahmen): Gemini gab beide Male
  HTTP 503 (überlastet, alle -latest-Modelle), die App fiel auf Groq Whisper zurück → 1 Sprecher, schlechterer Wortlaut.
  **v1.13.1:** bei 5xx/429 wechselt Auswertung und Bericht auf `gemini-3.6-flash` → `gemini-3.5-flash`; kürzere
  Wartezeiten je Modell. Nachgeprüft an Allans Aufnahme 1790089914117-192z9h: 2 Sprecher (richtig), Wortlaut gut,
  Bericht über gemini-3.6-flash. Auto-Update in der App scheitert bei unsignierter App (bekannt) → DMG + `xattr -cr`.

## In Arbeit

Lokale akustische Stimmerkennung als Vorgabe für Gemini (Versuch: sherpa-onnx + pyannote-Segmentierung +
wespeaker-resnet34; bei Schwelle 0,7 drei Stimmen, aber stark schwellenabhängig). Es fehlt eine Aufnahme
mit bekannter Wahrheit: nächste Mehrpersonen-Aufnahme mit Namensansage („Ich bin …“) und/oder gelabelte
Forschungsaufnahmen (Download-Freigabe von Allan offen).

### Offen (Stand 22.09.)

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
