# Paply Notes — gezielte GUI-Nachprüfung N1/N2

**Aktueller Abschluss: B2, A, A2, B sowie Clipboard-Grenze und Konfliktbestätigung im Paket `7c410e6a…79ebe` bestanden.** Der Nachtrag am Ende dokumentiert diese letzte Runde. Der folgende ursprüngliche Bericht bezieht sich auf den früheren Hash `d5c07bc4…f57122`.

26.10.2026 · Unabhängiger QA-Agent `/root/notes_independent_qa` · Anschluss an `PACKAGED-QA.md` und Opus v4.

**A, A2, B und C bestanden.** Zusätzlich bestand der direkte Wechsel zwischen zwei Editoren mit gespeichertem ersten und zweiten Entwurf. Die B-Zusammenführung blieb nach einem Prozessneustart im Main-Snapshot erhalten. Kein neuer Appfehler wurde in diesen Fällen festgestellt. Ein echter nativer Fensterblur konnte unter der Automation nicht zuverlässig ausgelöst werden und bleibt ausdrücklich unbestätigt.

## Geprüftes Paket

- Version `1.15.0-notes.1`, `app.isPackaged:true`.
- Während dieser Runde gestarteter Pfad: `electron-menubar/dist/notes-test-final/mac-arm64/paply.app`.
- **Finaler Übergabepfad:** `electron-menubar/dist/notes-test/mac-arm64/paply.app`. Nach Ende aller QA-Prozesse vom Hauptagenten unverändert übernommen und mit gleichem Hash bestätigt. Der Starter wurde von dieser QA nicht gestartet.
- SHA-256 von `Contents/Resources/app.asar`, vor und nach der Runde identisch: `d5c07bc4b425d323ab57b27a3f77d14cafe08684cc65325741f13713d4f57122`.
- Vier getrennte frische Testprofile (`n1-a`, `n1-a2`, `n1-b`, `n2-c`), exakter Dummy-Key `paply-notes-test-key`, isolierte F18/F19/F20-Kürzel. Kein Produktivprofil, echter Key oder Live-Groq.
- Normale Sandbox in allen Läufen. Board und Pille bestätigen `sandbox:true`; `--no-sandbox` war nicht gesetzt.
- Ausschließlich eigene Loopback-Antworten: insgesamt drei Planrequests und ein STT-Request. Verzögerte Antworten wurden erst bei tatsächlich offenem Editor freigegeben.

## Ergebnisse

| Fall | Ausführung und Ergebnis |
| --- | --- |
| **A — Plan trifft auf offenen geänderten Entwurf** | Drei Sätze per echter Zwischenablage/⌘V eingefügt. Planrequest zurückgehalten, Rohkarte per Doppelklick geöffnet und Textarea geändert. Plan geliefert, lokale `plan-0.json` abgewartet, Editor weitere 2,4 s offen gehalten. Rohkarte und unveränderter Entwurf blieben vorhanden. Übernehmen speicherte exakt den Entwurf; Entry endete `kept_user`. Original unverändert, **genau ein Planrequest**. |
| **A2 — Editor unverändert schließen** | Eigenes frisches Profil, gleicher Ablauf ohne Textänderung. Fertiger Plan blieb während des offenen Editors lokal geparkt. Unverändertes Übernehmen schloss den Editor; danach wurde die Rohkarte durch den gecachten Plan ersetzt. Alle drei Originalsätze blieben sichtbar vertreten, Entry `complete`, **genau ein Planrequest**. |
| **B — STT trifft auf offenen Aufnahme-Platzhalter** | Notes über den echten Aufnahmebutton gestartet. Chromiums internes Fake-Mikrofon lief durch `getUserMedia`, AudioWorklet, PCM-Schreibpfad und echten Multipart-WAV-Upload. Während der Aufnahme den Platzhalter per Doppelklick geöffnet und einen Entwurf geschrieben. Stop über das vorhandene Capture-Preload-API, damit der Editor den Fokus behielt; anschließend verzögertes STT geliefert. Die Textarea behielt den Entwurf, während der Main-Store bereits das Transkript enthielt. Übernehmen ergab exakt `Meine Ergänzung während der Aufnahme.\n\nDas synthetische Transkript bleibt vollständig auf der Fläche.`; `pending:false`, Entry `kept_user`. Original vollständig erhalten. **Ein STT-Request, null Planrequests.** |
| **B — erneutes Öffnen nach Prozessneustart** | Dasselbe isolierte B-Profil neu gestartet; Main-Snapshot enthielt unverändert beide Texte und `pending:false`. Dies ist ein Persistenz-Lesetest. Ein unmittelbar nach Öffnen erstelltes frühes Bildschirmbild wurde nicht als visueller Nachweis gewertet. |
| **C — überlange Tabellenzelle** | Quelle aus einem 2.340 Zeichen langen Satz plus zweitem Satz, insgesamt 2.389 Zeichen. Mock lieferte eine Tabelle mit nicht belegtem Kurz-Zitat, das beim Prüfen auf den vollständigen langen Originalsatz erweitert wird. Ergebnis: **zwei normale Notes**, beide Texte exakt vollständig, keine Tabelle, Original unverändert, Entry `complete`. Nach weiteren Queue-Ticks weiterhin **genau ein Planrequest**, keine Retry-Schleife. |
| **Direkter Editorwechsel** | Ersten Entwurf geändert und unmittelbar die zweite Notiz doppelt angeklickt. Der erste Entwurf wurde gespeichert, nur der zweite Editor blieb offen. Dessen Entwurf anschließend normal übernommen und im Store geprüft. Keine zusätzlichen Modellrequests. |

