# Paply iOS – Testplan Phase 0

Für Allan, auf dem iPhone 14 Pro Max (iOS 18.0). Ziel: herausfinden, ob die riskanten Annahmen
halten, bevor wir Phase 1 bauen. Jede Frage hat Schritte, was du beobachten sollst und wo die
Messwerte stehen.

Du musst nichts Technisches lesen. Notiere, was du siehst (Tabelle am Ende), und schick am Schluss
das Diagnoseprotokoll. Alle Zeiten im Protokoll misst Paply selbst.

> **Groq-Kontingent sparsam nutzen:** Der Groq-Schlüssel läuft im kostenlosen Tarif. Fürs Polieren
> (qwen) gibt es etwa **200 000 Tokens pro Tag**, und dein Desktop-Paply nutzt denselben Schlüssel mit.
> Ist das Kontingent aufgebraucht, setzt Paply den Rohtext ein (im Verlauf steht dann „Unpoliert
> eingesetzt – Grund: Groq-Kontingent erschöpft“, in der Tastatur dezent „ohne Polieren“).
> Latenz-Testreihen (Test 3) deshalb **knapp halten** und nicht am selben Tag wie lange Desktop-Sitzungen.

---

## 0. Vorbereitung (einmal, ca. 10 Minuten)

1. **Installieren** macht der Koordinator per Kabel am MacBook.
2. **Tastatur einschalten:** Einstellungen → Allgemein → Tastatur → Tastaturen → „Tastatur hinzufügen …“ →
   Paply. Dann auf „Paply“ tippen → **„Vollen Zugriff erlauben“** an.
3. **Schlüssel:** Paply-App öffnen → Zahnrad → Groq-Schlüssel. Am Mac kopieren, am iPhone „Einsetzen“ tippen.
   Es erscheint „Schlüssel funktioniert“. Andere Meldungen: „Groq lehnt diesen Schlüssel ab“ (falsch
   kopiert), „Keine Verbindung zu Groq“ (gespeichert, später prüfen) oder ein Fehlertext von Groq.
   Bitte einmal im Flugmodus „Schlüssel prüfen“ tippen – es muss „Keine Verbindung“ kommen.
   Protokoll: `settings.apiKey.check` mit `result`.
   - **Sprachen:** Zahnrad → „Sprachen, die du sprichst“. Bei „Automatisch“ stehen dort die Sprachen
     deiner Tastaturen und des iPhones (z. B. „automatisch: Deutsch, Englisch“). Findet Paply nur
     eine Sprache, kommt Englisch automatisch dazu. Stimmt die Liste?
4. **Höhe messen – nur mit laufender Sitzung:** Auf der Startseite „Starten“ tippen und warten, bis
   „Mikro bereit“ steht. Sonst öffnet die Tastatur die App über die Testseite. Dann Zahnrad → Labor → Testseite.
   - Ins Textfeld tippen (Apple-Tastatur erscheint).
   - Mit 🌐 zu Paply wechseln, 2 Sekunden warten. (Paply nimmt dabei auf – danach einfach nach
     links wischen, das verwirft.)
   - iPhone quer drehen und beides wiederholen.
   - Unter „Gemessen“ stehen jetzt Zahlen. Ab jetzt hat Paply genau Apples Höhe.
5. **Erstes Diktat – Polieren prüfen:** Das Polieren läuft neu als Datenstrom und wurde noch nicht
   live geprüft. Nach dem allerersten Diktat mit Paply: Verlauf → ⓘ → Abschnitt „Polieren“. Dort muss
   **„Ergebnis: poliert“** und ein Modell stehen und **kein** „Unpoliert eingesetzt“. Steht dort ein
   Grund, bitte notieren und dem Koordinator sagen, bevor du weitertestest.
6. **Protokoll finden:** Zahnrad → Labor → **Diagnose**. Neueste Einträge oben. Oben rechts „Teilen“
   (Datei an den Koordinator schicken) und „Löschen“. Vor jedem großen Test einmal löschen, dann
   ist das Protokoll übersichtlich.

**So liest du das Protokoll:** Jede Zeile hat einen Namen (z. B. `kb.recording`) und Werte
(z. B. `appearToRecordingMs=38`). `kb` = Tastatur, `app` = App, `wg` = Widget-Erweiterung.
Werte mit `Ms` sind Millisekunden (1000 ms = 1 Sekunde).

