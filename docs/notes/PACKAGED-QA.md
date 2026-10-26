# Paply Notes — unabhängiger Paket-Smoke

26.10.2026 · Zweite unabhängige QA-Runde · Agent `/root/notes_independent_qa`.

Die anschließende gezielte Prüfung der N1/N2-Korrekturen am final übergebenen Paket mit neuem Hash ist separat in [EDITOR-QA.md](EDITOR-QA.md) dokumentiert. Die folgenden breiteren Smoke-Ergebnisse beziehen sich auf den hier ausdrücklich genannten vorherigen Hash.

**Ergebnis:** Das korrigierte macOS-arm64-Paket besteht die 14 unten protokollierten Prüfungen. Ein fehlendes Mindmap-Kantenpaar und unerwünschte globale Startaktionen des ersten Testpakets wurden gemeldet, vom Hauptagenten korrigiert und im zweiten Paket nachgeprüft. Im ausgeführten Umfang bleibt kein offener Befund. Dies ist eine lokale Testabnahme, keine Release-Freigabe.

## Genau geprüfter Stand

- Version `1.15.0-notes.1`, `app.isPackaged === true`.
- Erster Lauf: `electron-menubar/dist/notes-test/mac-arm64/paply.app`.
- Abschließend geprüfter korrigierter Lauf: `electron-menubar/dist/notes-test-next/mac-arm64/paply.app`. Der Hauptagent übernimmt dieses Bundle anschließend an den vorgesehenen Testpfad.
- SHA-256 der abschließend geprüften `Contents/Resources/app.asar`: `0ef51b96863063ccc2dc7164a2105f191c8df2c564eb4591b37e3e8c2ceef461`.
- Normale Sandbox während der gesamten Runde; kein `--no-sandbox`. Board und Pille: `sandbox:true`, `nodeIntegration:false`, `contextIsolation:true`.
- Frische temporäre Profile, ausschließlich Dummy-Key `paply-notes-test-key`, F18/F19/F20, keine kopierte Produktivkonfiguration. Meeting, Autopaste, Bildschirmkontext und Bildverständnis deaktiviert. Kein echtes Mikrofon gestartet.
- Echter Electron-Prozess über Playwrights Electron-Unterstützung; Modelltransport ausschließlich zum eigenen Loopback-Server. Im abschließenden Profil genau **ein** Planrequest für zehn synthetische Sätze. Kein Live-Groq-Aufruf durch diese QA.

## Gefundene und korrigierte Fehler

| Befund | Beleg | Nachprüfung |
| --- | --- | --- |
| **PK1: Linke Mindmap-Kanten fehlen.** `LooseMode` allein genügte nicht: Der linke Griff war ein Target-Handle; React Flow sucht den Source-Endpunkt auch im Loose-Modus nur unter Source-Handles. | Nach echtem Text-Paste: fünf Kanten im Store, nur drei SVG-Pfade. Die beiden linken Hub-Verbindungen fehlten auch sichtbar. `02-packaged-missing-edge.png` im ersten Artefaktordner. | Beide Seiten sind jetzt Source-Handles im Loose-Modus. Alle fünf Pfade vorhanden. Für beide linken Kanten wurden tatsächliche SVG-Endpunkte gegen die äußere linke Hub-Griffkante und rechte Ziel-Griffkante gemessen: Abweichung unter 3 px. Screenshot visuell geprüft. |
| **PK2: Isolierter Paketstart stößt globale Startaktionen an.** `autoStart:false` führte zu einem Versuch, das globale Login-Item zu löschen; der automatische Updatecheck scheiterte an fehlender `app-update.yml`. | Erster Paketlog: AppleScript-Aufruf `delete login item "paply"` endete im Timeout; Updatecheck endete mit ENOENT. Kein Download oder Installationsaufruf. | Hauptagent unterbindet diese beiden Startaktionen bei `PAPLY_USER_DATA`. In beiden Starts des korrigierten Pakets keine entsprechenden Meldungen/Fehler. Der native Update-Lifecycle-Listener blieb vorhanden und wurde separat geprüft. |

## Bestandene Prüfungen des korrigierten Pakets

