# Paply — Regeln

Hier steht, wie sich Paply verhält: auf Mac, Windows, iPhone und Android. Was welche App heute kann und was noch
nachkommt, steht in [`docs/STAND.md`](docs/STAND.md).

**So ändert man eine Regel:** Hier ändern, dann `node shared/regeln-pruefen.mjs` laufen lassen. Der Wächter zeigt,
welche App noch nachziehen muss. Fertig ist eine Änderung erst, wenn alle Apps sie erfüllen oder sie unten als
Ausnahme steht. Gemeinsame KI-Texte und Prüffälle liegen in `shared/`. Die Abläufe bleiben in jeder App in ihrer
eigenen Programmiersprache.

**Begriffe:** Die **Hauptsprache** wählt der Nutzer. Ohne Wahl gilt die Gerätesprache. Agenten und Profile ändern sie
nicht. **Eigene Sprachen** sind die Sprachen des Nutzers. Auf iPhone und Android kommen sie automatisch aus Gerät und
Tastaturen oder sind selbst gewählt, auf Mac und Windows sind es Hauptsprache, Systemsprachen und Englisch.

## 1. Sprache

Vorgabe von Allan (30.10.2026, geschärft am 31.10.2026):

- Paply übersetzt nie. Was gesprochen wird, steht in dieser Sprache da.
- Paply rechnet mit der Hauptsprache. Wird durchgehend eine andere Sprache gesprochen, schreibt Paply in dieser Sprache,
  auch wenn sie nicht zu den eigenen Sprachen gehört.
- Hauptsprache mit wenigen fremden Wörtern: Alles bleibt wie gesprochen.

So läuft es bei Diktat und Gedanken in allen Apps, bei Gesprächen auf dem iPhone und im Groq-Ausweichweg auf Mac und
Windows:

1. Jedes Stück geht ohne Sprachvorgabe an Whisper. Whisper erkennt die Sprache selbst.
2. Erwartet wird die Sprache des letzten Stücks derselben Aufnahme, das Text ergeben hat, sonst die Hauptsprache. Stimmt
   die Erkennung damit überein, ist das Stück fertig.
3. Stimmt sie nicht überein, folgt eine Gegenprobe, wenn höchstens `sprache.kurz_sekunden` gesprochen wurde oder die
   erkannte Sprache keine eigene Sprache ist: Dasselbe Stück läuft ein zweites Mal, diesmal mit der erwarteten Sprache.
   Die Gegenprobe wartet höchstens zweimal die Dauer der ersten Anfrage plus 5 Sekunden, maximal 60 Sekunden.
   Bei Zeitablauf bleibt das erste Ergebnis.
4. Ist der Text beider Läufe gleich, gilt die erwartete Sprache. Bei kurzen Stücken gewinnt die erkannte Sprache, wenn
   ihre Konfidenz um mindestens `sprache.abstand` besser ist. Bei langen Stücken gewinnt sie immer, außer die erwartete
   Sprache ist um mindestens `sprache.abstand` besser. Scheitert die Gegenprobe, dauert sie zu lange oder fehlt ein
   Konfidenzwert, bleibt das erste Ergebnis.

Konfidenz ist der Mittelwert von `avg_logprob` über alle Segmente, gewichtet mit der Segmentdauer. Prüffälle:
`shared/sprache/faelle.json`.

**Warum so:** Gibt man Whisper eine falsche Sprache vor, übersetzt es: Aus „On se voit ce soir.“ wurde „Wir sehen uns
heute Abend.“ Nur erkennen lassen reicht nicht, weil sehr kurze Stücke falsch erkannt werden und Whisper dann in die
andere Richtung übersetzt. Messung vom 31.10.2026: Bei echten Aufnahmen gab es ab 3 Sekunden keine Fehlerkennung
(0 von 21), bei 2 Sekunden eine von 15, darunter deutlich mehr. Gemessen wurde mit deutschen Aufnahmen und künstlichen
Stimmen in sechs Fremdsprachen, echte fremdsprachige Aufnahmen fehlen noch. Lange Stücke (5 bis 12 Sekunden, künstliche
Stimmen): Die Erkennung lag immer richtig. Die Vorgabe `de` übersetzte oder erfand Text, außer bei Englisch und einem
türkischen Satz, wo der Text gleich blieb.

## 2. Polieren