## Aktueller Audio-Nachweis und historische Grenze

Fall B lief mit `--use-fake-device-for-media-stream` und `--use-fake-ui-for-media-stream`, **ohne Audiodatei und ohne deaktivierte Sandbox**. Die Flags wurden vor Aufnahmebeginn im tatsächlichen App-Prozess geprüft. Aufgenommen wurden 2.082,625 ms synthetischer Chromium-Testton; der wirkliche WAV-Upload hatte 66.688 Byte und 16 kHz. Es wurden weder menschliche Mikrofonhardware noch PCM-Injektion verwendet.

Der in `QA.md` dokumentierte frühere `--no-sandbox`-Workaround betraf ausschließlich das Lesen einer lokalen Fake-WAV-Datei durch Chromiums Audio-Sandbox. Er ist historische Testinfrastruktur und wurde hier **nicht** gebraucht. Der aktuelle B-Nachweis belegt den vollständigen synthetischen Audiopfad mit normaler Sandbox; echte Hardware und TCC-Berechtigungsdialoge bleiben weiterhin ungetestet.

## Unbestätigter Zusatzpunkt: nativer Fensterblur

Der Versuch, vom offenen zweiten Editor zum Dashboard zu wechseln, konnte keinen belastbaren nativen Fokuswechsel herstellen: `BrowserWindow.isFocused()` blieb für sämtliche Paketfenster `false`, während der Board-DOM `document.hasFocus()` meldete. `Dashboard.show()/focus()` und `app.focus()` änderten das nicht. Es wurde kein künstlicher DOM-`blur`-Event verwendet. Der native Blur-Autosave ist daher weder als bestanden noch als Appfehler gezählt. Der direkte Editorwechsel und das normale anschließende Speichern wurden unabhängig davon tatsächlich geprüft.

## Belege, Werkzeuge und Abschluss

Artefaktordner:

`/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-pxTxtl/`

`results.json` enthält die Ergebnisse und Requestmetadaten; die vier Profilordner enthalten Originale, Plan-Caches und persistierte Boards. `last-upload.wav` enthält ausschließlich synthetischen Testton. Kein Rendererfehler im aufgezeichneten Log.

Visuell geöffnet und geprüft: `n1-a-plan-held-draft.png`, `n1-b-stt-with-open-draft.png` und `n2-long-table-as-notes.png`. Das frühe Bild `n1-b-merged-after-restart.png` zeigt noch keine gezeichnete Karte und belegt deshalb nicht den fertigen Rendererzustand; ausschließlich der explizite Snapshot-Vergleich zählt für den zusätzlichen Neustart-Lesetest.

Tests: `electron-menubar/tools/notes-qa/editor-races.cjs`, erweitert um kontrollierte Transportantworten und Fallprofile in `packaged-harness.cjs`. Nur QA-Dateien und Berichte wurden durch diesen Agenten geändert. Syntaxprüfungen und `git diff --check` bestanden. Die vollständige Testsuite wurde nicht erneut ausgeführt; Gesamtsuite/TypeScript/Build verantwortet der Hauptagent.

Alle eigenen Appinstanzen, der Harness und der Loopback-Server wurden regulär beendet. Abschließende Prozesssuche ohne Treffer. Der Umfang dieser Runde ist gezielt N1/N2; die breitere Paketprüfung des vorherigen Hashs steht unverändert in `PACKAGED-QA.md`.

## Abschlussnachtrag nach Opus v5 — B2 und Editorgrenzen

