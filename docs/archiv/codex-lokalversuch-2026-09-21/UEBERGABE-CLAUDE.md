# Paply — Übergabe an Claude

Stand: 21.09.2026. Dies ist eine Übergabe-Momentaufnahme; der weiter zu pflegende Projektstand bleibt `docs/STAND.md`.

## 1. Ergebnis vorweg

**Der Meeting-Modus ist nicht zuverlässig und nicht produktionsreif.** Technische Grundlagen wurden verbessert, aber die entscheidende Qualität bei realen Raumgesprächen wurde nicht erreicht. Eine eingebaute Audioaufbereitung verschlechtert eine der neuen Aufnahmen nachweislich. Allan erlebt schlechte Transkription, nur einen sichtbaren Sprecher trotz drei Personen, lange Verarbeitung und eine kryptische Ausgabe. Das ist kein bestandener Produktumbau.

**Die normale Diktierfunktion funktioniert für Allan gut und soll erhalten bleiben.** Die installierte normale App wurde nicht ersetzt. Die letzten beiden Untersuchungen haben nur Befunde und Prüfwerkzeuge ergänzt: Ihre vorgeschlagenen Korrekturen sind noch NICHT in der Test-App umgesetzt.

## 2. Allans bestätigtes Ziel / Auftrag an Claude

Allan möchte Claude mit dem von ihm genannten Modell „Fable 5.1“ ausprobieren. Diese Modellbezeichnung/Verfügbarkeit ist nicht geprüft; sie ist keine Vorgabe für Paplys Laufzeitmodelle.

Radikale Änderungen am Meeting-Modus sind ausdrücklich erwünscht, wenn sie das Ziel erreichen. Bestehende Architektur und Modellwahl sind keine Schutzgüter. Die Grenzen bleiben: kostenloser stabiler Betrieb, keine laufenden API-Kosten/Abos/Testguthaben-Abhängigkeit, bevorzugt lokal auf M5 mit 32 GB, funktionierendes Diktat unangetastet.

Gewünschter Alltag:
1. Shortcut drücken: Aufnahme beginnt zuverlässig, ohne Teilnehmerzahl, Namen oder technische Einstellungen.
2. Mit mehreren Personen reden: im Raum, über beliebige Telefon-/Konferenz-App oder beides gleichzeitig. Mikrofon und Systemaudio müssen erfasst werden.
3. Shortcut erneut drücken: Aufnahme endet, gespeicherte Daten bleiben auch bei Verarbeitungsfehlern erhalten.
4. Danach ein verständlicher, schön aufgebauter Bericht: kurze Orientierung, je nach Gespräch ausführliche Themen und Standpunkte, klare Entscheidungen/offene Fragen und am Ende passende Todos. Keine erfundenen Zuständigkeiten oder Beschlüsse.
5. Darunter die vollständige Konversation in gesprochenem Wortlaut, mit neutralen Sprechern, Zeitmarken und Nachhören. Keine „Politur“, die Inhalte umformuliert. Automatisch erkannter Text ist keine garantierte wortgetreue Referenz; Unsicherheit muss verständlich bleiben.

Berichtslänge muss dem Gespräch folgen. Tabellen/Grafiken nur bei Nutzen. Bericht, erkanntes Gespräch und Originalaudio müssen klar unterscheidbar sein. Größere visuelle Änderungen zunächst als Vorschau abstimmen; nicht wieder technische Prüfdetails zur Hauptoberfläche machen.

Allan will nicht wiederholt neue Tests aufnehmen oder selbst Namen/Sprecherstellen beschriften. Vorhandene Aufnahmen zuerst nutzen. Automatische Konsistenzprüfungen sind möglich; sie ersetzen keine unabhängige Referenz für Prozentangaben zur Genauigkeit.

## 3. Welcher Ordner und welcher GitHub-Stand?

**Auf diesem Mac in `/Users/allanha/Vibe/paply-local-meetings` arbeiten.** Das ist der aktuelle isolierte Entwicklungs-Worktree, Branch `codex/local-meeting-quality`.

