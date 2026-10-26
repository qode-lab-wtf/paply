# Paply Notes testen

Notes ist als reguläres [Paply 1.15.0](https://github.com/qode-lab-wtf/paply/releases/tag/v1.15.0) veröffentlicht. Für den Alltag die normale App unter `/Applications/paply.app` verwenden. Den Stand der MacBook-Aktualisierung und Datenübernahme beschreibt [STAND.md](../STAND.md).

1. Die normale Paply-App öffnen; Version im Dashboard prüfen: **1.15.0**. Den alten separaten Test-Starter nicht parallel verwenden.
2. **Cmd+Y** startet und stoppt eine Gedankenaufnahme. **Cmd+Alt+Y** öffnet das Board. Beide Kürzel lassen sich in den Einstellungen ändern. Die Notes-Pille zeigt eine eigene grün-goldene Aura.
3. Alternativ Notes über die App oder die Menüleiste öffnen. Der vorhandene Groq-Key gilt auch für Notes.

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
- Trifft ein Transkript genau beim Speichern ein, kann ein Versionshinweis erscheinen. Der Entwurf bleibt offen; mit erneutem „Übernehmen“ bestätigst du ihn.
- Beim Wechsel in eine andere App soll der Editor speichern und schließen. Dieser native Fokuswechsel ließ sich in der Testautomation nicht zuverlässig auslösen; bitte einmal per Cmd+Tab ausprobieren. Bleibt der Editor offen, wartet nur dieser Moment auf das Schließen.
- Windows ist erfolgreich gebaut, braucht aber noch den Praxistest. Echte Berechtigungsdialoge und physische Mikrofonbedienung sind nicht vollständig durch die automatisierte QA abgedeckt.

## Frühere separate Testversion

Die vorangegangene `1.15.0-notes.2` liegt auf dem MacBook unter `~/Applications/Paply-Notes-Test` und verwendete ausschließlich `~/.paply-notes-test`. Dieser Stand bleibt als Rückfallmöglichkeit erhalten. Ein frisches Testprofil sieht leer aus. Das Repository und `electron-menubar/dist/notes-test` liegen auf dem Mac mini; sie sind nicht die installierte MacBook-App.

Prüfbelege: [separate QA](QA.md), [gepackte App](PACKAGED-QA.md), [Editor-Nachprüfung](EDITOR-QA.md), [Opus-Abschlussprüfung](OPUS-EDITOR-NACHPRUEFUNG.md), [Umsetzung und Modellproben](IMPLEMENTIERUNG.md).
