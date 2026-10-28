# Review Phase 0 – Funde und Entscheidungen

Review: Sonnet 5.5 am 28.10.2026 auf Commit `0e8fbc3`. Entschieden hat die Bauleitung (Opus). Jeder Fund ist einer
Etappe zugeordnet: **A** = `:core`-Diktat-Port, **D** = Tastatur-Integration, **G** = Gedanken (Etappe 2),
**C** = App-Oberfläche.

## Gedanken-Dienst (→ G, beim Neubau des Dienstes Pflicht)
1. **Mikro-Recht vor dem Dienststart.** `CaptureActivity` prüft vorher `RECORD_AUDIO` und `POST_NOTIFICATIONS` und
   fragt danach. Ohne Recht wird der Dienst nicht gestartet. `stopSelf()` erst, wenn `startForeground` gelungen ist
   oder nie angefordert wurde. Sonst droht „did not call startForeground“ und der ganze Prozess stürzt ab, auch die
   Tastatur.
2. **Kein Auto-Start nach Recreate.** Der Start ist genau einmal pro Tipp erlaubt (Intent-Extra verbrauchen bzw. in
   `savedInstanceState` merken). Drehen, Dunkelmodus oder Prozess-Neustart dürfen nie eine Aufnahme starten.
3. **Kein Datenverlust bei Lesefehlern.** Eine Teil-WAV mit Sprache wird behalten und transkribiert. Ein Fehler in
   `trimQuietEdges` führt nur dazu, dass die Datei unbeschnitten bleibt. **Stummschaltung mitten in der Aufnahme**
   (Anruf, andere App) verwirft nicht alles:
   - stumme Abschnitte auslassen,
   - die Benachrichtigung zeigt „Unterbrochen“,
   - danach automatisch weiterschreiben.
   Bei `ERROR_DEAD_OBJECT` einmal einen frischen Recorder bauen (iOS-Lehre Build 6). Während eines Anrufs keinen
   Neustart versuchen.
4. **Ergebnis-Benachrichtigung.** Nach dem Ende erscheint eine normale, stille Benachrichtigung: „Gedanke
   gespeichert“ oder „Gedanke wartet – Schlüssel/Netz prüfen“ (Antippen öffnet ihn).
8. **Aufnahme immer sichtbar.** Ohne Benachrichtigungsrecht lässt sich die Karte nicht wegwischen, Fertig und
   Verwerfen bleiben dann auf der Karte.
9. **Kanal** `IMPORTANCE_LOW`, ohne Ton und ohne Vibration. Hinweise per eigener Vibration so wie iOS Build 7:
   - beim Verlassen der Karte bzw. App während der Aufnahme,
   - alle 2 Minuten,
   - bei „noch 1 Min.“.
10. FINISH/DISCARD ohne aktive Aufnahme rufen `stopSelf(startId)` auf.
16. Ein Kachel-Tipp bei offener Karte wirkt sofort (`onNewIntent` behandeln).
17. Eigener Text für „Mikro gerade belegt“.
14. Audio fehlgeschlagener Gedanken bekommt eine Frist und einen Hinweis in der Oberfläche (wie iOS, nur bis der
    Rohtext gesichert ist).

## Tastatur (→ D)
5. **Robustes Einsetzen.** Wechselt die InputConnection während der Transkription, wird in die aktuelle eingesetzt,
   solange dasselbe Feld fokussiert ist (Paket und Feld-ID). Andernfalls kommt das Ergebnis in die Zwischenablage,
   mit Hinweis und Eintrag im Verlauf. Es gibt einen sichtbaren Zustand „Eingesetzt“, nie ein stilles Ende.
6. **Konfigurationswechsel.** Bei Drehung während der Aufnahme wird das Panel aus dem laufenden Zustand neu
   aufgebaut. Ein Mikro ohne sichtbares Panel darf es nie geben.
7. **Passwortfelder.** Bei Passwort-Eingabetypen (Text, Web, Zahl, sichtbar) nimmt Paply nicht auf. Stattdessen
   kommen ein Hinweis und „Zurück zur Tastatur“.
13. `commitText == true` heißt nur „gesendet“. Ein Fehler führt zu Zwischenablage und Verlauf.
18. `set-test-key.py` löscht die Klartext-Zwischendatei immer (`finally`).

## Kern (→ A)
11. Ein SSE-Fehler `rate_limit_exceeded` wird wie bei iOS auf 429 mit Wartezeit aus der Meldung abgebildet.
12. Modellkatalog wie iOS `ModelCatalog`: 5 Min. im Speicher, Auffrischung im Hintergrund, nie vor dem Polieren
    warten.