- Repository: https://github.com/qode-lab-wtf/paply
- Arbeitsbranch: https://github.com/qode-lab-wtf/paply/tree/codex/local-meeting-quality
- Draft-PR: https://github.com/qode-lab-wtf/paply/pull/7 — keine Produktionsfreigabe.
- Vor dieser Dokumentübergabe frisch geprüft: lokaler HEAD und Remote-Arbeitsbranch identisch bei `11878331c7d3674181c3f898674f9737e12034a7`.
- `/Users/allanha/Vibe/paply-main` ist der ältere saubere `main`-Checkout bei `736f5aa95dafe5a2bac48752dfc56c3f79936202`; GitHub main steht ebenfalls dort. **Nicht dort versehentlich neu anfangen oder nur main herunterladen.**
- Diese Übergabe wird anschließend auf den Arbeitsbranch gepusht. Aktuellen HEAD bei Arbeitsbeginn erneut prüfen.
- GitHub enthält Code, Plan und anonymisierte Belege. **Private Audios, Transkripte, Modelle und Laufzeiten sind nur lokal vorhanden.** Ein reiner Cloud-Checkout kann die realen Vergleiche nicht unmittelbar wiederholen.

Zuerst lesen: `AGENTS.md`, `CLAUDE.md`, `docs/instinct/START.md`, diese Übergabe, `docs/STAND.md`, `docs/PLAN.md`, `docs/ENTSCHEIDUNGEN.md`.

## 4. Was tatsächlich läuft

- Normale App: `/Applications/paply.app`, v1.12.5; nicht ersetzt, Diktat erhalten.
- Separate Test-App: `/Users/allanha/Documents/Codex/2026-09-21/hi-x20/outputs/paply-test-build/mac-arm64/Paply Meeting Test.app`.
- Testfenster: „Paply Gespräch – TESTVERSION“, Dock-Badge TEST; eigene App-ID `com.paply.meeting.localtest`, eigene Daten. Zwei verschiedene Dock-Symbole waren normale App plus Test-App.
- Meeting-Shortcut der Test-App: **Command + Option + Shift + X**, Start/Stop.
- Testdaten: `/Users/allanha/Library/Application Support/Paply Gespräch Test`.
- Installierter Test-Build basiert auf `0d98a5245f37a4a6d2c4e1bb6e63e420da52eb86`. Spätere Commits `68b3342` und `1187833` ergänzen Diagnose/Belege, keine neue App.
- Aktive Pipeline: faster-whisper Large v3 CPU/int8/Beam 5 auf Originalaudio → MossFormerGAN nur für Mikrofon-Sprecheranalyse → pyannote Community-1 auf MPS → lokaler Qwen3.8-27B-Berichtsentwurf mit Aussagenprüfung.
- **Der problematische MossFormer-Standard ist weiterhin aktiv.** Rücknahme wurde empfohlen, noch nicht umgesetzt. Auch Aufnahme-Startverzögerung und kurze Sprecherwechsel sind noch nicht korrigiert.

## 5. Soll und Ist

