# Paply — Regeln

Hier steht, wie sich Paply verhält: auf Mac, Windows, iPhone und Android. Was welche App heute kann und was noch
nachkommt, steht in [`docs/STAND.md`](docs/STAND.md).

**So ändert man eine Regel:** Hier ändern, dann `node shared/regeln-pruefen.mjs` laufen lassen. Der Wächter zeigt,
welche App noch nachziehen muss. Fertig ist eine Änderung erst, wenn alle Apps sie erfüllen oder sie unten als
Ausnahme steht. Gemeinsame KI-Texte und Prüffälle liegen in `shared/`. Die Abläufe bleiben in jeder App in ihrer
eigenen Programmiersprache.

**Begriffe:** Die **Hauptsprache** wählt der Nutzer. Ohne Wahl gilt die Gerätesprache. **Eigene Sprachen** sind die
Sprachen des Nutzers, automatisch aus Gerät und Tastaturen oder selbst gewählt.

## 1. Sprache

Vorgabe von Allan (30.10.2026, geschärft am 31.10.2026):

- Paply übersetzt nie. Was gesprochen wird, steht in dieser Sprache da.
- Paply rechnet mit der Hauptsprache. Wird durchgehend eine andere Sprache gesprochen, schreibt Paply in dieser Sprache,
  auch wenn sie nicht zu den eigenen Sprachen gehört.
- Hauptsprache mit wenigen fremden Wörtern: Alles bleibt wie gesprochen.

So läuft es in allen Apps, bei Diktat, Gedanken und Gesprächen:

1. Jedes Stück geht ohne Sprachvorgabe an Whisper. Whisper erkennt die Sprache selbst.
2. Erwartet wird die Sprache des vorherigen Stücks derselben Aufnahme, sonst die Hauptsprache. Stimmt die Erkennung
   damit überein, ist das Stück fertig.
3. Stimmt sie nicht überein, folgt eine Gegenprobe, wenn höchstens `sprache.kurz_sekunden` gesprochen wurde oder die
   erkannte Sprache keine eigene Sprache ist: Dasselbe Stück läuft ein zweites Mal, diesmal mit der erwarteten Sprache.
4. Die erkannte Sprache gewinnt, wenn ihre Konfidenz um mindestens `sprache.abstand` besser ist. Sonst gilt die erwartete
   Sprache. Scheitert die Gegenprobe oder fehlt ein Konfidenzwert, bleibt das erste Ergebnis.

Konfidenz ist der Mittelwert von `avg_logprob` über alle Segmente, gewichtet mit der Segmentdauer. Prüffälle:
`shared/sprache/faelle.json`.

**Warum so:** Gibt man Whisper eine falsche Sprache vor, übersetzt es: Aus „On se voit ce soir.“ wurde „Wir sehen uns
heute Abend.“ Nur erkennen lassen reicht nicht, weil sehr kurze Stücke falsch erkannt werden und Whisper dann in die
andere Richtung übersetzt. Messung vom 31.10.2026: Bei echten Aufnahmen gab es ab 3 Sekunden keine Fehlerkennung
(0 von 21), bei 2 Sekunden eine von 15, darunter deutlich mehr. Gemessen wurde mit deutschen Aufnahmen und künstlichen
Stimmen in sechs Fremdsprachen, echte fremdsprachige Aufnahmen fehlen noch.

## 2. Polieren

- Polieren ist immer an. Abschalten geht nur im Entwicklerbereich.
- Der Rohtext von Whisper ist schon gut. Polieren macht nur wenig: Rechtschreibung, Satzzeichen, Füllwörter, klar
  gesprochene Selbstkorrekturen und eindeutige Hörfehler.
- Englische und eingedeutschte Wörter wie „gepolisht“ bleiben unverändert.
- Einen Begriff nur tauschen, wenn der Zusammenhang eindeutig ist.
- Lehnt das Sicherheitsnetz die Politur ab, bleibt der Rohtext. Fällt das Polieren aus, auch.
- Die Regeln für die KI bleiben knapp. KI-Text: `shared/polish/system-prompt.txt`, Prüffälle:
  `shared/polish/safety-cases.json`.

## 3. Stille