## Oberfläche (→ C)
14. Der Schlüssel liegt Keystore-verschlüsselt im `KeyVault` (Auftrag C).
15. Listen werden nicht auf dem Main-Thread geladen, und Lesen löscht keine Dateien als Nebeneffekt.

## Bewusst so gelassen
- Debug-Receiver nur im Debug-Manifest mit `DUMP`. Backup-Regeln, `exported`-Flags und PendingIntents sind korrekt
  (Review ohne Befund).

## Review Kern E1A (Sonnet, Commit `fd0001a`): Restpunkte für D (Tastatur-Integration)
- Der Kern behebt die Funde 1–7 und 9 selbst (Auftrag „E1A-Fix“).
- Für D bleiben:
  - instrumentierter Kurztest der `Pattern`-Helfer auf dem Gerät bzw. Emulator (ICU-Regex auf Android)
  - FLAC-Encoder per MediaCodec als `:core`-Adapter, denn der Upload-Standard ist FLAC; ohne Adapter wird es WAV mit doppelter Größe
  - `deviceLanguages` aus `LocaleList`
  - Schlüssel beim Speichern mit `sanitizeApiKey()` bereinigen (KeyVault)

## Review Oberfläche E1C (Sonnet, Commit `19dda22`): Entscheidungen
Alle Punkte werden behoben, und zwar in einer Fix-Runde nach D, weil D gerade in `app/` arbeitet. Es sei denn, D erledigt
einen Punkt schon.

1. **Ein Schlüsselweg:** Tastatur und Gedanken-Dienst lesen nur noch über `KeyVault`. `Settings.apiKey` und `client()` aus
   Phase 0 fallen weg, kein Klartext-Schreibweg mehr. (D, Kontrolle in der Fix-Runde)
2. Keystore und `commit()` laufen nie auf dem Main-Thread. `hasKey` wird einmal berechnet und gecacht.
3. **Beta aus** wirkt auch auf Kachel und Dienst: kein Start, eine laufende Aufnahme endet wie bei iOS. → Fix-Runde
   für die Kachel, für den Dienst in G.
4. **Beschädigte Dateien sperren nie:** Verlauf und Einstellungen verschieben eine kaputte Datei nach `damaged-<ms>.json`
   und starten leer. Einträge werden einzeln dekodiert, für DataStore gibt es einen `ReplaceFileCorruptionHandler`.
5. `ThoughtStore.entries()` löscht nichts mehr (→ G, Neubau).
6. Die Diagnose hat auch im Release einen Speicherpuffer, nur mit freigegebenen Ereignissen. `takeLast(200)` statt `take(200)`.
7. Ist der Keystore-Alias kaputt, wird er gelöscht und einmal neu erzeugt. Der Alt-Schlüssel wird nicht im Klartext
   liegen gelassen.
8. `KeyVault.save` nutzt `sanitizeApiKey()` (D).
9. Löschen und das Kürzen auf 300 Einträge entfernen auch die zugehörigen Audiodateien, nur innerhalb von `filesDir`.
10. Sprachen: Es zählen nur ISO-Codes, Alt-Codes werden umgesetzt (iw → he, in → id), Pseudo-Locales wie „zz“ werden
    herausgefiltert.
11. Auf der Einrichtungskarte gibt es für die Kachel-Erkennung unter API 29–32 „Erledigt“ als Ausweg.
12. Die Zwischenablage wird nach dem Einsetzen des Schlüssels geleert. „Eigene Begriffe“ werden entprellt gespeichert.
    Von der Startkarte geht es wieder zum Start zurück.

## Review Etappe 1 – Tastatur integriert (Sonnet, Commit `da5cc3f`): Entscheidungen
Zwei Runden: **UI-Fix** (sofort, `history/`, `settings/`, `ui/Settings|Setup`) und **IME-Fix** (nach dem Gedanken-Dienst, weil
der gerade `AudioCapture`/`DictationSession` umbaut).

1. **Keine unbemerkte Endlos-Aufnahme in der Tastatur.** Geht der Bildschirm aus (`ACTION_SCREEN_OFF`), endet die Aufnahme:
   mit Sprache wird fertig verarbeitet, ohne Sprache still verworfen. Nach 10 Min. wird fertig verarbeitet, mit Hinweis,
   die gleiche Grenze wie bei Gedanken. Bewusst **kein** Stopp bei Sprechpause (Allan). Den VAD bis zur ersten Sprache
   inkrementell statt O(N²) machen. (IME-Fix)
2. `discard()` löscht zuerst die Datei. Die Verlaufslöschung läuft nur, wenn ein Eintrag existiert, und in `runCatching`.
   Im Hintergrund-Launch darf es keinen Absturz geben. (IME-Fix)