- Jedes Diktat wird poliert. Abschalten geht nur im Entwicklerbereich. Gedanken haben eine eigene KI (Regel 5),
  Gespräche werden nicht poliert.
- Der Rohtext von Whisper ist schon gut. Polieren macht nur wenig: Rechtschreibung, Satzzeichen, Füllwörter, klar
  gesprochene Selbstkorrekturen und eindeutige Hörfehler.
- Englische und eingedeutschte Wörter wie „gepolisht“ bleiben unverändert.
- Einen Begriff nur tauschen, wenn der Zusammenhang eindeutig ist.
- Lehnt das Sicherheitsnetz die Politur ab, bleibt der Rohtext. Fällt das Polieren aus, auch.
- Die Regeln für die KI bleiben knapp. KI-Text: `shared/polish/system-prompt.txt`, Prüffälle:
  `shared/polish/safety-cases.json`.

## 3. Stille

Das gilt für Diktat und Gedanken in allen Apps. Gespräche haben eigene, einfachere Prüfungen.

- Wurde nichts gesagt, schreibt Paply nichts und fragt Groq möglichst gar nicht erst.
- Typische Whisper-Erfindungen wie „Vielen Dank.“ werden bei Stille verworfen. Echt gesprochen bleiben sie stehen.
- Steht nur ein Untertitel-Rest wie „Amara.org“ da, fällt er immer weg.
- Alle Apps nutzen dieselbe Stille-Liste. Der Wächter vergleicht sie.

## 4. Eigene Begriffe

- Ein Begriff ersetzt nur ein ähnlich klingendes, sicher falsch gehörtes Wort.
- Paply fügt nie einen Begriff ein, der nicht gesprochen wurde.
- Begriffs-Gegenprobe bei Diktat und Gedanken: Klingt ein Teil des Textes nach einem eigenen Begriff, läuft das Stück ein
  zweites Mal mit dem Begriff im Vordergrund. Der Begriff zählt nur, wenn Whisper ihn dabei selbst hört: Die Konfidenz darf
  um höchstens `begriffe.abstand` schlechter sein, und nur der ähnlich klingende Teil ändert sich. Sonst bleibt das erste
  Ergebnis. Was die Stille-Regeln verwerfen, bekommt keine Gegenprobe. Prüffälle: `shared/begriffe/faelle.json`.
- Nur Klangtreffer lösen aus, keine unsicheren Segmente. Klangschlüssel unter drei Zeichen lösen nie aus.
- Zusätzlich darf der Schreibweisen-Abstand ohne Leer- und Kombinationszeichen höchstens die aufgerundete
  Begriffslänge mal `begriffe.schreibweise` betragen. Die Gegenprobe nennt höchstens drei Kandidaten jeweils zweimal.
- Das Klangfenster im ersten Text bestimmt den ersetzten Teil. Der Rest bleibt als Wortmenge mit Häufigkeiten erhalten,
  mit höchstens abgerundet Restwortzahl/10 fehlenden und neuen Wörtern. Direkt am Fenster darf zusätzlich ein Wort
  entfallen, wenn der Rest mindestens vier Wörter hat. Bei mehrfach gehörtem Begriff braucht der Rest mindestens drei Wörter.
- Messung vom 31.10.2026: Mit zehn typischen Begriffen betrifft das rund 14 % von Allans 1.374 echten Diktaten, mit kurzen
  Namen keines. Die Gegenprobe wurde bisher nur mit künstlicher Stimme geprüft.

## 5. Gedanken

- Aus einem gesprochenen Gedanken werden Titel, sauberer Text, Thema, Aufgaben und Verknüpfungen.
- Die KI erfindet nichts und übersetzt nichts. Nur ein neuer Themenname folgt der Gerätesprache.
- Aufgaben nur bei ausdrücklicher Absicht, höchstens 5, bei langen Gedanken mit mehreren Teilen bis zu 10. Verknüpfungen
  höchstens 3.
- Die KI ordnet nur diesen einen Gedanken ein, nie die ganze Ablage neu. Themen zusammenführen schlägt sie höchstens vor.
- Was der Nutzer selbst geändert hat, überschreibt die KI nie. Weicht die gesprochene Sprache von der Gerätesprache ab,
  gilt ein Titel nur, wenn er aus dem Gesagten stammt.
- Scheitert das Einordnen, bleibt der Originaltext. Es geht kein Gedanke verloren.
- Die Regel-Version wird nur am Gedanken vermerkt. Eine neue Version ordnet alte Gedanken nicht neu ein.