26.10.2026, nach der Korrektur der Pending-Grenze im ersten Editor-Render. **Alle vereinbarten Fälle bestanden; kein verbleibender Blocker in diesem gezielten Prüfumfang.** C und der direkte Editorwechsel wurden in dieser letzten Runde nicht erneut ausgeführt; deren vorherige Ergebnisse bleiben oben dem damaligen Paket zugeordnet.

### Paket und Isolation

- Tatsächlich gestartetes Paket: `electron-menubar/dist/notes-test-final/mac-arm64/paply.app`, Version `1.15.0-notes.1`, `app.isPackaged:true`.
- Endgültiger Übergabepfad: **`electron-menubar/dist/notes-test/mac-arm64/paply.app`**. Nach Prozessfreigabe unverändert übernommen; der Hauptagent bestätigte den identischen folgenden Hash.
- SHA-256 von `Contents/Resources/app.asar`, vor und nach der Runde identisch: **`7c410e6a1477dd7cd0c60461da067501b2df9651001317976df955d246479ebe`**.
- Jeder Fall verwendete ein frisches temporäres Profil, ausschließlich den Dummy-Key `paply-notes-test-key` und Loopback-Transport. F18/F19/F20, kein Produktivprofil, kein echter Groq-Aufruf, keine menschliche Mikrofon- oder Bildschirmaufnahme.
- Normale Sandbox durchgehend aktiv. Tatsächliche Fensterpräferenzen bestätigten `sandbox:true`, `contextIsolation:true`, `nodeIntegration:false`; `--no-sandbox` war nicht gesetzt. Aufnahme über Chromiums internes Fake-Gerät, reguläres `getUserMedia`, AudioWorklet, PCM-Sicherung und Multipart-WAV. Der historische dateibedingte Sandbox-Workaround aus der ersten Entwicklungsrunde wurde weiterhin nicht benötigt.

### Ergebnisse im letzten Paket

| Fall | Unabhängig ausgeführte Prüfung und Ergebnis |
| --- | --- |
| **B2 — speichern, wieder öffnen, weiter ändern, dann STT** | Während der Aufnahme ersten Zusatz eingegeben und übernommen. Im Main bestätigt: `owner:user`, `pending:true`, `rev:2`. Dieselbe Karte erneut geöffnet, zweiten Entwurf eingegeben, Aufnahme ohne Fokuswechsel über das vorhandene Capture-Preload gestoppt und verzögertes STT geliefert. Nach sichtbarer Ankunft des Transkripts blieb der zweite Entwurf unverändert. Ein Klick auf Übernehmen speicherte **nur den zweiten Entwurf plus genau ein vollständiges Transkript**; der erste Zusatz wurde ersetzt. Editor geschlossen, Original erhalten, Entry `kept_user`, **1 STT / 0 Planrequests**. WAV: 79.062 Byte, 16 kHz, 2.469,3125 ms. |
| **A — Plan bei geändertem offenem Entwurf** | Echte Zwischenablage/⌘V, verzögerter Plan, geänderter Editor. Plan lokal gespeichert und weitere 2,4 s abgewartet. Entwurf und Rohkarte erhalten; Übernehmen speicherte exakt den Entwurf, Original blieb erhalten. **1 Planrequest**, Entry `kept_user`. |
| **A2 — unverändert schließen** | Frisches Profil; Plan bei unverändert offenem Editor lokal geparkt. Nach Übernehmen ersetzte derselbe gecachte Plan die Rohkarte; alle drei Originalsätze vertreten. **1 Planrequest**, Entry `complete`; kein zweiter Request. |
| **B — erster offener Aufnahmeentwurf plus STT** | Erneut vollständiger synthetischer Audiopfad mit normaler Sandbox. Entwurf überstand STT und wurde zusammen mit genau einem vollständigen Transkript gespeichert; Editor geschlossen, Original erhalten. **1 STT / 0 Planrequests**. WAV: 65.580 Byte, 16 kHz, 2.048 ms. |
| **Tatsächliches Einfügen von mehr als 20.000 Zeichen** | Manuelle Haftnotiz über die UI erstellt und wieder geöffnet. 20.050 Zeichen in die native Zwischenablage geschrieben, im Textarea echtes ⌘A/⌘V ausgeführt. DOM enthielt exakt die ersten 20.000 Zeichen; Übernehmen schloss den Editor und speicherte diese 20.000 Zeichen vollständig. **Keine Modellrequests.** |
| **Konkurrierende Textänderung und erneutes Übernehmen** | Manuelle Notiz offen bearbeitet; konkurrierende Änderung über das normale `paplyNotes.command` erzeugt. Erster UI-Save zeigte die Konfliktmeldung, behielt den Entwurf und ließ den konkurrierenden Store-Text unverändert. Escape blieb ohne Überschreiben. Zweites ausdrückliches Übernehmen speicherte den Entwurf und schloss den Editor. **Keine Modellrequests.** |
| **DOM-Grenzen** | Erstes Pending-Textarea: **16.998** in B2 und B. In B blieb diese Reserve nach STT beim weiterhin offenen Editor erhalten. Normale Notiz **20.000**, Tabellenkopf **100**, Kriterium **100**, Tabellenzelle **2.000**. |