---

## 1. Hält die Sitzung den ganzen Tag?

Fragen: Läuft das Mikro im Hintergrund von morgens bis abends? Was kostet das Akku?
Was passiert bei Anruf und Siri? Sieht man oben wirklich nur den orangen Punkt?

**Schritte**

1. Morgens: Diagnose löschen. Zahnrad → „Mikro bereit halten“ = **bis Neustart**.
2. Paply-App öffnen → „Starten“ (oder einfach in einem Textfeld 🌐 → Paply).
   Akkustand notieren.
3. Das iPhone ganz normal benutzen. Alle 2–3 Stunden einmal mit Paply diktieren.
4. Zwischendurch nacheinander ausprobieren und danach jeweils einmal mit Paply diktieren:
   - **Anruf** annehmen (30 Sekunden reden, auflegen).
   - **Anruf** nur klingeln lassen bzw. ablehnen.
   - **Siri** fragen („Wie spät ist es?“).
   - **Sprachmemo** aufnehmen (10 Sekunden) bzw. WhatsApp-Sprachnachricht.
   - **Video** mit der Kamera aufnehmen.
5. Abends: Akkustand notieren. Einstellungen → Batterie → Anteil von Paply notieren.
   Dann Einstellungen → Datenschutz & Sicherheit → **App-Datenschutzbericht** → Paply: Zeigt er
   Mikrofon-Zugriff (erwartet: durchgehend, solange die Sitzung lief) und **Netzwerk-Aktivität im
   Leerlauf** (erwartet: nur zu Groq und nur rund um echte Diktate)? Notieren, welche Domains wann.
6. Extra (einmal): „Mikro bereit halten“ = **15 Minuten**, 20 Minuten nichts tun.
   Ist der orange Punkt danach weg?

**Beobachten**

- Oben links nur der **orange Punkt**? Kein Paply-Symbol, keine Live Activity, kein Banner?
- Nach Anruf/Siri: Hört Paply in der Tastatur sofort wieder zu? Oder steht da
  „Mikro aus“ bzw. öffnet sich Paply kurz? (Ein Tipp auf „Paply starten“ startet den Rundlauf neu.)
- Wird das iPhone spürbar warm?

**Messwerte im Protokoll**

| Was | Zeile | Werte |
| --- | --- | --- |
| Sitzung an/aus | `session.start` / `session.stop` | `trigger`, `reason`, `durationS` (Laufzeit in Sekunden), `hold` |
| Akku, CPU, Speicher, Wärme | `metrics` (alle 10 Min und bei Änderung) | `battery`, `cpuPct`, `cpuS`, `memMB`, `thermal`, `lowPower`, `engine` |
| Unterbrechung | `audio.interruption.began` / `.ended` | `reason`, `shouldResume`, `app` (Vordergrund/Hintergrund) |
| Wiederanlauf | `audio.resume.ok` / `audio.resume.failed` | `attempt`, `code`, `fourCC` (z. B. `!int`, `!rec`) |
| Ton-Weg | `audio.route` | `in` (Mikro), `out` (Ausgabe), `reason` |
| Mikro läuft nicht | `engine.notRunning` | sollte nie vorkommen |
| Ablauf der Bereithalte-Dauer | `session.stop` | `reason=hold-expired` |

**Gut, wenn:** Die Sitzung läuft ≥ 12 Stunden ohne `session.stop`; Paply braucht wenig Akku
(`cpuPct` im Leerlauf deutlich unter 1 %); nach Anruf/Siri entweder `audio.resume.ok` oder eine
klare Meldung in der Tastatur.

---

## 2. Start aus der Tastatur und zurück

Frage: Wenn das Mikro aus ist – wie fühlt sich der Weg „🌐 → Paply blitzt auf → zurück“ an?

**Schritte (Variante A, Standard)**

1. Paply-App ganz schließen (im App-Umschalter nach oben wischen). Damit ist die Sitzung aus.
2. Notizen öffnen, in eine Notiz tippen, 🌐 → Paply.
3. Paply öffnet sich von selbst und zeigt „Mikro ist an“.
4. Zurück: oben links auf **„◀ Notizen“** tippen. Beim zweiten Mal stattdessen **unten am Rand nach rechts wischen**.
5. Die Paply-Fläche ist grün, die Zeit läuft schon. Einen Satz sagen, irgendwo auf die Fläche tippen.
6. Wiederholen in WhatsApp, Mail, Safari (Suchfeld).