| Prüfung | Tatsächlicher Nachweis |
| --- | --- |
| Paket, Preloads, Leerstart | Leerer Store mit Revision 0; Board und verborgen vorgeladene Pille aus `app.asar/renderer`. Eigene Capture-API antwortet mit `phase: idle`; Sandbox-Einstellungen oben. |
| Text-Paste bis Struktur | Native Zwischenablage + echtes ⌘V; zehn sichtbare Objekte in drei Themen: Karten, Haftnotiz, freier Text, Hub und Tabelle, dazu Mindmap-/Ablaufkanten. Ein konformer Loopback-Planrequest, Entry `complete`. |
| Linke Mindmap-Verbindungen | Zwei nach links gerichtete Kanten sichtbar und geometrisch an den richtigen Griffseiten angeschlossen; kein alleiniger Store-Nachweis. |
| Hub bearbeiten | Doppelklick auf das echte Hub-Element, Textarea bearbeiten, Übernehmen: `Meine ruhige Auszeit` gespeichert und sichtbar. |
| Live-Drag | Echte Mausbewegungen bei gedrückter Taste; linke Zielkarte und zugehöriger SVG-Endpunkt bewegten sich bereits vor Loslassen gemeinsam. |
| Resize | Echter Griff-Drag; Karte auf 417 × 234 px vergrößert und gespeichert. |
| Bearbeiten/Kopieren/Delete/Undo/Redo | Notiz geändert, Original unverändert, native Zwischenablage geprüft; Delete entfernt zugehörige Kante, Undo stellt sie wieder her; Redo stellt die Textbearbeitung wieder her. |
| Originaldialog | Echter dreifacher Pointer-Klick selektiert den Quellabsatz; ⌘C kopiert genau die Auswahl. Delete und Backspace lassen sämtliche Boardnoten unverändert. |
| Kamera-Hide | `desktopCapturer.getSources` im Test-Main vorher durch eine synthetische 160 × 90-PNG-Quelle ersetzt. Beim einzigen Aufruf war das Board verborgen, danach wieder sichtbar; Bild wurde über den normalen Kamera-/Assetpfad angehängt. Kein Nutzerbildschirm aufgenommen. |
| Settings-Kürzel | Separates Settings-Fenster per UI geöffnet, Aufnahme-Kürzel auf `Ctrl+Alt+F12` geändert und übernommen. Neues natives Kürzel registriert, F18 freigegeben; danach F18 wiederhergestellt. |
| Renderer-Crash | `forcefullyCrashRenderer()` zerstörte Boardfenster 4. Öffnen über das unverändert laufende Dashboard erzeugte Fenster 6; Nodes und Kanten waren identisch. |
| Native Update-Beendigung | Nur `autoUpdater.emit('before-quit-for-update')` ausgelöst, mit einem vorhandenen Listener. Anschließendes `Board.close()` zerstörte Fenster 6 vollständig. Kein Updatecheck, Download, Installieren oder Release ausgelöst. |
| Performance/Viewport | Messung unten; echte Wheel-Ereignisse änderten Renderer- und gespeicherte Viewportkoordinaten, ohne Boardrevision oder Board-Broadcast. |
| Sauberes Beenden | Letzte reguläre Beendigung in 617 ms. Alle eigenen Appinstanzen, beide Harness-Prozesse und Loopback-Server beendet; abschließende Prozesssuche ohne Treffer. |

## Gezielte Leistungsmessung

60 kurze synthetische Objekte, gleichmäßig auf Karte/Haftnotiz/Freitext verteilt. Über gültige User-Commands erzeugt und auf kleine 170 × 110-px-Flächen gesetzt, damit alle bei **100 % Zoom** in das 1900 × 999-px-Fenster passen. Die Fixture dient der Messung und ist kein Beleg für das Layout gewöhnlicher langer Notizen. Sie ersetzte erst nach Abschluss der Funktionsprüfungen deren synthetische Boardobjekte; die Funktionsansicht wurde separat gesichert.

| Messung | Ergebnis |
| --- | ---: |
| Vollständig sichtbare Nodes am Messbeginn | 60 |
| Gemessene Frame-Abstände während etwa 3 s echtem Wheel-Pan | 186 |
| p95 | **16,7 ms** |
| Maximum | 18,4 ms |
| Boardrevision vorher → nachher | 20 → 20 |
| `notes:changed`-Broadcasts während Pan | 0 |
| DOM und persistierter Viewport, X vorher → nachher | 55 → −142 |
| Zoom vorher/nachher | 1 / 1 |

Die endgültige Messung wartet ausdrücklich, bis gespeicherter Viewport und tatsächliche DOM-Matrix übereinstimmen. Vorläufige Harness-Annahmen über Debounce-Zeit, Handle-Mittelpunkt, Kürzel-Alias und Fixture-Größen wurden korrigiert; sie wurden nicht als Appfehler gezählt. Kein erneuter Vollsuite-Lauf, da dieser Smoke gezielt das gebaute Paket prüft.

## Belege und Grenzen

Erster Artefaktordner: `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-vRSvLm/`.

Abschließender Artefaktordner: `/var/folders/0p/3rr4yfqs47xbdb7p_0j4p8dr0000gn/T/paply-notes-packaged-qa-PBKHTl/`.

`results.json` enthält die 14 bestandenen Nachweise, Messdaten und Requestmetadaten. `functional-board.json` bewahrt die Funktionsansicht vor der Performance-Fixture; `main.log` enthält den Paketlog. Keine Renderer-, AutoLaunch- oder Updatecheck-Fehler im abschließenden Log. Tatsächlich visuell geprüft: erster fehlender Kantenstand sowie final `02-packaged-left-fixed.png`, `03-packaged-original.png`, `06-packaged-crash-recovered.png`, `05-packaged-performance-start-100pct.png` und `05-packaged-performance-100pct.png`. Die Überlappung der Karte im Crash-Screenshot stammt vom absichtlichen manuellen Drag/Resize.

Die reproduzierbaren Hilfen liegen unter `electron-menubar/tools/notes-qa/packaged-{harness,cases}.cjs`; `canvas.cjs` wird für die echten Pointerprüfungen wiederverwendet. Der QA-Agent änderte keine Appdatei.

Offen bleiben physische globale Tastenauslösung, echte Mikrofonhardware und Berechtigungsdialoge, tatsächliche Nutzerbildschirmaufnahme, Trackpad-Pinch, Windows, Signierung/Notarisierung und Live-Modellqualität. Die Pille wurde im Paket geladen und ihr Preload geprüft; eine neue Tonaufnahme wurde in dieser Runde bewusst nicht gestartet. Die frühere synthetische Audio-/Recovery-Runde ist separat in `QA.md` dokumentiert.