### Beobachtete schnelle Speicheraktion nach STT

Die ersten beiden B2-Anläufe speicherten unmittelbar nach dem neuen Main-Snapshot, während der Renderer noch den Pending-Spinner und die alte Revision zeigte. Der erste Klick wurde korrekt ausgeführt, scheiterte aber am Revisionsschutz. Die unmittelbare Meldung lautete: „Notiz inzwischen geändert. Dein Entwurf bleibt offen. Erneut Übernehmen bestätigt deinen Text.“ Ein zweiter echter Klick speicherte den zweiten Entwurf plus das vollständige Transkript; keine Daten gingen verloren.

Diese Abfolge wurde über passive Pointer-/Toast-Aufzeichnung und eine durchleitende Beobachtung des vorhandenen IPC-Handlers im Testprozess nachvollzogen. Der Aufruf enthielt die alte `rev:2`; Main wies ihn korrekt zurück. Das war kein hängender Editor und kein verlorener Klick. Der abschließende B/B2-Akzeptanztest wartet daher auf die **sichtbare** STT-Ankunft (Pending-Spinner verschwunden), nicht nur auf einen bereits neueren Main-Snapshot. Die schnellere Aktion bleibt als gesonderter erfolgreich behandelter Konflikt dokumentiert.

Das zuvor geprüfte Zwischenpaket `265ce84d…f9b30` hatte beim ersten Öffnen fälschlich `maxlength=20000` statt `16998`. Diese Runde wurde nach dem Befund gestoppt. Die hier geprüfte Korrektur ist im ersten DOM-Render bestätigt.

### Belege und Abschluss dieser Runde

Artefakte: `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-b7dBOG/`.

- `results.json`: sechs erfolgreiche Ergebnisdatensätze einschließlich des zusätzlich diagnostizierten schnellen Revisionskonflikts; insgesamt **4 STT-Requests** (inklusive zweier Diagnoseanläufe) und **2 Planrequests**, alle lokal simuliert.
- `b2-probe.json`: durchgeleitete IPC-Aufrufe, Pointer-Ereignisse, unmittelbare Toasts und lesende Hook-Diagnose des B2-Konflikts. `security-final.json`: tatsächliche Paket-/Fenstereinstellungen.
- Visuell geöffnet und geprüft: `n1-b2-second-draft-merged.png`, `n1-a-plan-held-draft.png`, `n1-b-draft-merged.png`, `editor-conflict-retains-draft.png`. B2 und B zeigen beide Texte vollständig, der Konflikt-Screenshot den unverlorenen Entwurf samt konkreter Bestätigungsmeldung.
- QA-Werkzeuge: `editor-races.cjs`, `editor-probe.cjs`, `packaged-harness.cjs`. Keine Appdateien geändert. Die protokollierten drei `notes:command`-Fehler gehören zu den absichtlich bzw. bei STT diagnostizierten Revisionskonflikten; keine Rendererfehler beobachtet.

Syntaxprüfungen der drei QA-Werkzeuge bestanden. Die vollständige Suite wurde nicht wiederholt. Alle eigenen Paketinstanzen, der Harness und der Loopback-Server wurden regulär beendet; die abschließende Prozesssuche hatte keine Treffer. Der Starter wurde nicht gestartet. Das unveränderte geprüfte Paket ist zur Übernahme durch den Hauptagenten freigegeben. Physische Tasten, echte Audiohardware, echter nativer Fensterblur und Live-Modellqualität bleiben außerhalb dieser gezielten Runde.

Übergabe durch den Hauptagenten abgeschlossen: Das Paket liegt unter `electron-menubar/dist/notes-test/mac-arm64/paply.app`; der isolierte Starter heißt `electron-menubar/dist/notes-test/Paply Notes testen.command`. SHA-256 nach der Übernahme unverändert: `7c410e6a1477dd7cd0c60461da067501b2df9651001317976df955d246479ebe`.