| Bereich | Soll | Belegter Ist-Zustand |
|---|---|---|
| Diktat | Bestehendes Verhalten erhalten | Normale App unverändert; Allan zufrieden |
| Sofortaufnahme | Ab Shortcut zuverlässig erfassen | Im 30-s-Test Mikrofon erst 3,993 s nach Startzeitpunkt; keine Warnung |
| Wortlaut | Alle verständlichen Beiträge | Frühere ASR ließ im 106-s-Test etwa 11–52 s aus; neue ASR liefert mehr Wörter, Genauigkeit ungeprüft |
| Sprecher | Automatisch mehrere Stimmen stabil trennen | Drei Personen gemeldet; Verfahren widersprechen sich, aktueller kurzer Test zeigt nur eine eindeutig zugeordnete Stimme |
| Zusammenführung | Kein erkannter Beitrag verloren | Erkannter Text und Reihenfolge in bisherigen Erhaltungstests vollständig erhalten; das beweist keine vollständige Erkennung |
| Bericht | Verständlich, angemessen ausführlich, faktentreu | Experimenteller Entwurf; Bedeutungs-/Rollenfehler trotz Selbstprüfung, UI kryptisch |
| Wartezeit | Alltagstauglich, Status verständlich | 30-s-Test: zugeordnetes Transkript nach 83,1 s, Bericht nach 246,9 s ab Stop; kein verlässlicher Ein-Stunden-Wert |
| Raum/Telefon/Hybrid | Alles zuverlässig | Neue Problemtests nur Raum; ihre Systemspuren digital still. Keine Abnahme von echten Telefon-/Mischsituationen |
| Robustheit | Wiederaufnahme, Export, Aufbewahrung | Mehrere technische Tests bestanden; neue lange Aufnahme und echter Gerätewechsel noch offen |

## 6. Wichtigste reproduzierbare Aufnahmen

Basisordner: `/Users/allanha/Library/Application Support/Paply Gespräch Test/meetings`.
Keine privaten Gesprächsinhalte in Git übernehmen. Nicht vor der bestehenden Löschfrist unbemerkt Kopien außerhalb der Sitzung anlegen.

### A: 106 Sekunden, drei Personen, unterschiedliche Abstände

Sitzung `1790000094067-7l7njk`, 21.09.2026 16:14:54. Mikrofon 106,237 s, Offset 0,101 s; System 106,2 s, digital still. Kein Clipping, Mikrofon-RMS etwa −39,6 dBFS. Allan direkt am Mac, zweite Person weiter weg, dritte noch weiter. Hörverständlichkeit nicht unabhängig bestätigt.

- Frühere MLX-Whisper-Ausgabe: 128 Wörter, etwa 11–52 s weitgehend ausgelassen trotz modellseitig erkannter Sprache.
- faster-whisper auf Original: 203 Wörter, zusätzliche Passage teilweise erkannt. Mehr Wörter bedeutet nicht automatisch weniger Fehler.
- Community-1 auf Original: zwei Gruppen; mit MossFormer: drei. Identitätsrichtigkeit nicht belegt.
- Nach Wortzuordnung unklar: 37 Wörter mit Original-Diarisierung, 43 mit Aufbereitung. Drei Labels allein sind kein Erfolg.
- Installierte experimentelle Ausgabe hat drei Sprecherlabels und einen lokalen Berichtsentwurf.

### B: 30 Sekunden, erneuter Drei-Personen-Test

Sitzung `1790005145787-pij2iq`, 21.09.2026 17:39:05. Mikrofon 30,128 s, Startoffset 3,993 s; Aufnahmeuhr 34,159 s. System 31,4 s, Offset 2,707 s, digital still. Mikrofon-RMS etwa −41,99 dBFS, Peak 0,08554, kein Clipping.

- Original-Community-1: drei Gruppen, allen drei wird Text zugeordnet.
- Aufbereitung + Community-1: nur zwei Gruppen; die zweite liegt ausschließlich in modellseitig überlappenden Bereichen. Konservative Wortzuordnung zeigt nur eine eindeutige Stimme, andere Stellen bleiben unklar.
- **Konkreter Rückschritt durch pauschale Aufbereitung.** Gegenläufig zu Aufnahme A.
- faster-whisper: 80 Wörter; keine bestätigte Wortreferenz.
- Ab Stop: ASR 26,54 s, zusammengeführtes Transkript 83,15 s, Bericht 246,85 s. Nach ASR ungefähr 41 s Aufbereitung, 9 s Sprecheranalyse, 6 s Systemspurprüfung, 165 s Bericht.
- Früheres MLX-Whisper isoliert auf demselben Original: 10,323 s; anderer Text, kein bestätigter Genauigkeitssieger.
- Aktuelle gespeicherte Testausgabe wurde während der Ursachenprüfung nicht durch die bessere Gruppenzahl der Originalanalyse ersetzt.