**Variante B:** Zahnrad → Labor → „App automatisch öffnen“ **aus**. Wiederholen: Die Tastatur zeigt
„Paply ist nicht bereit“ mit „Paply starten“. Was fühlt sich besser an?

**Ohne Vollzugriff:** Vollzugriff ausschalten (siehe 0.2). Paply zeigt „Vollzugriff fehlt“ und
„Weiter zur nächsten Tastatur“. Klappt das Weiterschalten? Danach Vollzugriff wieder an.

**Experimentell (nur zur Info):** Labor → „Host-App protokollieren“ an, Paply einmal zeigen.
Im Protokoll steht `kb.host.experimental` – steht dort eine Bundle-ID oder `null`? Danach wieder aus.

**iOS 26** (nur falls ein Gerät mit iOS 26 da ist): gleiche Schritte. Zusätzlich: Klappt das
Öffnen der App ohne Vollzugriff? (Erwartung laut Recherche: nein.)

**Beobachten:** Wie lange blitzt Paply auf? Findest du „◀“ sofort? Geht beim Zurückwischen etwas verloren?
Hört Paply nach dem Zurückkommen wirklich schon zu (Zeit läuft)?

**Messwerte**

| Was | Zeile | Werte |
| --- | --- | --- |
| Tastatur will App öffnen | `kb.open` | `reason` |
| Welcher Weg hat geklappt | `kb.open.variant` | `variant`, `ok`, `ms` |
| App kommt an | `url.open` | `urlLatencyMs` (Tastatur → App), `sinceProcessStartMs` (kalt/warm) |
| Mikro an | `session.start` | `ms`, `in`/`out` |
| Wieder angeschlossen | `kb.attach`, dann `kb.recording` | `appearToRecordingMs` |
| Fehler | `kb.open.failed`, `kb.failure` | `kind` |

---

## 3. Wie schnell kommt der Text? (large-v3 / turbo × Stücke an/aus)

**Schritte**

Vier Durchgänge. Vor jedem: Zahnrad → Diktat → „Transkription“ und „Stücke-Upload“ einstellen.

| Durchgang | Transkription | Stücke-Upload |
| --- | --- | --- |
| A | large-v3 | an |
| B | large-v3 | aus |
| C | large-v3-turbo | an |
| D | large-v3-turbo | aus |

Je Durchgang in der Testseite (oder Notizen) diktieren – wegen des Kontingents (siehe oben) knapp:
- 2 × kurz (ca. 5 Sekunden),
- 2 × mittel (ca. 30 Sekunden),
- 1 × lang (ca. 2 Minuten, z. B. eine Mail vorlesen, deutsch und englisch gemischt).

**Testvarianten** (Zahnrad → Labor → Testvarianten der Pipeline): Upload-Format FLAC/WAV,
Sprachwechsel-Beispiel an/aus, Polieren an/aus, strenge Polier-Prüfung an/aus. Standard ist FLAC,
Beispiel an, Polieren an, strenge Prüfung an – für die Durchgänge A–D **nichts ändern**. **„Polieren aus“ nur für reine Transkriptions-Messungen**
(dann wird der Rohtext eingesetzt). Danach wieder „Auf Standard zurücksetzen“. Jede Variante steht
im Protokoll als `opts` und wird in der Auswertung getrennt ausgewiesen.

Am besten alles im WLAN, dann Durchgang A nochmal im Mobilfunk (WLAN aus). Paply notiert das Netz
selbst (`net` = `wifi` / `cellular`).

**Beobachten:** Gefühlte Wartezeit nach dem Tipp („Poliere …“). Stimmt der Text? Werden Namen aus
„Eigene Begriffe“ erkannt?

**Messwerte**

