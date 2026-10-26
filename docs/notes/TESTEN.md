# Paply Notes testen

Dies ist die Anleitung zur separaten Testversion. Nach Allans Freigabe wird Notes als reguläres **1.15.0** veröffentlicht und in die installierte MacBook-App übernommen; den aktuellen Stand beschreibt [STAND.md](../STAND.md). Danach für den Alltag die normale Paply-App verwenden.

Lokale macOS-Testversion **1.15.0-notes.2** für Apple Silicon. Keine Veröffentlichung, keine Änderung der installierten App.

**Auf Allans MacBook:** Seit 26.10.2026 liegt die Test-App unter `~/Applications/Paply-Notes-Test`. Der Starter **Paply Notes testen.command** liegt auf dem Schreibtisch. Der vorhandene Groq-Key ist bereits im separaten Testprofil eingerichtet. Die installierte App unter `/Applications/paply.app` bleibt 1.14.1; zum Notes-Test den Schreibtisch-Starter verwenden. Das Repository und der unten verlinkte Buildpfad liegen auf dem Mac mini.

1. Das bisher laufende Paply beenden, damit die globalen Kürzel frei sind.
2. [Paply Notes testen.command](../../electron-menubar/dist/notes-test/Paply%20Notes%20testen.command) öffnen. **Der erste Start sieht leer aus:** eigener Datenordner `~/.paply-notes-test`. Den vorhandenen Groq-Key in die App-Einstellungen eintragen.
3. **Cmd+Y** startet und stoppt eine Gedankenaufnahme. **Cmd+Alt+Y** öffnet das Board. Beide Kürzel lassen sich in den Einstellungen ändern. Die Notes-Pille zeigt eine eigene grün-goldene Aura.

Seit `notes.2` berücksichtigen Voreinstellungen und Anzeige die tatsächliche Mac-Tastaturbelegung. In `notes.1` lagen Y/Z bei deutschen Tastaturen vertauscht. Bereits selbst gesetzte Kürzel behalten ihre Tastenposition; Notes zeigt deren aktuelle Beschriftung an.

## Kurz ausprobieren

- Einen Gedanken oder mehrere Themen sprechen; das Fenster kann dabei geschlossen bleiben. Nach dem Sichern ordnet Paply geeignete Inhalte als Notizen, Mindmap, Tabelle oder Ablauf ein. Die Themen oben bewegen die Ansicht auf derselben Fläche.
- Notiz ziehen oder am Rand vergrößern; Verbindungen folgen live. Doppelklick zum Bearbeiten, kleines Kontextmenü zum Kopieren/Entfernen. Cmd+Z macht Benutzeränderungen innerhalb der Sitzung rückgängig.
- Unten Pfeil oder Linie auswählen und ziehen; Endpunkte verschieben und an Notizen andocken. Leertaste+Ziehen bewegt die Fläche; Trackpad scrollt, Pinch zoomt.
- Text und Bilder mit Cmd+V einfügen. Ein Bild an einer ausgewählten Notiz bleibt kompakter Anhang. Kamera nimmt den Bildschirm im Moment des Klicks auf.
- Optional in Notes-Einstellungen „Bildschirmkontext“ aktivieren: Bei Aufnahmebeginn wird ein einzelnes Startbild vorgehalten. Mit „Bildschirm merken“ oder „Bitte Screenshot machen“ am Anfang der Aufnahme wird es übernommen. Ohne dieses Signal wird das Startbild verworfen. Die zusätzliche Bildbeschreibung lässt sich separat aktivieren.

## Was du wissen solltest

- Nach Quotenende, fehlendem Key oder Verbindungsfehler bleiben Gedanken lokal gesichert. Im Eingang stehen Zustand und Wiederholen. Kein Modellaufruf durch bloßes Öffnen, Verschieben oder Bearbeiten.
- Das kostenlose Groq-Kontingent hängt von deinem Konto und weiterer Nutzung ab. Notes begrenzt Requests und Kontext zusätzlich; es gibt keine Zusage unbegrenzter Gratisnutzung.
- Manuell verschobene, vergrößerte oder bearbeitete Rohkarten bleiben bewusst als Rohnotiz erhalten. Ihre Position wird anschließend nicht von der KI neu geordnet. Weitere Teile einer langen Aufnahme werden weiterhin verarbeitet.
- Entfernen nimmt Karten von der Fläche; Originaltranskript bleibt lokal. Erfolgreich verarbeiteter Ton wird nach sieben Tagen beim nächsten Appstart bereinigt. Undo gilt für diese Sitzung.
- Bitte **den Starter** benutzen: Ein direkter Start der enthaltenen `paply.app` würde den normalen Datenordner öffnen. Zum normalen Paply zurückkehren: Test-App beenden, installierte App öffnen.
- Trifft ein Transkript genau beim Speichern ein, kann ein Versionshinweis erscheinen. Der Entwurf bleibt offen; mit erneutem „Übernehmen“ bestätigst du ihn.
- Beim Wechsel in eine andere App soll der Editor speichern und schließen. Dieser native Fokuswechsel ließ sich in der Testautomation nicht zuverlässig auslösen; bitte einmal per Cmd+Tab ausprobieren. Bleibt der Editor offen, wartet nur dieser Moment auf das Schließen.
- Windows, echte Berechtigungsdialoge und die physische Hotkey-/Mikrofonbedienung brauchen noch den Praxistest. Die Test-App lädt keine Updates und ändert kein globales Login-Item.

Prüfbelege: [separate QA](QA.md), [gepackte App](PACKAGED-QA.md), [Editor-Nachprüfung](EDITOR-QA.md), [Opus-Abschlussprüfung](OPUS-EDITOR-NACHPRUEFUNG.md), [Umsetzung und Modellproben](IMPLEMENTIERUNG.md).