Originale und Zwischenaudio dieser neuen Sitzungen unterliegen weiterhin der Sieben-Tage-Frist (28.09.2026; maßgeblich gespeichertes Ablaufdatum). Danach sind diese Reproduktionen ohne Audio nicht mehr möglich. Nicht stillschweigend Aufbewahrung verlängern.

## 7. Bisherige Versuche — nicht blind wiederholen

| Versuch | Ergebnis / Konsequenz |
|---|---|
| Historische 21-s-Anisa-Aufnahme | Keine saubere Referenz; eventuell TV im Hintergrund. Nicht als einziges Qualitätsbeispiel verwenden |
| Fünf historische Ausschnitte / neun Tonspuren | Pipeline/Erhaltungsprüfungen möglich, keine bestätigte Sprecher-/Wortreferenz |
| MLX Whisper Large v3 | Schnell auf Apple-GPU, aber große Auslassung in Aufnahme A |
| `no_speech_threshold=None` | Behebt Auslassung in A nicht |
| Isolierter Ausschnitt 10–52 s | Mehr, aber weiter fraglicher Text; kein vollständiger Produktfix |
| Verstärkung ×8 mit Clipping | Ausschnitt wurde schlechter; keine pauschale Verstärkung übernehmen |
| Naive 20-s-Fenster | Halluzination „Das war’s für heute.“; nicht ungeprüft integrieren |
| Parakeet TDT v3 über FluidAudio | A etwa 3,3 s Laufzeit, erkennbare Wortfehler; kein bewiesener Sieger |
| Qwen3-ASR 1.7B 4 Bit | A etwa 14,1 s, erkennbare Abweichungen; Vollpräzision nicht getestet |
| faster-whisper Large v3 CPU/int8/Beam 5/VAD | A 203 statt 128 Wörter, aber langsamer und keine WER-Referenz. Frühe 225,7-s-Messung durch parallele Last verunreinigt |
| Beam Search einfach in MLX-Whisper aktivieren | In verwendeter Version nicht implementiert; NotImplementedError |
| MossFormerGAN für ASR | Verändert/verschlechtert Wörter; ASR bleibt auf Original |
| MossFormerGAN für Sprecher | A mehr Gruppen, B weniger; kein zuverlässiger Standard |
| Community-1 CPU vs MPS | Auf neun geprüften Spuren gleiche Turns; Kurzfall 7,37 statt 28,17 s. Geschwindigkeits-, kein Genauigkeitsnachweis |
| Community-1 mit erzwungenen drei Sprechern | Liefert drei Gruppen; beweist weder automatische Erkennung noch korrekte Identität. Nicht integriert |
| Gemma3-4B / Qwen3-8B Berichte | Rollen-/Bedeutungsfehler, keine Freigabe |
| Qwen3.5-9B mit Ollama 0.34.2 | Struktur gültig auf zwei Fällen, Inhalt weiterhin falsch; nicht aktiviert |
| Qwen3.8-27B | Bessere Kontrollfälle, echte Bedingung semantisch verändert; großer/langsamer experimenteller Berichtersteller |
| Zusätzliche Selbstprüfung des Berichts | Übersah Bedeutungsfehler. Zustimmende Modellprüfung ist kein Faktenbeweis |
| Denkmodus plus strukturiertes Schema | Ollama 500 „no user query found in messages“, nach etwa drei Minuten; keine Lösung |

Noch NICHT untersucht: Qwen-ASR in Vollpräzision, Whisper.cpp/Metal mit geeigneter Decodierung, weitere neue Modelle/grundlegend andere Architekturen. Keine Behauptung, diese wären automatisch besser. Modellnamen sind Kandidaten, keine Vorgabe an Claude.

### Neueste akustische Prüfung ohne Namen oder Kontext-Raten