| Was | Zeile | Werte |
| --- | --- | --- |
| Gesamt, wie du es spürst | `kb.inserted` | `tapToInsertMs` (Tipp → Text steht da), `model`, `chunked`, `net`, `id` |
| Aufteilung in der Tastatur | `kb.result` | `tapToAppMs`, `appProcessingMs`, `writtenToKbMs` |
| Aufteilung in der App | `dictation.result` | `model`, `chunked`, `net`, `opts`, `audioS`, `flushMs`, `transcribeMs`, `polishMs`, `totalMs`, `chunks`, `bytes`, `tapIntervalMs` |
| Polieren | `dictation.result` | `polishModel`, `polishError` (z. B. `rate-limited`, `server-error`), `rejected` (Sicherheitsnetz, z. B. `replaced`) |
| Pro Diktat in der App | Verlauf → ⓘ | „Zeiten“ |

Der Koordinator bekommt mit `pull-logs.sh` automatisch Median und Mittel je Modell · Stücke · Netz,
für die App-Seite und für „Tipp → eingesetzt“; abweichende Testvarianten stehen getrennt daneben.

### 3a. Gemischte Sprachen

In Notizen auf Deutsch diktieren und mittendrin einen ganzen englischen Satz einschieben, z. B.:
„Ich habe das Update eingespielt. **The build is green and all tests pass.** Morgen schauen wir uns
die Zahlen an.“ Dreimal, mit unterschiedlichen Sätzen.

**Prüfen:** Bleibt der englische Satz **englisch** (nicht ins Deutsche übersetzt, nicht eingedeutscht)?
Stimmt der deutsche Teil? Im Verlauf → ⓘ: Rohtext und eingesetzter Text vergleichen – passiert die
Übersetzung schon beim Erkennen (Rohtext) oder erst beim Polieren?
Protokoll: `dictation.result` → `langs` (z. B. `de,en`), `rejected`.

### 3b. Nichts verstanden

In Notizen 🌐 → Paply, dann **nichts sagen** (oder nur Lärm: klopfen, rascheln, Musik im Hintergrund)
und nach ein paar Sekunden auf die Fläche tippen.
Erwartet: „**Nichts verstanden** – Tippen = neu sprechen · ← wischen = zurück“. Es wird **nichts**
eingesetzt, und im Verlauf der App erscheint **kein** Eintrag.
- Tippen → Paply nimmt sofort neu auf (gleiche Fläche). Einen Satz sagen, tippen → Text kommt.
- Zweiter Durchgang: nach „Nichts verstanden“ nach links wischen → zurück zur nächsten Tastatur.

Protokoll: `dictation.noSpeech` (App, ohne Text), `kb.noSpeech` (Tastatur), `dictation.result` mit `noSpeech=true`.

### 3c. Strenge Polier-Prüfung

Die strenge Prüfung verwirft polierten Text schon, wenn Wörter ersetzt oder eingefügt wurden; dann
wird der Rohtext eingesetzt. Wegen des Kontingents nur kurz: Je 3 mittlere Diktate (ca. 30 Sekunden,
gern mit Zahlen, Namen und einem „nicht“) mit strenger Prüfung **an** (Standard) und **aus**
(Testvarianten). Danach wieder „Auf Standard zurücksetzen“.
**Prüfen:** Wie oft steht im Verlauf → ⓘ „Sicherheitsnetz hat den polierten Text verworfen“? Wirken die
polierten Texte mit Prüfung aus besser oder schlechter (Wörter verändert, Sinn verdreht)?
Protokoll: `dictation.result` → `rejected` (Code, z. B. `replaced`, `inserted`), `opts` (`…·strict` bzw. `…·loose`).

### 3d. Erneut versuchen nach Fehler

Diktieren, kurz vor dem Tipp auf „fertig“ den **Flugmodus** einschalten, dann tippen.
Erwartet: „Das hat nicht geklappt … Tippen = erneut senden · ← wischen = verwerfen“.
Flugmodus aus, auf **„Erneut versuchen“** tippen → der Text kommt (dieselbe Aufnahme, nichts neu
sprechen; Paply sendet nur die gescheiterten Teile erneut).
Zweiter Durchgang: statt erneut senden nach links wischen → verworfen.
Protokoll: `kb.retry`, `dictation.retry` (`attempt`), `dictation.result` (`retries`, `keptForRetry`),
`dictation.retry.released` (`reason` = `discarded` oder nach 10 Min `expired`).

---

## 4. 🌐, Rücksprung, Höhe, erstes Laden, Durchschalten

