# Reaktion auf Opus-Abschlussreview

26.10.2026 · Umsetzung durch Hauptagent · Basis: OPUS-ABSCHLUSSREVIEW.md, Task paply-notes-final-opus55-xhigh-v3.

- **B2 / P1-3:** Geometrie setzt `pinned`, bewahrt Herkunft und verhindert anschließendes KI-Umordnen. Pending-Karte wird trotzdem mit Transkript gefüllt, weitere Batches werden sichtbar; während Aufnahme manuell ergänzter Text bleibt vor dem Transkript. No-op-Blur schreibt nichts. 3 Varianten × 60 Sätze Regression, ursprüngliches Opus-Repro ebenfalls grün. Freitext bleibt nach Drag in gleicher Schrift. Mindmap-Zentren jetzt editierbar.
- **P1-1:** Stop ohne Ton und Recovery lösen den Pending-Zustand auf; sichtbares „Kein Ton aufgenommen“, kein Dauerzähler.
- **P1-2:** Eigener `fallback`-Endzustand mit sichtbarem Hinweis; „Erneut“ setzt Batchcursor/Fallback zurück, schon strukturierte oder bearbeitete Objekte werden übersprungen. Regression beweist neuen Request und unveränderte Quelle.
- **B3:** Native `before-quit-for-update` setzt Notes `closing` und beendet Recorder/Queue vor dem Fensterschließen. Echter Update-Download wird nicht ausgelöst; gepackter Smoke soll das Ereignis/Fensterschließen prüfen.
- **B1:** Kontextkürzung und kleinere Batches. Echte Kalibrierung mit 30 Notizen / 20 Themen / UUID-IDs / 12 Sätzen: reserviert 7.520, Prompt 3.324 + Ausgabe 1.861 = 5.185; 12/12 abgedeckt, Mindmap, Finish stop. Bericht lokal `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-bench-3wotQi/report.json`. Vier vorherige 120B-Proben ebenfalls ohne Trunkierung, aber keine statistisch belastbare Rate. Kurze ID-Aliasse sind Optimierung, aktuell kein Blocker.
- **P2-1:** Board wird für Kameraaufnahme verborgen und danach wieder angezeigt.
- **P2-2:** ReactFlow Loose-Handles, KI-Kanten wählen Griffseiten anhand relativer Knotenposition. Physisches Mitgehen bereits QA-belegt; neue linken Mindmap-Kanten im Smoke prüfen.
- **P2-3:** Pending-Startbilder überleben Neustart; nur fertige/verwaiste/verworfene oder >7 Tage alte temporäre Bilder bereinigen. Regression vorhanden.
- **P2-4:** Zu kleines Tagesbudget eigener endlicher `budget_small`-Fehler → needs_attention, kein Tick-Dauerloop. 5k bleibt zulässig, meldet erforderliche Erhöhung konkret. Normale Quotenwiederholung auf endliche Retrywerte begrenzt.
- **P2-5:** Eigene Quelle und Pending-Nodes aus Kontext entfernt, einheitliche Unicode-Wortzerlegung.
- **P2-6:** Nach Renderer-Crash wird das tote Boardfenster zerstört; nächstes Öffnen erzeugt neu.
- **P2-7:** Memoisierter Board-Kontext mit drei Detailstufen statt ständigem Zoomwert; Ansicht separat gespeichert, kein Board-Revision/Broadcast beim Pan. Nachmessung folgt im gepackten Smoke. Echte Trackpad-Pinch-Gesten bleiben physisch zu testen.
- **P2-8:** Qwen explizit reasoning_effort none, dokumentierter JSON-Modus, validierte Strings und Finish-Check. Vision-Request hat jetzt Abort beim Beenden.
- **P2-9:** Dialoge fangen keine Board-Shortcuts ab; Textselektion darf nativ kopieren.
- **P3-1/2/3/4:** Verwaiste Linienpunkte entfernen (Undo erhält ganze Linie); Object.prototype-IDs ablehnen; Diskfehler schließen FD und geben Capture-Lease frei; Source-Einträge im einzigen schreibenden Repo gecacht. Zusätzliche Tiefenvalidierung für syntaktisch gültige beschädigte Boards mit Rückfall auf vorige Generation.
- **P3-5:** Explizit vor Verarbeitung abgewiesene 401/403/404/429 mit 0 abrechnen. Fehler nach möglicher Modellverarbeitung weiter konservativ reservieren.
- **P3-6:** Unverändert konservativer Diktatvorrang auch während des Diktat-Netzjobs; vorerst dokumentierte Einschränkung, keine Änderung am vorhandenen Diktatablauf.
- **P3-7:** Cmd+D dupliziert lokal; eingefügter Text wird als neuer Gedanke eingeordnet. Diese Bedeutung bleibt bewusst gleich für Fremdtext und kopierten Text.
- **P3-8:** Pille wird verborgen vorgeladen. Heller Fensterhintergrund/Windows-Pinch/Range-Seeking bleiben kleine dokumentierte Grenzen der Testversion; keine Release-Freigabe behauptet.

