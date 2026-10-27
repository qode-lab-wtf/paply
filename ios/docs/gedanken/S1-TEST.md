# Spike S1 – Gedanken-Knopf (ca. 20 Minuten)

Ziel: Klappt der Gedanken-Knopf, auch wenn Paply nicht läuft? In diesem Testbau **ordnet Paply noch
nicht** – nach dem Stopp steht kurz „Gesichert“. Es geht nichts an Groq.

**Vorbereitung:** Sperrbildschirm lange drücken → Anpassen → Sperrbildschirm → bei der Taschenlampe „–“,
dann „+“ → **„Paply-Gedanke“**. Außerdem ins Kontrollzentrum legen („+“ oben links → Steuerelement
hinzufügen → „Paply-Gedanke“). In Paply: Entwicklerbereich → Diagnose → Löschen.

1. **Paply aus, gesperrt:** Paply im App-Umschalter wegwischen, iPhone sperren. Den Knopf drücken.
   Erscheint oben/auf dem Sperrbildschirm die Live Activity mit laufender Zeit? 10 Sekunden sprechen,
   nochmal drücken. Steht kurz „Gesichert“? (Öffnet sich stattdessen Paply bzw. fragt Face ID: notieren.)
2. **Paply aus, entsperrt:** Paply wieder wegwischen, Safari öffnen, Kontrollzentrum → „Paply-Gedanke“.
   Gleiche Fragen wie in Schritt 1.
3. **Mikro läuft, gesperrt:** Paply öffnen → „Mikro bereit halten“ einschalten (Diktat-Bereich). Sperren,
   drücken, 10 Sekunden sprechen, nochmal drücken.
4. **„Fertig“ antippen:** Aufnahme starten und auf dem Sperrbildschirm „Fertig“ tippen. Dann noch einmal
   entsperrt: Dynamic Island lange drücken → „Fertig“.
5. **Doppeldruck:** Knopf zweimal schnell hintereinander drücken. Es darf genau eine Aufnahme laufen.
6. **Siri:** „Hey Siri, Gedanke mit Paply“ → sprechen → „Hey Siri, Paply Gedanke“ zum Beenden.
   Spricht Siri etwas in die Aufnahme?
7. **Kontrollzentrum während der Aufnahme:** Zeigt der Knopf „an“ (grün, „Aufnahme“)?
8. **Anruf:** Während einer Aufnahme anrufen lassen und annehmen. Was zeigt die Live Activity danach?
9. **Diktat-Gegenprobe:** In Notizen 🌐 → Paply → diktieren: klappt wie vorher? Dann einen Gedanken
   starten und währenddessen 🌐 tippen: Der Gedanke wird gesichert, das Diktat startet.
10. **Verwerfen aus der Live Activity:** Aufnahme starten, ein paar Wörter sagen, auf dem Sperrbildschirm
    (bzw. Dynamic Island lange drücken) **„Verwerfen“** tippen. Kurz „Verworfen“, dann weg. In Paply liegt
    der Gedanke unter „Zuletzt gelöscht“ und lässt sich wiederherstellen.
11. **Protokoll schicken:** Entwicklerbereich → Diagnose → Teilen.

**Im Protokoll** (für den Koordinator): `thought.start` (`case` A/B, `ok`, `stage`, `code`, `fourCC`,
`process`, `locked`), `thought.intent` (`process`: `app` oder `wg`), `thought.attach`, `thought.stop`
(`reason`, `durationMs`), `thought.activity.*`, `thought.foreground.request` (Fall B gescheitert),
`thought.intent.forward.timeout` (Knopf lief in der Erweiterung, App antwortete nicht), `thought.discard`.

**Entscheidet:** Fall B im Hintergrund ja/nein (sonst kurz Paply öffnen), Toggle oder Knopf im Control,
Verhalten mit Siri.

## Ergebnis (27.10.2026, iPhone 14 Pro Max, iOS 18.0, entsperrt, Kontrollzentrum)

- Steuerelemente erschienen erst nach einem **Neustart des iPhones** (nach Installation über Xcode).
- **Fall B klappt im Hintergrund:** Paply lief nach dem Neustart nicht. Der Control-Druck startete die App
  unsichtbar (`thought.intent process: app`, `app: background`), die Sitzung per `AudioRecordingIntent`
  (`session.start trigger: thought-intent`, 189 ms) und die Aufnahme (`thought.start case B ok`, 237 ms,
  ohne Vorlauf). Kein Vordergrund-Rückfall nötig.
- **Fall A** (Sitzung lief): Start in 23–30 ms, mit 500 ms Vorlauf.
- **Beenden** über den Knopf (`reason: button`) und über „Fertig“ in der Live Activity (`reason: liveActivity`)
  funktioniert; 3 Aufnahmen als WAV gesichert (6,6 s / 8,6 s / 14,5 s).
- **Offen:** gesperrtes iPhone/Sperrbildschirm-Knopf, Siri, Anruf, Doppeldruck – im Gesamttest.