**Vorbereitung:** Tastaturen: Deutsch, Englisch, Emoji, Paply – **Paply ans Ende der Liste**
(Einstellungen → Allgemein → Tastatur → Tastaturen → Bearbeiten). Reihenfolge notieren.
Hintergrund: Nach dem Einsetzen springt Paply mit `advanceToNextInputMode` zur **nächsten**
Tastatur der Liste, nicht zur vorigen. Steht Paply am Ende, heißt „weiter“ = zurück zur ersten.

**Schritte**

1. **Durchschalten:** In Notizen 🌐 mehrmals schnell antippen, sodass Paply nur kurz vorbeikommt
   (unter 1 Sekunde). Es darf **nichts passieren**: keine App öffnet sich, kein Text, nichts wird
   gesendet. Zweimal testen: **mit laufender Sitzung** und **mit ausgeschalteter Sitzung**
   (App weggewischt) – ohne Sitzung darf sich Paply erst öffnen, wenn die Tastatur gut 1 Sekunde stehen bleibt.
2. **Wohin nach dem Einsetzen:** Mit Paply diktieren, tippen. Bei welcher Tastatur landest du? Notieren.
   Dann Paply in der Liste verschieben (z. B. direkt vor Emoji, dann an den Anfang) und jeweils
   notieren, wo man landet – besonders, ob man im **Emoji** landet.
3. **🌐 lang drücken:** Erscheint die Liste, ist Paply wählbar?
4. **Verwerfen:** Diktieren, dann auf der Fläche **nach links wischen**. „Verworfen“, es kommt kein
   Text, die vorige Tastatur erscheint.
5. **Höhe:** Zwischen Apple-Tastatur und Paply hin und her. **Springt das Textfeld?** Flackert die
   Höhe beim Erscheinen (kurz falsch, dann richtig)?
6. **Querformat:** Paply quer – sieht es ordentlich aus, ist nichts abgeschnitten?
7. **Erstes Laden:** iPhone neu starten, entsperren, Notizen → 🌐 → Paply. Wie lange bis die
   grüne Fläche da ist?
8. **Haptik:** Beim ersten gesprochenen Wort ein leichter Tick? (Nur mit Vollzugriff möglich –
   ohne Vollzugriff nimmt Paply gar nicht auf.)
9. **Weg nach dem Sprechen:** Mit Paply einen Satz sagen und dann – ohne zu tippen – mit 🌐 weiterschalten
   oder die App wechseln. Es wird nichts eingesetzt. Beim nächsten 🌐 → Paply erscheint einmal
   **„Wartender Text“** mit „Einsetzen“ bzw. „Neu sprechen“. Nimmst du ihn nicht, ist er beim
   übernächsten Mal weg (er steht aber im Verlauf der App).
10. **Wischen genau prüfen:** schräg nach links, langsam nach links, nach rechts, senkrecht. Nur
    deutlich nach links verwirft; alles andere federt zurück und setzt **nichts** ein. Ein Tipp
    ohne Bewegung beendet.

**Messwerte**

| Was | Zeile | Werte |
| --- | --- | --- |
| Erscheinen / Verschwinden | `kb.appear`, `kb.disappear` | `n`, `visibleMs`, `state`, `memMB`, `memFreeMB` |
| Kurz durchgeschaltet | `kb.discard.disappear` (Tastatur), `dictation.cancel` (App) | `speech=false`, `reason=keyboard` |
| Rücksprung | `kb.advance` | `reason` |
| Höhe gesetzt | `kb.height` | `target`, `measured` |
| Start-Flackern | `kb.layout` | Folge von `h` mit `sinceAppearMs` |
| Höhen der Testseite | `height.frame`, `height.measure` | `h`, `kind`, `mode` |
| Erstes Laden | `kb.load`, `kb.firstFrame` | `sinceProcessStartMs`, `sinceAppearMs` |
| Mikro bestätigt | `kb.recording` | `appearToRecordingMs` |
| Haptik | `kb.speech` | `fullAccess` |
| Verwerfen per Wischen | `kb.discard.swipe` | `state`, `speech` |
| Weg nach Sprache | `kb.disappear.defer` (Tastatur), `dictation.deferred` (App) | `id`, `textLen` |
| Wartender Text | `kb.pending.offer`, `kb.pending.dropped`, `kb.pending.skipped` | `len` |
| Warten auf die App | `kb.ack.missing` | `stage` (`first`, `noPong`, `slow`), `pong` |