Zusätzliche Härtung: bereits registrierte Notes-Kürzel werden bei fokussierter Kürzel-Erfassung in den Settings ins Feld geliefert; nicht aus Versehen als Aufnahme ausgelöst. Bei fehlgeschlagenem Board-Command wird die bestätigte Main-Sicht erneut geladen. Entfernte Momente synchronisieren Source-Sichtbarkeit bei Undo/Redo.

## Nachtrag aus dem gepackten Smoke

- Zwei linke Mindmap-Kanten waren trotz LooseMode unsichtbar: React Flow akzeptiert beim Source-Ende ausschließlich Source-Handles. Beide Griffseiten sind jetzt Source-Handles; LooseMode erlaubt sie auch als Ziel. Paket erneut gebaut, praktische Nachprüfung folgt.
- Das bestehende AutoLaunch initialisierte in einem isolierten, gepackten Testprofil das globale Login-Item. Testmodus mit `PAPLY_USER_DATA` ändert jetzt weder Login-Item noch lädt/installiert er Updates. Normale App unverändert; Regression für diese Trennung.
- Bildanhänge bleiben bei der Einordnung einmal pro Moment sichtbar, statt sich auf alle generierten Zweige zu vervielfachen. Neues Regressionstest deckt es ab.
- Live-Kurzprobe 20B: 1/1 Satz, 2.092 Token, 823 ms; blieb ohne neues Thema als einzelne Notiz. Live-Bildprobe mit synthetischem Rechteck/Text: korrektes JSON mit Beschreibung und sichtbarem Text, 331 ms. Kein Nutzerbildschirm wurde dafür verarbeitet.
- Das manuelle Verbinden zweier Karten setzt ebenfalls nur `pinned`; die Schrift-Herkunft einer KI-Notiz bleibt erhalten. Eigene Regression ergänzt; keine zusätzliche Rendereränderung.


## Gezielte Nachprüfung v4 und Antworten (20:42)