- Wurde nichts gesagt, schreibt Paply nichts und fragt Groq möglichst gar nicht erst.
- Typische Whisper-Erfindungen wie „Vielen Dank.“ werden bei Stille verworfen. Echt gesprochen bleiben sie stehen.
- Untertitel-Reste wie „Amara.org“ fallen immer weg.
- Alle Apps nutzen dieselbe Stille-Liste.

## 4. Eigene Begriffe

- Ein Begriff ersetzt nur ein ähnlich klingendes, sicher falsch gehörtes Wort.
- Paply fügt nie einen Begriff ein, der nicht gesprochen wurde.
- Whisper und Polieren sehen die ersten 200 Zeichen der Liste.

## 5. Gedanken

- Aus einem gesprochenen Gedanken werden Titel, sauberer Text, Thema, Aufgaben und Verknüpfungen.
- Die KI erfindet nichts und übersetzt nichts. Nur ein neuer Themenname folgt der Gerätesprache.
- Aufgaben nur bei ausdrücklicher Absicht, höchstens 5. Verknüpfungen höchstens 3.
- Die KI ordnet nur diesen einen Gedanken ein, nie die ganze Ablage neu. Themen zusammenführen schlägt sie höchstens vor.
- Was der Nutzer selbst geändert hat, überschreibt die KI nie.
- Scheitert das Einordnen, bleibt der Originaltext. Es geht kein Gedanke verloren.
- Die Regel-Version wird nur am Gedanken vermerkt. Eine neue Version ordnet alte Gedanken nicht neu ein.

## 6. Gespräche

- Personen heißen Person 1, 2, 3, bis der Besitzer sicher erkannt oder per Tipp bestätigt ist. Erst dann landen seine
  Aufgaben im Reiter. Aufgaben anderer kommen nur per „Übernehmen“ dazu.
- Der Bericht folgt Regel 1: durchgehend andere Sprache in dieser Sprache, sonst in der Hauptsprache. Zitate bleiben
  wörtlich.
- Alle Beteiligten müssen der Aufnahme zustimmen. Die App weist darauf hin.

## 7. Grenzen und Hinweise

- Grenzen nicht kürzen. Lieber ein einfacher sichtbarer Hinweis, zum Beispiel Banner oder Vibration.
- Erreicht eine Aufnahme ihre Grenze, wird alles Bisherige gesichert und normal verarbeitet.
- Eine Minute vor der Grenze kommt ein Hinweis. Läuft ein Gedanke unbemerkt, erinnert Paply daran.

| Aufnahme | Mac, Windows | iPhone | Android |
| --- | --- | --- | --- |
| Diktat | Keine Grenze, Groq nimmt bis 25 MB | Keine Grenze | 10 Minuten |
| Gedanke | 30 Minuten | 10 Minuten | 10 Minuten |
| Gespräch | Keine Grenze | 4 Stunden Ton, 8 Stunden insgesamt | Noch nicht vorhanden |

## 8. Ton und Verlauf

- Ton bleibt nur, bis der Text sicher gespeichert ist. Das gilt für alle Apps und alle Funktionen.
- Scheitert die Verarbeitung, bleibt der Ton für den Neuversuch, höchstens 30 Tage.
- Nachhören gibt es nicht.

| Was | Mac, Windows | iPhone | Android |
| --- | --- | --- | --- |
| Verlauf Diktat | 90 Tage | 300 Einträge | 300 Einträge |
| Ton nach Fehler beim Diktat | 24 Stunden | 10 Minuten | 30 Tage |
| Gelöschte Gedanken | Sofort | 30 Tage im Papierkorb | 30 Tage im Papierkorb |

## 9. Zustellung

- Text landet nie im falschen Feld. Geht das Einsetzen nicht sicher, wartet er in Verlauf oder Zwischenablage.
- In Passwortfeldern nimmt Paply nicht auf (Android-Tastatur und -Knopf; iPhone-Tastaturen sind dort von iOS gesperrt).
- Ein Diktat, das nichts enthält, erzeugt keinen Eintrag und keine Kosten.

## 10. Vorrang

- Diktat geht vor. Solange ein Diktat läuft, wartet die Verarbeitung von Gedanken.
- Unterbricht ein Anruf oder eine andere Aufnahme einen Gedanken, wird er gesichert oder pausiert, nie verworfen.