Community-1 auf beiden Originalen, zusätzlich halbe Amplitude und eine Sekunde vorangestellte Stille (in RAM, Zeitversatz korrigiert): B bleibt bei drei, A bei zwei Gruppen. Auf beidseitig als Einzelstimme erkannten Bereichen stimmen zugeordnete Gruppen nach Kennungsabgleich etwa 98,6–99,9 % überein. **Das ist Stabilität unter kleinen Änderungen, NICHT Genauigkeit.**

FluidAudio offline findet in beiden Originalen zwei Gruppen. Übereinstimmung mit Community-1 auf vergleichbaren Abschnitten nur rund 67–69 %. Abweichende Sprachaktivität/Überlappungen getrennt erfasst. Kein Modell als Wahrheit behandelt.

Bei B sind 13 von 26 Sprecherabschnitten kürzer als 0,2 s, bei A sieben von 39. Das trägt zur zerstückelten Wortzuordnung bei. Nicht blind glätten und dabei echte kurze Einwürfe löschen.

Stimmenmerkmale aus sechs bzw. 19 mindestens einsekündigen, modellseitig nicht überlappten Ausschnitten: Ähnlichkeitsbereiche gleicher/verschiedener Gruppen überlappen. Bei B haben zwei Gruppen nur je ein geeignetes Beispiel. Merkmalsextraktor ist Bestandteil der Gruppierung, keine unabhängige Referenz. Keine belastbare einfache Tonhöhen-/Ähnlichkeitsschwelle. Kontext darf keine Sprecheridentität erfinden.

## 8. Technische Arbeit, die erhalten werden kann

- Getrennte Test-App/Daten/Shortcut, Single-Instance-Schutz für denselben Datenordner.
- Getrennte Mikrofon-/Systemspuren, atomare Zwei-Sekunden-Chunks; fortlaufendes Resampling 44,1/48 → 16 kHz und Sichern letzter Samples. Zeitlücken bleiben als Stille statt Zusammenschieben.
- Meeting-Mikrofon ohne Browser-Echounterdrückung, Rauschfilter und automatische Pegelregelung.
- Keine Tonhöhenheuristik, kein „erster Sprecher = Ich“, kein textbasiertes Umsortieren.
- Gleichzeitiges Sprechen nicht pauschal als Echo gelöscht; tatsächliche Audiokorrelation nur Hinweis.
- Versionierte Sitzungen, Modelle/Fehler/Checkpoints; getrennte Wiederaufnahme der Stufen.
- Stabile wortbasierte IDs und separate Nutzerkorrekturen; nach Neuberechnung unverknüpfbare Korrekturen sichtbar statt still verloren.
- Finales Transkript und Sprecherzahl schon vor langsamem Bericht aktualisiert.
- Bei mindestens zehn Sekunden vollständig untranskribierter erkannter Sprecherabschnitte Bericht zurückgestellt (`needs-transcript-review`). Diese Metrik erkennt nicht sämtliche fehlenden Wörter und ist keine WER.
- Wiedergabe ab Textstelle, Korrekturen, TXT/HTML/PDF, Belegverweise.
- Sieben-Tage-Audiolöschung einschließlich Zwischenkopien durch LaunchAgent; alte historische Aufnahmen ausgenommen, Text/Bericht bleiben.
- Netzgesperrte getrennte Modellprozesse, nur eigener lokaler Ollama-Zugriff für Bericht; schwere Modelle nacheinander.

## 9. Belege und Prüfgrenzen