- Gepackte separate QA abgeschlossen: alle 14 Fälle grün, normale Sandbox, sichtbare linke Mindmap-Kanten, Crash/Wiederöffnen, natives Update-Beendigungsereignis. Bei 100 % und 60 sichtbaren Notizen: p95 16,7 ms, Max 18,4 ms; Pan erzeugt keine Board-Revision und keinen Board-Broadcast. Bericht `PACKAGED-QA.md`.
- **N1:** Main bestätigt eine kurzlebige Bearbeitungs-Lease vor Öffnen des Editors. Queue prüft sie vor dem Request und nach der Antwort. Der fertige validierte Plan wird mit Rohkartenrevision lokal gesichert und nach Editorende wiederverwendet. Editorwechsel werden serialisiert; der Text speichert mit der Revision vom Öffnen, bei Konflikt bleibt der Entwurf offen. Ein während der Bearbeitung eingetroffenes Transkript wird beim Pending-Übergang an den Entwurf angehängt. Unverändertes Schließen macht die Karte nicht zur Benutzerkarte. Editor wird beim Pan nicht durch Viewport-Culling entfernt. Crash/Navigation lösen die Lease; Fenster-Blur speichert.
- **N2:** Tabellen mit finalen Zitaten >2.000 Zeichen werden als Struktur verworfen, vollständige Mitglieder bleiben Notizen. Eine deterministisch ungültige Projektion endet im Fallback. Bei einem lokalen Schreibfehler wird der bereits gesicherte Plan wiederverwendet. Regressionen belegen genau einen Modellaufruf.
- **N3:** Auch Benutzertext in einem Aufnahmeplatzhalter beendet bei leerer Transkription den Spinner.
- **N4:** Mindmap-Zentren gehören mit `sourceId` zu ihrem Moment; Entfernen/Undo betrifft die ganze Mindmap.
- **N5:** Verworfener Plan aufgrund Benutzeränderung zeigt `kept_user`; zuvor erfolgreich projizierte Teile werden beim Retry nicht als Benutzeränderung gezählt.
- **N6:** Bilder anhängen und Kanten verbinden setzen nur `pinned`, erhalten die Textherkunft und Schrift.
- **N7/N8:** Fehlgeschlagener echter Squirrel-Neustart bleibt Release-Prüfung (Test-App ohne Updater). Manuell verschobene/vergrößerte Rohkarten bleiben in v1 bewusst an Ort und Stelle als Rohnotizen; explizites Neuordnen ist nicht enthalten.
- Automatische Gesamtsuite nach diesen Fixes: **603/603 Tests in 41 Dateien**. TypeScript ohne Fehler. Opus prüft N1/N2 gezielt in Task `paply-notes-editor-opus55-xhigh-v5`; separate GUI-Nachprüfung A/A2/B/C folgt im finalen Paket.

- Separate GUI-Nachprüfung im finalen Paket: A offener korrigierter Entwurf, A2 unverändertes Schließen mit gecachtem Plan, B eintreffendes STT während Editor, C überlange Tabellenzelle, direkter Editorwechsel und B-Neustart bestanden. A/A2/C je genau ein Planrequest; B genau ein STT-Request, kein Planrequest, echte 16-kHz-WAV aus Chromiums synthetischem Mikrofon, normale Sandbox. Native Fensterblur-Prüfung aus Harness-Fokusbegrenzung nicht bestätigt; normale Übernahme und Editorwechsel geprüft.
- Finaler Übergabepfad `electron-menubar/dist/notes-test`; app.asar SHA-256 `d5c07bc4b425d323ab57b27a3f77d14cafe08684cc65325741f13713d4f57122`. Kein Testprozess mehr aktiv.


## Abschluss v5 und letzte gezielte Korrekturen

Opus 5.5 Extra High hat den geprüften Stand lokal freigegeben, ohne Release-Freigabe. Bericht `OPUS-EDITOR-NACHPRUEFUNG.md`; weitere Opus-Runde laut §5 nicht nötig. Die empfohlenen Nachbesserungen wurden anschließend umgesetzt und separat nachgeprüft:

- **N9:** `src/lib/notes/editor.ts` erkennt den Pending-Übergang anhand der hinzugekommenen Satzreferenzen, auch bei bereits gespeichertem Benutzertext. Nur das neue Transkript wird an den zweiten Entwurf angehängt, nicht dessen alter Prefix. Reine Geometrieänderungen können ohne Textüberschreiben neu basiert werden; andere Textkonflikte benötigen bewusstes erneutes Übernehmen. Text-/Tabellenfelder begrenzen Eingaben auf die Store-Verträge. Pending-Editor reserviert zusätzlich Platz für den späteren Transkriptteil.
- **N10:** Plancache speichert die erlaubten Themen-/Notiz-IDs aus dem ursprünglichen Request. Er wird weiterhin validiert, jedoch nicht gegen eine zwischenzeitlich veränderte Top-20-Auswahl. Gelöschte Referenzziele werden beim Commit wie bisher übersprungen.
- **N11:** Bewusstes „Erneut“ nach Fallback verwirft den früheren Plan; automatische Wiederholungen nach Schreibfehler/Editor-Wartezeit behalten ihn.
- **P3a:** Lease-Konflikthinweis wird ohne internen IPC-Fehlerpräfix dargestellt. Kosmetisches Leer-STT-Label und Snapshot-Frequenz bei blockiertem Moment bleiben kleine Grenzen dieser Version.
- Neue Regressionen für erneutes Öffnen, Geometrie-/Textkonflikt, verschobene Top-20-Themen und expliziten Retry: **608 Tests in 42 Dateien grün**, TypeScript und Build grün. Separate Paketnachprüfung B2/A2/A/B plus Konflikthandhabung angefordert; Ergebnis im Nachtrag von `EDITOR-QA.md`.

- Opus v5 hat während der Berichtserstellung auch die letzten N9–N11-Fixes am Stand 20:56 selbst nachgeprüft: 79 Notes-Tests und TypeScript grün, aktuellem Arbeitsstand lokale Freigabe erteilt. Verlangte Paketstichproben: B2, A/A2, bewusste Konfliktübernahme, >20.000-Zeichen-Paste. Dafür läuft die abschließende separate QA.
- In dieser Paketstichprobe fiel die Eingabegrenze beim allerersten Render eines leeren Aufnahmeplatzhalters noch auf 20.000 zurück (Ref erst nach Render initialisiert). Die JSX-Bedingung berücksichtigt jetzt zusätzlich den aktuellen `n.pending`-Zustand. Paket erneut erstellt; Nachweis wird mit B2 wiederholt.

- Sehr schneller B2-Save vor sichtbarer STT-Ankunft separat beobachtet: Main hatte bereits Revision 3, Renderer zeigte noch Pending/Revision 2. Der erste Update wurde korrekt abgewiesen; Hinweis erschien, zweites Übernehmen speicherte den zweiten Entwurf plus genau ein vollständiges Transkript. Kein verlorener Text und keine hängende Promise. Das ist der von Opus beschriebene zusätzliche Klick, kein neuer Blocker. Steady-State-B2 wird zusätzlich nach sichtbarem Spinnerende geprüft.


## Finale lokale Übergabe

Alle angeforderten Paketstichproben auf dem endgültigen Hash bestanden: B2, A, A2, B, tatsächliche Clipboard-Paste 20.050 → 20.000 Zeichen mit erfolgreichem Speichern, konkurrierende Textänderung mit bewusstem Übernehmen, Eingabegrenzen. Aufnahme-Pipeline in normaler Sandbox mit synthetischem Mikrofon. Alle Testprozesse beendet. Separater Abschlussnachtrag in `EDITOR-QA.md`.

**Endgültiger app.asar SHA-256:** `7c410e6a1477dd7cd0c60461da067501b2df9651001317976df955d246479ebe`. Unverändert von `dist/notes-test-final` nach `dist/notes-test` übernommen; alte Notes-Testpakete entfernt. Starter syntaktisch geprüft und ausführbar. Die installierte App wurde nicht ersetzt, kein Commit/Tag/Push/Release ausgeführt.

**Abnahme:** 608/608 Tests in 42 Dateien, TypeScript, Swift-Helfer, Vite und macOS-arm64-Paketbau erfolgreich. Opus 5.5 Extra High hat Vorprüfung, Abschlussprüfung und gezielte Nachprüfung durchgeführt; die letzten Empfehlungen sind korrigiert und unabhängig nachgetestet. Verbleibende Grenzen stehen in `TESTEN.md` und `IMPLEMENTIERUNG.md`.