## 6. Gespräche

- Personen heißen Person 1, 2, 3, bis der Besitzer sicher erkannt oder per Tipp bestätigt ist. Erst dann landen seine
  Aufgaben im Reiter. Aufgaben anderer kommen nur per „Übernehmen“ dazu.
- Der Bericht folgt Regel 1: Liegt eine andere Sprache bei mindestens 80 % der Sprechzeit, steht er in dieser Sprache,
  sonst in der Hauptsprache. Zitate bleiben wörtlich.
- Alle Beteiligten müssen der Aufnahme zustimmen. Die App weist darauf hin.

## 7. Grenzen und Hinweise

- Grenzen nicht kürzen. Lieber ein einfacher sichtbarer Hinweis, zum Beispiel Banner oder Vibration.
- Erreicht eine Aufnahme ihre Grenze, wird alles Bisherige gesichert und normal verarbeitet.
- Kurz vor der Grenze kommt ein Hinweis: beim Gedanken eine Minute vorher, beim Gespräch fünf Minuten. Läuft ein Gedanke
  unbemerkt im Hintergrund von iPhone oder Android, erinnert Paply daran. Auf Mac und Windows zeigt die Pille die Zeit.

| Aufnahme | Mac, Windows | iPhone | Android |
| --- | --- | --- | --- |
| Diktat | Keine eigene Grenze, Groq nimmt 25 MB, das sind rund 27 Minuten | Keine Grenze | 10 Minuten |
| Gedanke | 30 Minuten | 10 Minuten | 10 Minuten |
| Gespräch | Keine Grenze | 4 Stunden Ton, 8 Stunden insgesamt | Noch nicht vorhanden |

## 8. Ton und Verlauf

- Ton bleibt nur, bis der Text sicher gespeichert ist. Das gilt für alle Apps und alle Funktionen.
- Scheitert die Verarbeitung, bleibt der Ton für den Neuversuch, höchstens 30 Tage ab dem Stopp. Das gilt auch für
  hängende Auswertungen, laufende Aufnahmen bleiben unberührt.
- Bleibt ein Gespräch auf Mac oder Windows trotz Ton ohne Text, gilt das als Fehler, der Ton bleibt ebenfalls.
- Ein leeres Ergebnis von Whisper gilt bei Gedanken auf iPhone und Android als „nichts gesagt“, Ton und Eintrag entfallen.
  Auf Mac und Windows muss das die Pegelmessung bestätigen, sonst bleibt der Ton.
- Nachhören gibt es nicht.

| Was | Mac, Windows | iPhone | Android |
| --- | --- | --- | --- |
| Verlauf Diktat | 90 Tage | 300 Einträge | 300 Einträge |
| Ton nach Fehler beim Diktat | 24 Stunden, auch bei lokal verworfener Stille | 10 Minuten im Speicher, nur Tastatur | 30 Tage |
| Gelöschte Gedanken | Rückgängig, solange die App läuft, der Originaltext bleibt auf dem Gerät | 30 Tage im Papierkorb | 30 Tage im Papierkorb |

## 9. Zustellung

- Text landet nie im falschen Feld. Geht das Einsetzen nicht sicher, wartet er in Verlauf oder Zwischenablage.
- In Passwortfeldern nimmt Paply auf iPhone und Android nicht auf. Mac und Windows können Passwortfelder nicht erkennen.
- Ein Diktat, das nichts enthält, erzeugt keinen Eintrag.

## 10. Vorrang

- Diktat geht vor. Solange ein Diktat läuft, wartet die Verarbeitung von Gedanken.
- Unterbricht ein Anruf oder eine andere Aufnahme einen Gedanken, wird er gesichert oder pausiert, nie verworfen.

## 11. Entwicklerbereich

- Jede App hat ihn. Er öffnet sich mit 5× Tippen auf die Version und lässt sich wieder ausblenden.
- Er enthält mindestens: Polieren an/aus, Whisper-Modell (`whisper-large-v3` oder `whisper-large-v3-turbo`) und Diagnose.
- Normale Nutzer brauchen ihn nie. Seine Einstellungen bleiben gespeichert, auch nach dem Ausblenden.
- Polieren an/aus wirkt aufs Diktat, das Whisper-Modell auf Diktat und Gedanken. Gespräche nutzen immer `whisper-large-v3`.