`docs/validation/` enthält anonymisierte Nachweise:
- `2026-09-21-local-evaluation.md`: erste Modellvergleiche.
- `2026-09-21-additional-recordings.json`: weitere historische Aufnahmen.
- `2026-09-21-product-text-preservation.json`: erkannter Text auf neun Spuren erhalten.
- `2026-09-21-mps-comparison.json`: CPU/MPS-Vergleich.
- `2026-09-21-long-offline.json`: historischer Langlauf, 1.655 s Mikrofon / 3.342,6 s Systemton; Prozessabbruch und Fortsetzung, kein Verlust erkannter Wörter. Ungleiche historische Längen beweisen keine neue Aufnahmesynchronität.
- `2026-09-21-room-three-failure.json`: erste neue Raumaufnahme fehlgeschlagen.
- `2026-09-21-room-acoustic-improvement.json`: experimenteller längerer Raumtest; damaliger Mehr-Gruppen-Befund, durch späteren Rückschritt relativiert.
- `2026-09-21-two-room-root-cause.json`: Aufbereitungsregression und Startverzögerung.
- `2026-09-21-acoustic-stability.json`: neueste Stabilitäts-/Widerspruchsmessung, ausdrücklich keine Genauigkeitsfreigabe.
- `2026-09-21-report-review.json`: semantische Berichtsfehler.

Zuletzt 140 App-Tests in 18 Dateien und 41 Python-Tests bestanden. Vite/Packen/ad-hoc-Signatur wurden am installierten Build geprüft. Vier schon auf der Basis vorhandene TypeScript-Fehler `Profile`/`CustomAgent` in `Dashboard.tsx` (1266/1268/1306/1309); kein vollständig grüner Typecheck.

In echter UI geprüft: Testgespräche öffnen, Wiedergabe bei 17,64 s, Korrektur speichern, PDF als lesbare zwei Seiten. Audiolöschung auch bei geschlossener Test-App geprüft. Das belegt Funktionen, nicht Produktqualität.

**Offen:** mindestens 95 % richtige verständliche nichtüberlagerte Sprecherzeit je Situation, höchstens 10 % deutsche Wortfehler, alle wichtigen Inhalte/faktentreuer Bericht; menschlich bestätigte Referenz fehlt. Echte neue lange Offline-Aufnahmen, Gerätewechsel, Telefon/Hybrid, ähnliche Stimmen/Überlappung und Gesamt-Alltagstauglichkeit nicht abgenommen. Instinct-Empfang nicht nachgewiesen.

## 10. Lokale Werkzeuge und wichtige Fallen

Code im Worktree:
- `electron-menubar/meeting/local-controller.js`: Start/Stop/Zustand. Start meldet aktiv vor Mikrofonbereitschaft; bisherige Endzeitprüfung verpasst Anfangslücke.
- `electron-menubar/src/apps/meeting-overlay/MeetingOverlay.tsx`: getUserMedia → AudioContext → Worklet → Aufnahmeepoch; Initialisierungslatenz untersuchen.
- `electron-menubar/meeting/local-pipeline.js`, `local/worker.py`, `local/enhancer.py`, `local/reporter.py`: Verarbeitung.
- `electron-menubar/meeting/local-store.js`, `local-retention.js`, `local-retention-agent.js`: Speicherung/Löschung.
- `electron-menubar/src/apps/dashboard/views/MeetingDetail.tsx`: Gesprächsausgabe; „Originalstellen“ sind derzeit ASR-Zitate, kein verifizierter Originalwortlaut.
- `tools/meeting-eval/stability.py`, `run_model.py`, `evaluate.py`, `metrics.py`, `test_*.py`: Prüfwerkzeuge.

Private Arbeitsdateien liegen in ignoriertem `work/`, u.a. `work/results`, `work/samples`, `work/voice-stability`, `work/room-*.json`, `work/latest-raw-speakers.json`, `work/older-raw-speakers-audit.json`. Nicht hochladen. Embeddings ebenso privat wie Aufnahmen behandeln.

Umgebungen/Modelle bereits vorhanden:
- `work/venv`: MLX-Whisper 0.4.3 / mlx-audio 0.5.4; Python 3.12.13, kein pip; bei Bedarf uv nutzen.
- `work/pyannote-venv`: pyannote.audio 4.0.4, MPS.
- `work/acoustic-venv`: faster-whisper 1.2.1, ClearVoice 0.1.2 (interne Versionsanzeige irreführend 0.1.0), Torch 2.8.
- `work/models/`: Whisper, Qwen-ASR, pyannote, faster-whisper-large-v3, mossformer-gan.
- `work/FluidAudio/.build/release/fluidaudiocli`; FluidAudio-Modelle im Benutzer-Supportordner.
- `work/ollama-0.34.2/ollama`, `work/ollama-models`.
- Modellrevisionen/Hashes und Pakete in `tools/meeting-eval/models.lock.json` und `requirements-*.lock`.
- Kostenlose Community-1-Freigabe/Download bereits erfolgt; keinen neuen Token-Dialog erfinden. Keine Zugangsdaten in Git/Übergabe.