## 11. Entwicklerbereich

- Jede App hat ihn. Er öffnet sich mit 5× Tippen auf die Version und lässt sich wieder ausblenden.
- Er enthält mindestens: Polieren an/aus, Whisper-Modell (`whisper-large-v3` oder `whisper-large-v3-turbo`) und Diagnose.
- Normale Nutzer brauchen ihn nie. Was dort steht, ändert nur Testläufe, nicht die Regeln hier.

## 12. Kosten, Schlüssel und Daten

- Keine laufenden Kosten, keine Abos. Paply läuft mit den kostenlosen Kontingenten der Nutzer.
- Schlüssel kommen in die App-Einstellungen, nie ins Repository.
- Ton und Text gehen an Groq. Gemini kommt nur bei Gesprächen auf Mac und Windows dazu. Sonst verlässt nichts das Gerät.
- Diagnose enthält nie Diktat-Text. Tester-Namen, Geräte-IDs und Einladungslinks gehören nicht ins Repository.

## Werte

Diese Tabelle liest der Wächter direkt. Steht ein Wert in einer App anders, schlägt er an.

| Schlüssel | Wert | Bedeutung |
| --- | --- | --- |
| `sprache.kurz_sekunden` | `5` | Bis zu dieser Sprechzeit bekommt eine abweichende Erkennung eine Gegenprobe |
| `sprache.abstand` | `0.15` | So viel besser muss die Konfidenz der erkannten Sprache sein, damit sie gewinnt |
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
| A1 | Mac, Windows | Diktat und Gedanken schicken eine feste Sprache mit | Fremde Sprache kann übersetzt werden, Regel 1 gilt nicht | In Arbeit |
| A2 | Mac, Windows | Diktat und Gedanken nutzen Whisper `turbo` statt `large-v3` | Schwächer bei Sprachwechseln | In Arbeit |
| A3 | Mac, Windows | Stille-Liste hat 11 statt 62 Sätze, nur Deutsch und Englisch | „Merci.“ oder „Gracias.“ können bei Stille durchrutschen | In Arbeit |
| A4 | iPhone, Android | Kurze Stücke gehen mit fester Sprache raus, fremde Sprachen werden neu in der Hauptsprache geschrieben | Hier entsteht die Übersetzung, die Allan aufgefallen ist | In Arbeit |
| A5 | Mac, Windows | Gedanken nutzen eigene deutsche KI-Regeln ohne Aufgaben und Fälligkeiten | Regel 5 gilt nicht. Auf Allans MacBook (26./27.10.): von 19 Gedanken 4 sauber eingeordnet, 10 nicht eindeutig, 4 wegen Limit nur gesichert, 1 leer | In Arbeit |
| A6 | Mac, Windows | Polieren ist für neue Nutzer aus, der Schalter steht in den Einstellungen, es gibt keinen Entwicklerbereich | Regeln 2 und 11 gelten nicht | In Arbeit |
| A7 | Mac, Windows | Gespräche und Gedanken behalten den Ton 7 Tage, Gespräche haben Nachhören | Regel 8 gilt nicht | In Arbeit |
| A8 | Android | „Gespräche“ fehlt | Android hat zwei von drei Funktionen | Nachzureichen, sobald das iPhone den Gerätetest bestanden hat |
| A9 | Mac, Windows | Gespräche laufen über Gemini, heißen „Sprecher N“ und „Gegenstelle“, ohne Besitzer-Erkennung und Aufgaben-Reiter | Regel 6 gilt hier nur für den Bericht | Nachzureichen |
| A10 | Android | Gedanken verknüpfen nur über Wörter, das iPhone zusätzlich über Apples Sprachmodell | Etwas weniger Treffer. Android hat kein eingebautes Gegenstück | Bewusst |
| A11 | Mac, Windows | Eigene Agenten haben einen eigenen KI-Text, können übersetzen und umgehen das Sicherheitsnetz | Regeln 1 und 2 gelten dort nicht | Bewusst, der Nutzer stellt das selbst ein |
| A12 | Mac, Windows | Gedanken dürfen 30 statt 10 Minuten lang sein | Regel 7 | Bewusst, Grenzen werden nicht gekürzt |