3. Verlauf: Löschen, „Alles löschen“ und das Kürzen auf 300 Einträge entfernen auch die WAVs (= E1C 9). (UI-Fix)
4. Feldwechsel: Jedes nicht-restartende `onStartInput` während einer Sitzung gilt als Wechsel, außer im Drehfenster.
   (IME-Fix)
5. Verschwindet die Tastatur, bevor das Ergebnis da ist: Zwischenablage (sensibel markiert) plus eine stille
   Benachrichtigung „Text liegt in der Zwischenablage“. Nie ein stilles Ende. (IME-Fix)
6. Rückleseprüfung normalisiert Leerzeichen und Groß-/Kleinschreibung. Eine Abweichung heißt „unbekannt“, nicht
   „fehlgeschlagen“. Keine doppelte Einfügung. (IME-Fix)
7. Zwischenablage mit `EXTRA_IS_SENSITIVE`. Steht dort nach 2 Min. noch Paplys Clip, wird er geleert. (IME-Fix)
8. `lastEntry = null` beim Start. Die Fehlerarten sind getrennt (Schlüssel, Speicher, Mikro belegt). (IME-Fix)
9. Eigene Zustände für „Schlüssel neu eintragen“ und „Speicher voll“. (IME-Fix)
10. `activeRecordingConfiguration` wird nur noch mit 1 Hz abgefragt, sonst gilt das Callback-Flag. (IME-Fix)
11. Weniger Verlaufs-fsyncs auf dem Weg von Tipp zu Text: PENDING parallel zum Upload. (IME-Fix)
12. `retry` meldet immer `completed`. Fehlt die WAV, ist der Endzustand „Audio fehlt“, und es wird der aktuelle Eintrag
    geschrieben. (IME-Fix)
13. Panel: `idle` nicht als „schreibt“ anzeigen. „Eingesetzt“ bekommt einen Zurück-Knopf. Wischen bricht einen Neuversuch
    ab. (IME-Fix)

## Review Etappe 2 – Gedanken-Aufnahme (Sonnet, Commit `7dd47f7`): Entscheidungen
Es gibt eine eigene Korrekturrunde **„Fix-G“**. Sie läuft nach dem IME-Fix, weil beide `AudioCapture` berühren.

1. **Benachrichtigung weggewischt** (ab API 34 möglich): `tick` prüft `activeNotifications`. Fehlt die Aufnahme-Meldung,
   wird sie sofort neu gepostet. Geht das nicht, endet die Aufnahme und wird gespeichert. Ein Mikro ohne Anzeige darf es
   nie geben.
2. `ready` bzw. `backend()` lassen sich erneut versuchen, und jeder Discard-Marker läuft einzeln in `runCatching`. Ein
   einzelner Fehler darf nie die ganze Funktion bis zum Neustart lahmlegen.
3. Binder-Abfragen in der Leseschleife laufen höchstens alle 500 ms, dazwischen gilt das Callback (wie IME-Fix 10).
4. `publish()` wird serialisiert (Mutex bzw. ein Konsument). Ein Schnappschuss besteht nie aus Teilen verschiedener Stände.
5. Die Trim-Kopie bekommt den Namen `.tmp-trim…`. Recovery und `releaseAudio` räumen sie weg, damit kein Sprachrest liegen
   bleibt.
6. Stummschaltung gilt nur bei `isClientSilenced` oder `isMicrophoneMute`, nicht bei Klingel- oder VoIP-Modus. Sprache
   wird nie unnötig verworfen.
7. **Beta aus** hält auch die Verarbeitung an: keine Groq-Aufrufe und keine Hygiene für ausgeblendete Gedanken. Beta an
   setzt sie fort. Daten bleiben erhalten.
8. `waitingKey` ist nicht in der 15-Minuten-Weckschleife. Der Schlüssel-Listener reicht.
9. Erst `startForeground`, dann die Zustandsaktualisierung für Widget und Kachel.
10. `finishCapture` mit 0 ms meldet sichtbar „nichts gespeichert“, nicht „gesichert“.
11. Der FileTranscriber verarbeitet PCM gestreamt bzw. in Stücken, statt 10 Min. als ein Array zu laden. Kein
    OOM-Absturz.
12. „Verwerfen“ in der Benachrichtigung verlangt Entsperren (`setAuthenticationRequired`, ab API 31). „Fertig“ geht ohne.
13. `visible()` wird etwa 1 s gecacht, damit die Karte keine Binder-Abfragen im 100-ms-Takt auslöst.
14. Widget-PendingIntent mit `FLAG_UPDATE_CURRENT`.
15. Bewusst so gelassen: Im Lautlos- bzw. DND-Modus vibriert der Hinweis nicht, die Wünsche des Nutzers gelten. Sichtbar
    bleiben Benachrichtigung, Chip und Mikro-Punkt.