## 12. Kosten, Schlüssel und Daten

- Keine laufenden Kosten, keine Abos. Paply läuft mit den kostenlosen Kontingenten der Nutzer.
- Schlüssel kommen in die App-Einstellungen, nie ins Repository.
- Ton und Text gehen an Groq. Gemini kommt nur bei Gesprächen auf Mac und Windows dazu. Sonst verlassen Ton und Text das
  Gerät nicht. Eingeschalteter Bildschirmkontext schickt auf Mac und Windows Bilder an Groq.
- Diagnose enthält im Betrieb nie Diktat-Text. Tester-Namen, Geräte-IDs und Einladungslinks gehören nicht ins Repository.

## Werte

Diese Tabelle liest der Wächter direkt. Steht ein Wert in einer App anders, schlägt er an.

| Schlüssel | Wert | Bedeutung |
| --- | --- | --- |
| `sprache.kurz_sekunden` | `5` | Bis zu dieser Sprechzeit bekommt eine abweichende Erkennung eine Gegenprobe |
| `sprache.abstand` | `0.15` | So viel besser muss die Konfidenz der erkannten Sprache sein, damit sie gewinnt |
| `begriffe.abstand` | `0.05` | So viel schlechter darf die Konfidenz der Begriffs-Gegenprobe höchstens sein |
| `begriffe.schreibweise` | `0.6` | Größter Schreibweisen-Abstand als Anteil der Begriffslänge, darüber keine Gegenprobe |
| `diktat.whisper_modell` | `whisper-large-v3` | Standardmodell für Diktat |
| `polieren.modell` | `qwen/qwen3.8-27b` | Modell fürs Polieren |
| `polieren.ausweichmodell` | `openai/gpt-oss-120b` | Bei Limit oder fehlendem Modell |
| `stille.no_speech_prob` | `0.6` | Segment gilt ab hier als Stille, zusammen mit dem nächsten Wert |
| `stille.avg_logprob` | `-1.0` | Unter diesem Wert ist Whisper unsicher |
| `gedanken.modell` | `openai/gpt-oss-120b` | Einordnen von Gedanken |
| `gedanken.ausweichmodell` | `openai/gpt-oss-20b` | Falls das Hauptmodell ausfällt |
| `gedanken.regel_version` | `6` | Stand der KI-Regeln für Gedanken, wird nur am Gedanken vermerkt |
| `gedanken.grenze_sekunden` | `600` | Längste Gedanken-Aufnahme auf iPhone und Android |

## Ausnahmen

Hier weicht eine App heute von den Regeln ab. Der Wächter meldet es, wenn eine Ausnahme verschwindet, damit diese Liste
stimmt. **In Arbeit** wird gerade behoben, **Bewusst** bleibt so, **Nachzureichen** kommt später.

| Nr. | App | Abweichung | Folge | Status |
| --- | --- | --- | --- | --- |
| A8 | Android | „Gespräche“ fehlt | Android hat zwei von drei Funktionen | Nachzureichen, sobald das iPhone den Gerätetest bestanden hat |
| A9 | Mac, Windows | Gespräche laufen über Gemini, bei Ausfall über Groq ohne Sprecher. Sie heißen „Sprecher N“ und „Gegenstelle“, ohne Besitzer-Erkennung und Aufgaben-Reiter | Regeln 1, 3 und 6 gelten mit Gemini nur für den Bericht | Nachzureichen |
| A10 | Android | Gedanken verknüpfen nur über Wörter, das iPhone zusätzlich über Apples Sprachmodell | Etwas weniger Treffer. Android hat kein eingebautes Gegenstück | Bewusst |
| A11 | Mac, Windows | Eigene Agenten haben einen eigenen KI-Text, können übersetzen und umgehen das Sicherheitsnetz | Regeln 1 und 2 gelten dort nicht | Bewusst, der Nutzer stellt das selbst ein |
| A12 | Mac, Windows | Gedanken dürfen 30 statt 10 Minuten lang sein | Regel 7 | Bewusst, Grenzen werden nicht gekürzt |
| A14 | iPhone | Mit eingeschalteter Beta „Gespräche“ bewahrt das Stimmen-Lernen bis zu 10 Kopien von Gedanken-Ton bis zu 7 Tage auf | Regel 8 gilt dort nicht | Bewusst, nur in der Beta |