---

## 5. Schnelltaste im Hintergrund

**Einrichten**

- **Rückseite:** Kurzbefehle-App → „+“ → Aktion „Paply-Diktat an/aus“ hinzufügen, sichern.
  Dann Einstellungen → Bedienungshilfen → Tippen → Auf Rückseite tippen → Doppeltippen → diesen Kurzbefehl.
- **Kontrollzentrum:** Kontrollzentrum öffnen → „+“ (oben links) → Steuerelement hinzufügen → „Paply-Diktat“.

**Schritte**

1. **Sitzung läuft**, Safari ist offen. Rückseite 2× tippen.
   Erscheint oben in der Dynamic Island die Paply-Marke mit Zeit? Sprechen. Rückseite 2× tippen.
   „Poliere …“, dann „In der Zwischenablage“.
2. Notizen öffnen, lange tippen → „Einsetzen“: Ist der Text da?
3. Neue Notiz, 🌐 → Paply: Zeigt Paply einmal „Wartender Text – Einsetzen“? Ein Tipp setzt ein.
4. Dasselbe mit dem **Kontrollzentrum-Knopf**.
5. **Ohne Sitzung** (App weggewischt): Rückseite 2× tippen. Was passiert? Fehlermeldung, Paply
   öffnet sich, oder nimmt es trotzdem auf?
6. **Während eines Tastatur-Diktats:** In Notizen mit Paply aufnehmen und dabei Rückseite 2× tippen.
   Erwartet: Meldung „In der Tastatur läuft gerade ein Diktat“, das Tastatur-Diktat läuft ungestört weiter.
7. **Im Zustand „unterbrochen“:** Einen Anruf annehmen und beenden (danach steht in der App ggf.
   „Unterbrochen“), dann Rückseite 2× tippen. Startet das Mikro wieder, kommt eine Meldung, oder
   öffnet sich Paply?
8. Optional: bei gesperrtem Bildschirm.

**Messwerte**

| Was | Zeile | Werte |
| --- | --- | --- |
| **In welchem Prozess** | `intent.perform` | `process`: `app` = App, `wg` = Widget-Erweiterung |
| Weiterleitung aus der Erweiterung | `intent.forward.ack` / `intent.forward.timeout` | `outcome`, `ms` |
| Ergebnis | `intent.outcome`, `shortcut.toggle` | `outcome`, `status`, `app` |
| Live Activity | `activity.start` / `activity.start.failed` / `activity.end` | `code` |
| Mikro im Hintergrund starten | `session.start` / `session.start.failed` | `stage`, `code`, `fourCC` |
| App nach vorne holen | `intent.foreground.request` | `reason` |
| Zwischenablage | `shortcut.deliver` | `clipboard`, `textLen` |

---

## 6. Zusatztests

### Rückgängig nach dem Einsetzen
Nach dem Einsetzen in Notizen: **mit drei Fingern nach links wischen** (bzw. iPhone schütteln →
„Rückgängig“). Verschwindet der eingesetzte Text in einem Schritt? Das Gleiche in Mail und WhatsApp.

### Musik und AirPods im Leerlauf
Paply nutzt Bluetooth bewusst nur für die Ausgabe (A2DP) und nimmt immer mit dem iPhone-Mikro auf.
Grund: Würde Paply das AirPods-Mikro nutzen, schaltet iOS die AirPods den ganzen Tag auf
Telefonqualität. Das prüfen wir:

1. AirPods verbinden, Musik starten, dann Sitzung starten. **Klingt die Musik genauso gut wie vorher?**
   (Nicht dumpf, nicht leiser.)
2. Mit AirPods diktieren: Wird es verstanden, wenn das iPhone in der Hand bzw. auf dem Tisch liegt?
3. Ohne Kopfhörer: Musik über den Lautsprecher – normale Lautstärke (nicht leise aus der Hörmuschel)?
4. Telefonat mit AirPods, während die Sitzung läuft – danach wieder diktieren.

Messwerte: `audio.route` – `in` sollte `MicrophoneBuiltIn` sein, `out` bei AirPods `BluetoothA2DPOutput`.
`session.start` – `otherAudio=true`, wenn Musik lief.

### Experiment: Mikro im Leerlauf pausieren