Die installierte App hat ihre eigene vorbereitete Laufzeit unter `/Users/allanha/Library/Application Support/Paply Gespräch Test/runtime/runtime.json`. Vorbereitung durch `electron-menubar/scripts/prepare-local-runtime.cjs`; ausgewählte Modelle/Umgebungen per APFS geklont, Python-Basisverweise repariert. `work/runtime-acoustic.json` beschreibt den experimentellen Stand. Auch eine Runtime-Konfiguration wird in die App gepackt: Bearbeiten einer Datei ist kein Beweis, dass die laufende App sie verwendet. Tatsächliche Pfade/Startkonfiguration prüfen.

Testbefehle vom Repo aus:
```sh
npm --prefix electron-menubar test -- --run
work/venv/bin/python -m unittest discover -s tools/meeting-eval -p 'test_*.py'
```

Test-App nur gezielt bauen, aus `electron-menubar`:
```sh
npm run build:meeting-test -- '/Users/allanha/Library/Application Support/Paply Gespräch Test/runtime/runtime.json' '/Users/allanha/Documents/Codex/2026-09-21/hi-x20/outputs/paply-test-build'
```
Vorher Test-App regulär beenden und Prozessende prüfen; keine laufende App überschreiben, normale App unberührt lassen. Nicht pauschal `npm run build` verwenden (Produktions-Signierhooks). Der ausführbare App-Name muss ASCII bleiben: `Paply Meeting Test`. Der frühere Name mit Umlaut verursachte Startabstürze unter Electron 33. Bereits beseitigt, alte Crashdialoge nicht mit neuem Fehler verwechseln.

## 11. Empfohlener Einstieg für Claude — Vorschlag, keine Architekturbindung

1. Aktuellen lokalen Stand und beide Originalaufnahmen selbst nachvollziehen. Die zwei konkreten Fehler zuerst behandeln: pauschale Aufbereitung und falsches Bereitschaftssignal beim Aufnahmestart. Keine weitere blinde Modellinstallation als ersten Schritt.
2. Aufnahmequalität, Worterkennung und Sprecherzuordnung getrennt untersuchen; kurze Grenzsprünge, Überlappung und unterschiedliche Entfernung berücksichtigen. Kontext darf beim Erklären helfen, nicht akustische Beweise ersetzen.
3. Wenn andere Architektur bessere Ergebnisse bringt, radikal ersetzen. Entscheidungen an denselben mehreren Aufnahmen gegenprüfen; Rückschritte wie A verbessert/B verschlechtert sichtbar machen. Automatische stabile drei Labels nicht als drei korrekt erkannte Personen verkaufen.
4. Erst auf tragfähigem Text einen faktentreuen Bericht aufbauen; Originaltranskript nicht vom Berichtsmodell umschreiben lassen. Verständliche Ausgabe mit Bericht oben, Konversation unten als Vorschau zeigen.
5. Durchgängiges Produkt einschließlich realer Wartezeit, Offlineverhalten und Fehlerfällen prüfen. Erst dann neue klar benannte Testversion bereitstellen; keine unfertige Änderung als zuverlässig erklären. Allan nur dann um Information bitten, wenn diese wirklich nicht aus vorhandenen Daten gewonnen werden kann.

Technisch bestandene Tests, stabile Gruppierung und schönere Oberfläche sind jeweils nützlich, aber ersetzen nicht die noch fehlende Gesprächsqualität. Übergabe bedeutet ausdrücklich keinen Abschluss der Umsetzung.
