# Paply — Regeln

Hier steht, wie sich Paply verhält: auf Mac, Windows, iPhone und Android.

**So ändert man eine Regel:** Hier ändern, dann `node shared/regeln-pruefen.mjs` laufen lassen. Der Wächter zeigt,
welche App noch nachziehen muss. Fertig ist eine Änderung erst, wenn alle Apps sie erfüllen oder sie unten als
Ausnahme steht. Die Texte für die KI liegen in `shared/`, die Abläufe bleiben in jeder App in ihrer eigenen Sprache.

## 1. Sprache

Vorgabe von Allan (30.10.2026):

- Paply zielt immer auf die Hauptsprache.
- Wird durchgehend eine andere Sprache gesprochen, schreibt Paply in dieser Sprache.
- Hauptsprache mit wenigen fremden Wörtern: Alles bleibt wie gesprochen.
- Paply übersetzt nie.

Kurze Stücke gehen direkt in der Hauptsprache raus, weil die automatische Erkennung dort oft danebenliegt.

## 2. Polieren

- Der Rohtext von Whisper ist schon gut. Polieren macht nur wenig: Rechtschreibung, Satzzeichen, eindeutige Hörfehler.
- Englische und eingedeutschte Wörter wie „gepolisht“ bleiben unverändert.
- Einen Begriff nur tauschen, wenn der Zusammenhang eindeutig ist.
- Lehnt das Sicherheitsnetz die Politur ab, bleibt der Rohtext.
- Die Regeln für die KI bleiben knapp. KI-Text: `shared/polish/system-prompt.txt`, Prüffälle:
  `shared/polish/safety-cases.json`.

## 3. Stille

- Wurde nichts gesagt, schreibt Paply nichts und fragt Groq möglichst gar nicht erst.
- Typische Whisper-Erfindungen wie „Vielen Dank.“ werden bei Stille verworfen. Echt gesprochen bleiben sie stehen.

## 4. Eigene Begriffe

- Ein Begriff ersetzt nur ein ähnlich klingendes, sicher falsch gehörtes Wort.
- Paply fügt nie einen Begriff ein, der nicht gesprochen wurde.

## 5. Gedanken

- Aus einem gesprochenen Gedanken werden Titel, Thema, Aufgaben und Verknüpfungen.
- Die KI erfindet nichts und übersetzt nichts. Sie ordnet nur diesen einen Gedanken ein, nie die ganze Ablage neu.

## 6. Gespräche

- Personen heißen Person 1, 2, 3, bis der Besitzer sicher erkannt oder per Tipp bestätigt ist. Erst dann landen seine
  Aufgaben im Reiter.
- Der Ton wird nach fertiger Auswertung gelöscht.

## 7. Grenzen und Hinweise

- Grenzen nicht kürzen. Lieber ein einfacher sichtbarer Hinweis, zum Beispiel Banner oder Vibration.

## 8. Kosten und Schlüssel

- Keine laufenden Kosten, keine Abos.
- Schlüssel kommen in die App-Einstellungen, nie ins Repository.

## Werte

Diese Tabelle liest der Wächter direkt. Steht ein Wert in einer App anders, schlägt er an.

| Schlüssel | Wert | Bedeutung |
| --- | --- | --- |
| `sprache.kurz_sekunden` | `5` | Bis hierhin gesprochen: direkt in der Hauptsprache senden |
| `diktat.whisper_modell` | `whisper-large-v3` | Standardmodell für Diktat |
| `polieren.modell` | `qwen/qwen3.8-27b` | Modell fürs Polieren |
| `polieren.ausweichmodell` | `openai/gpt-oss-120b` | Bei Limit oder fehlendem Modell |
| `stille.no_speech_prob` | `0.6` | Segment gilt ab hier als Stille, zusammen mit dem nächsten Wert |
| `stille.avg_logprob` | `-1.0` | Unter diesem Wert ist Whisper unsicher |
| `gedanken.modell` | `openai/gpt-oss-120b` | Einordnen von Gedanken |
| `gedanken.ausweichmodell` | `openai/gpt-oss-20b` | Falls das Hauptmodell ausfällt |
| `gedanken.regel_version` | `6` | Stand der KI-Regeln für Gedanken |
| `gedanken.grenze_sekunden` | `600` | Länge einer Gedanken-Aufnahme |

## Ausnahmen

Hier weicht eine App heute von den Regeln ab. Der Wächter meldet es, wenn eine Ausnahme verschwindet, damit diese Liste
stimmt. **Offen** heißt: Allan entscheidet.

| Nr. | App | Abweichung | Folge | Status |
| --- | --- | --- | --- | --- |
| A1 | Mac, Windows | Sprache ist fest eingestellt (Standard Deutsch), Whisper bekommt kein Sprachwechsel-Beispiel | Englisch gesprochen wird in Deutsch gepresst, Regel 1 gilt nicht | Offen, betrifft Cmd+X |
| A2 | Mac, Windows | Whisper `turbo` statt `large-v3` | Messung vom 21.10.: `large-v3` nicht besser. Mobil ohne solche Messung | Offen, erst messen |
| A3 | Mac, Windows | Stille-Liste hat 11 statt 62 Sätze, nur Deutsch und Englisch | „Merci.“ oder „Gracias.“ können bei Stille durchrutschen | Offen, betrifft Cmd+X |
| A4 | iPhone, Android | Durchgehend fremde Sprache, die keine Nutzersprache ist, wird neu in der Hauptsprache geschrieben | Regel 1 gilt nur für eingestellte Sprachen. Schützt vor falscher Erkennung wie „ru“ | Offen |
| A5 | Mac, Windows | Notes nutzt eigene deutsche KI-Regeln, ohne Aufgaben und Verknüpfungen zu früheren Gedanken | Regel 5 gilt nicht. Auf Allans MacBook scheiterte die Einordnung bei 10 von 19 Gedanken | Offen |
| A6 | Mac, Windows | Polieren ist für neue Nutzer standardmäßig aus | Neue Nutzer bekommen nur den Rohtext | Offen, betrifft Cmd+X |
| A7 | Mac, Windows | Meeting behält den Ton 7 Tage | Allans Entscheidung vom 21.09., Regel 6 gilt nur fürs iPhone | Offen |