Hintergrund: Ist eine andere App vorne, zeigt iOS bei laufender Aufnahme in der Dynamic Island ein
breites Mikro-Symbol, nicht nur den Punkt. Das Experiment hält die Aufnahme im Leerlauf an (die
Sitzung bleibt aktiv) und startet sie erst beim nächsten 🌐 wieder – dann ohne Vorlauf.

1. Zahnrad → Labor → **„Mikro im Leerlauf pausieren (Experiment)“** an. Art zuerst **engine.pause()**.
2. Sitzung starten, dann zu Notizen wechseln (Paply geht in den Hintergrund).
   **Beobachten:** Verschwindet das Mikro-Symbol in der Dynamic Island? Bleibt der orange Punkt?
   (Ein paar Sekunden warten.)
3. Nach 1 Minute in Notizen 🌐 → Paply. **Klappt die Aufnahme?** Wie lange, bis die Zeit läuft?
   Sofort einen Satz sagen – fehlt der Anfang?
4. Nach 5 Minuten und nach 30 Minuten Leerlauf wiederholen (ob die App inzwischen ausgesetzt wurde).
5. Dasselbe mit Art **engine.stop()**.
6. Danach den Schalter wieder **aus**.

Erwartbar: Ohne laufende Aufnahme setzt iOS die App nach einiger Zeit aus. Dann antwortet sie nicht
auf 🌐, und die Tastatur öffnet Paply wie ohne Sitzung (Variante A). Genau das soll der Test zeigen.

Protokoll: `session.idlePause` (`mode`, `reason`), `session.resumeFromPause` (`ok`, `startMs` = Engine
läuft, `firstSampleMs` = erstes Audio, bei Fehler `code`/`fourCC`), `kb.recording`
(`appearToRecordingMs`), `kb.ack.missing` (App antwortete nicht), `app.wasSuspended` (`gapS` = wie
lange die App ausgesetzt war).

### Tastaturtöne und Haptik der Apple-Tastatur
Während die Sitzung läuft: Spürst du beim Tippen auf der Apple-Tastatur weiter die Haptik bzw. hörst
du die Klicks?

---

## 7. Ergebnisse notieren

| Test | iOS | Beobachtung | OK? |
| --- | --- | --- | --- |
| 1 Sitzung ganzer Tag (Akku morgens → abends) | 18.0 | | |
| 1 Anruf angenommen | | | |
| 1 Siri | | | |
| 1 nur oranger Punkt | | | |
| 2 Start aus Tastatur, Variante A | | | |
| 2 Variante B | | | |
| 2 ohne Vollzugriff | | | |
| 3 Latenz A/B/C/D (Gefühl) | | | |
| 4 Durchschalten (mit Sitzung) | | | |
| 4 Durchschalten (ohne Sitzung) | | | |
| 4 Weg nach Sprache → Wartender Text | | | |
| 4 Wischen schräg/langsam/rechts | | | |
| 4 Rücksprung / Emoji | | | |
| 4 Höhe / Flackern / quer | | | |
| 4 erstes Laden | | | |
| 4 Haptik | | | |
| 5 Rückseite mit Sitzung | | | |
| 5 Kontrollzentrum | | | |
| 5 ohne Sitzung | | | |
| 5 während Tastatur-Diktat | | | |
| 5 im Zustand „unterbrochen“ | | | |
| 1 App-Datenschutzbericht | | | |
| 6 Rückgängig | | | |
| 6 Musik / AirPods | | | |
| 6 Leerlauf pausieren: Mikro-Symbol weg? (pause / stop) | | | |
| 6 Leerlauf pausieren: Aufnahme nach 1 / 5 / 30 Min? | | | |
| 0.3 Schlüsselprüfung (auch Flugmodus) | | | |
| 3a Gemischte Sprachen (Englisch bleibt?) | | | |
| 0.5 Erstes Diktat: „poliert“, kein Polier-Fehler | | | |
| 3b Nichts verstanden (Stille / Lärm) | | | |
| 3c Strenge Polier-Prüfung an/aus | | | |
| 3d Erneut versuchen / verwerfen | | | |

Zum Schluss: Diagnose → Teilen → an den Koordinator. Oder er holt das Protokoll per Kabel
(`ios/scripts/pull-logs.sh`).
