# Paply Notes – Opus-Nachprüfung Editor und Plancache (v5)

Stand: 26.10.2026, 20:55 · Prüfer: Claude Opus 5.5 (extra high) · Checkout `main`, Notes-Stand uncommitted.
Umfang: nur die Fixes zu N1/N2 und N3–N6 aus `OPUS-NACHPRUEFUNG.md` (v4). Keine neue Produkt-, Architektur- oder Designrunde.

Geprüfter Code: Kopie `/tmp/opus-notes-review/snap-v5/` (20:41). Der Code blieb während der Prüfung unverändert (Abgleich 20:50).
Das übergebene Paket `dist/notes-test/mac-arm64/paply.app` (`app.asar` SHA-256 `d5c07bc4…57122`) enthält die Main-Module
`queue/plan/commands/index/assets/capture.js` und `notes-preload.js` **byte-identisch**. Das Renderer-Bundle enthält dieselbe Speicherlogik.
Diese Prüfung gilt damit für genau dieses Paket.

## 0. Urteil

**Nachtrag 20:57:** Während ich den Bericht schrieb, hat Root N9, N10, N11 und P3 a im Arbeitsstand behoben.
Kopie dieses Stands: `/tmp/opus-notes-review/snap-v5-2056/`. Meine Nachprüfung steht in §6.

- **Arbeitsstand 20:56: lokale Test-App freigegeben.** Kein Blocker, kein Release.
  Bedingung: Das endgültige Paket wird aus genau diesem Stand gebaut, und die QA prüft die Stichprobe aus §5.
- **Paket `d5c07bc4…` von 20:42:** enthält N9 noch. Nur mit dem Hinweis aus §4 übergeben.
  Da Root ohnehin neu baut, ist das neue Paket vorzuziehen.

Die Abschnitte 0–5 beschreiben den Stand **20:41**, also das Paket `d5c07bc4…`:

**Die lokale Test-App ist freigegeben. Es gibt keinen Blocker. Ein Release ist nicht freigegeben.**

- **N1 ist behoben.** Das gilt für Fall A, A2, B, die Lease vor dem Request und das Rennen „Doppelklick trifft Planankunft“.
  Der Plan wird nie über einen offenen Editor gelegt. Ein unveränderter Editor kostet keinen zweiten Request.
  Ein blockierter Moment hält andere Momente nicht auf.
- **N2 ist behoben.** Eine lange Tabelle wird zu zwei Notizen, mit genau einem Request. Ein Commit-Fehler endet im Fallback.
  Bei einem Schreibfehler wird der gecachte Plan wiederverwendet.
- **N3, N4, N5 und N6 sind behoben.** Alle Reproskripte aus v4 sind jetzt negativ.
- **Neu ist N9 (P2).** Scheitert das Speichern dauerhaft, lässt sich der Editor nicht mehr verlassen.
  - Es geht nichts verloren, aber man sitzt fest.
  - Konkret auslösbar ist das über ein zweites Öffnen des Platzhalters während der Aufnahme oder über Text mit mehr als 20.000 Zeichen.
  - Ein gezielter Fix von ca. 6 Zeilen in `bodies.tsx` ist **vor dem endgültigen Paket empfohlen**.
  - Bleibt N9 offen, gehört der Hinweis aus §4 in `TESTEN.md`.
- **Neu sind N10 und N11 (P3).** Beide betreffen den Plancache, sind selten und kosten keine Tokens.

## 1. Was ich getan habe – und was nicht

**Gelesen:**

- Diff gegenüber meinem v4-Stand: `queue.js`, `plan.js`, `commands.js`, `index.js`, `assets.js`, `bodies.tsx`, `NotesApp.tsx`, `context.tsx`
- dazu `capture.js`, `contracts.js`, `notes-preload.js`, die neuen Regressionen in `core.test.js`
- `REVIEW-ANTWORTEN.md`, `EDITOR-QA.md`, `TESTEN.md`

**Ausgeführt:**

- `npx vitest run notes src/lib/notes`: **74/74 grün** (20:50)
- `npx tsc --noEmit`: Exit 0
- v4-Skripte `nachpruefung.cjs` erneut: alle Altbefunde negativ (Ergebnisse unten)
- neue Skripte `/tmp/opus-notes-review/v5.cjs` und `v5b.cjs`, mit echten Notes-Modulen, Fake-Groq, Temp-Ordnern, ohne Netz.
  Die Speicherlogik aus `bodies.tsx:15–32` ist dort zeilengenau gespiegelt (`renderSave`), die Lease aus `index.js:87–92` ebenso.
  `v5b.cjs` nutzt eine simulierte 1,5-s-Uhr, damit Busy-Backoff und Tick-Reihenfolge realistisch sind.
- Abgleich des Pakets: `app.asar` gegen den Arbeitsstand

**Nicht getan:**

- kein Electron gestartet, kein Groq-Aufruf, keine Keys gelesen
- keine App-Datei geändert, kein Build
- keine Gesamtsuite (Root meldet 603/603)
- Renderer nur im Code geprüft. Die GUI-Fälle A/A2/B/C hat die QA im Paket ausgeführt (`EDITOR-QA.md`). Meine Ergebnisse decken sich damit.

## 2. Nachprüfung N1–N6

| Befund | Ergebnis | Beleg |
|---|---|---|
| **N1 A**: Plan landet, während ein geänderter Entwurf offen ist | **behoben** | `v5 A`: Während der Plan landet, bleibt der Rohknoten, `transcribed`, `plan-0.json` liegt vor. Speichern ok, Text = Entwurf, `owner:user`, Entry `kept_user`, **1 Request**. |
| **N1 A2**: unverändert schließen | **behoben** | `v5 A2`: Entry `complete`, Rohknoten ersetzt, 2 KI-Karten, **1 Request**. Der Cache greift (`queue.js:107`). |
| **N1**: Lease vor dem Request | **behoben** | `v5b A3`: Moment wartet auf das Diktat, Editor öffnet, Diktat endet. **0 Requests**, solange der Editor offen ist, danach 1, Entry `complete`. |
| **N1**: Prüfung nach dem Request | **korrekt, ohne Fenster** | `queue.js:114–120`: Abbruchprüfung, `writeLocal`, `waitForEditor` und `commit` laufen synchron ohne `await` dazwischen. Ein IPC-Handler kann sich nicht dazwischenschieben. |
| **N1**: Doppelklick im Moment der Planankunft | **korrekt** | Bekommt die Lease den Vorrang, ist der Moment busy. Kommt der Plan zuerst, lehnt `index.js:89` die Lease ab und der Editor öffnet gar nicht (`NotesApp.tsx:99`). Ein Entwurf ist also nie möglich. Rest: Toast-Text, siehe P3. |
| **N1 B**: STT trifft auf offenen Platzhalter | **behoben** | `v5 B einmal`, 60 Sätze = 3 Teile: Karte = `Idee:\n\nSatz 0 zählt. …`, `owner:user`, Lease freigegeben, Entry `kept_user`, **60/60 Sätze sichtbar**, Board gültig. Teile 1–2 werden normal eingeordnet. |
| **N1 B3**: leeres STT bei offenem Editor | **behoben** | `v5b B3`: Speichern ok, `pending:false`, Text = Entwurf. Kosmetik siehe P3. |
| **N1**: andere Momente bei gehaltener Lease | **ok** | `v5b F`: Moment A bleibt `transcribed` mit `attempts:0`, Moment B wird `complete`. Mit Busy-Backoff 2 s und Tick 1,5 s kommt B dazwischen. |
| **N1**: Lease-Hygiene | **ok** | Senderprüfung über `handle(…,'board')`. Freigabe bei Crash, Navigation und `closed` (`index.js:70–72`). Wechsel laufen serialisiert (`NotesApp.tsx:95–100`). Kein Culling während des Editierens (`:187`). |
| **N2**: lange Tabelle | **behoben** | `v5 C`: zwei Notizen, `complete`, **1 Request**. v4-Skript „Tabelle >2000“: `complete`, `planCalls:1`. QA C ebenso. |
| **N2**: Commit-Validierung ⇒ Fallback | **behoben** | `v5 E`, erster Durchlauf: `fallback`, 1 Request. Schreibfehler ⇒ Cache wird wiederverwendet (Test `retains a cached plan…`). |
| **N3**: getippter Platzhalter ohne Sprache | **behoben** | v4-Skript: `entry=empty, pending:false`. |
| **N4**: Mindmap-Hub | **behoben** | v4-Skript „Discard Mindmap“: danach `[]`, 0 Kanten. Undo stellt 4 Knoten und 3 Kanten her (Test). Der Hub ist nie Bildträger (`plan.js:121`, die Items stehen in der Einfügereihenfolge vorn). |
| **N5a**: Drag während laufendem Plan | **behoben** | `v5 G` und v4-Skript: `kept_user`, `aiNodes:0`. |
| **N5b**: mehrteiliges „Erneut“ | **behoben** | v4-Skript: danach `complete`, 30/30 Satzreferenzen, alle eindeutig. |
| **N6**: Kante oder Anhang | **behoben** | `v5 G`: Owner nach Kante `ai, ai`. Anhang: `assets.js:36` setzt nur `pinned`. |
| **N7/N8** | dokumentiert | nicht erneut geprüft, außerhalb des Umfangs |

Auch die übrigen v4-Prüfungen sind weiter grün:

- B2 in allen fünf Varianten: 60/60 Sätze, Position erhalten
- Fallback-Retry ohne Wiederauferstehung
- `budget_small` endet endlich
- 429 bucht 0 Token ab

## 3. Neue Befunde

### N9 – P2 (gezielter Fix vor dem endgültigen Paket empfohlen): Nach dauerhaft scheiterndem Speichern lässt sich der Editor nicht verlassen

**Mechanik:**

- Seit N1 ruft jeder Ausweg zuerst `save()` auf und bricht bei `false` ab. Betroffen sind:
  - Escape, ⌘↩ und „Übernehmen“ (`bodies.tsx:40,48`)
  - Fokuswechsel und Fenster-Blur (`:42,:36`)
  - Klick auf die Fläche, Ziehen, Werkzeugwechsel, Doppelklick auf eine andere Notiz (alle über `setEditing`, `NotesApp.tsx:97`)
- `base` bleibt der Stand beim Öffnen (`bodies.tsx:14`). Ein Fehler, der beim nächsten Versuch gleich bleibt, kommt deshalb bei jedem Versuch wieder.
- Heraus kommt man nur, wenn man den Text exakt auf den Öffnungsstand zurücksetzt oder die Notiz entfernt.
- Die Lease bleibt so lange gehalten.
- Es geht nichts verloren: Der Entwurf bleibt sichtbar, das Original liegt im Eingang.
- Vorher ging in diesem Fall der Entwurf verloren. Jetzt bleibt er, aber der Editor lässt sich nicht schließen.

**Auslöser 1 – Platzhalter während der Aufnahme zweimal öffnen:**

1. Cmd+Y. Den Platzhalter doppelklicken, „Idee:“ tippen, „Übernehmen“. Die Karte ist jetzt `owner:user` und weiter `pending:true`.
2. Den Platzhalter erneut öffnen und weitertippen.
3. Mit Cmd+Y stoppen, der Editor bleibt offen. Das Transkript kommt an: `queue.js:53` fügt es an und erhöht `rev`.
4. „Übernehmen“ ⇒ „Die Notiz hat sich geändert. Bitte erneut bearbeiten.“ Bei jedem weiteren Versuch, Escape oder Klick daneben passiert dasselbe.

Ursache: `bodies.tsx:25` erkennt das eingetroffene Transkript nur bei `n.owner !== 'user'`. Nach Schritt 1 gehört die Karte aber
schon dem Nutzer. Deshalb wird mit der veralteten Öffnungsrevision gespeichert.

`v5 B erneut geöffnet`:

```
save1/save2 = "Die Notiz hat sich geändert. Bitte erneut bearbeiten." · leaseStillHeld:true
```

Auf der Karte steht `Idee:\n\nSatz 0 …`. Das Transkript ist sicher, nur der zweite Entwurf hängt fest.

**Auslöser 2 – Feldgrenzen:**

- Text mit mehr als 20.000 Zeichen im Editor, zum Beispiel per ⌘V in die Textarea (`contracts.js:10,50`)
- Spaltenkopf oder Kriterium mit mehr als 100 Zeichen, Zelle mit mehr als 2.000 Zeichen (`contracts.js:58`)

Die Felder haben kein `maxLength` (`bodies.tsx:44`). `v5b H`: beide Fälle ergeben `Ungültige Notes-Daten`, danach dieselbe Falle.

**Minimalfix, nur `bodies.tsx`:**

1. Zeile 25: die Bedingung `n.owner !== 'user'` streichen. Beim Zusammenführen nur den neuen Teil anhängen, damit „Idee:“ nicht doppelt erscheint:
   ```ts
   const arrived = original.pending && !n.pending && n.text !== original.text;
   const prefix = original.text.trim(), added = arrived && n.text.startsWith(prefix) ? n.text.slice(prefix.length).trim() : n.text;
   // text: arrived ? [draft.trim(), added].filter(Boolean).join('\n\n') : draft
   ```
   Im heutigen Normalfall B ist `original.text` leer. Das Ergebnis bleibt dann identisch.
2. `maxLength`: Textarea 20.000, Spalten und Kriterien 100, Zellen 2.000.
3. Sicherheitsnetz, eine der beiden Varianten:
   - Bei einem Revisionskonflikt `base.current = structuredClone(n)` setzen. Dann speichert das zweite „Übernehmen“ den Entwurf. Das entspricht „Nutzeredits haben Vorrang“.
   - Oder nach einem gescheiterten Speichern das nächste Escape schließen lassen und den Entwurf vorher per `notes:copy` sichern.

**Nachweis nach dem Fix:**

- `v5.cjs` „B erneut geöffnet“ ⇒ `save1 ok`, Text = `Idee: und noch etwas\n\nSatz 0 …` ohne doppeltes „Idee:“
- GUI-Stichprobe der QA: Fall B mit zweitem Öffnen vor dem Stopp, dazu B und A als Regression

### N10 – P3: Gecachter Plan wird gegen neueren Kontext erneut validiert und kann dauerhaft scheitern

- `queue.js:107–108` schickt auch den gecachten Plan erneut durch `validatePlan`, und zwar mit dem **aktuellen** Kontext.
- `context()` kürzt auf 20 Themen (`plan.js:40`).
- Verweist der Plan auf ein vorhandenes Thema, das während der Editor-Wartezeit aus den Top 20 fällt, wirft `plan.js:51`.
  Dann folgen `largeFallback`, derselbe Cache und schließlich `fallback`.
- „Erneut“ nimmt wieder denselben Cache und landet wieder im `fallback`.
- Die Rohkarte bleibt dauerhaft roh, ohne weiteren Request.

`v5 D`: 25 Themen, der Plan verweist auf `t_24`. Während der Editor offen ist, entstehen 10 passendere Notizen.

```
nachSchliessen: fallback · nachErneut: fallback · calls: 1
```

Gegenprobe `v5c.cjs`, direkt gegen `validatePlan`: `t24InBefore:true`, `t24InAfter:false`, die Revalidierung wirft `Ungültige Notes-Daten`.

- **Bedingung:** mehr als 20 Themen und eine Kontextverschiebung, während die Rohkarte im Editor offen ist. Selten.
- **Fix (1 Zeile):** den gecachten Plan nicht erneut validieren:
  `plan = cached?.rawRev === rawRev ? cached.plan : validatePlan(await groq.plan(…), ctx)`.
  Er wurde vor dem Schreiben bereits validiert. `applyPlan` verkraftet ein fehlendes Thema (`plan.js:98`) und fehlende
  Relationsenden (`:119`) schon heute.

### N11 – P3: „Erneut“ nach einem Darstellungs-Fallback fragt nie neu an

- `retry()` (`queue.js:180`) löscht `plan-*.json` nicht.
- Scheitert die Commit-Validierung deterministisch, wiederholt „Erneut“ dieselbe Projektion.
- `v5 E`: `fallback` → Erneut → `fallback`, `calls:1`.
- Mit dem N2-Fix ist kein Auslöser mehr bekannt. Dieser Pfad ist ein reines Sicherheitsnetz.
- **Fix:** `retry()` löscht für Fallback-Einträge die `plan-*.json`. Zusammen mit N10 umsetzen.

### P3 – Kleinigkeiten

| # | Befund | Stelle | Fix |
|---|---|---|---|
| a | **Toast beim Lease-Rennen:** Landet der Plan im selben Moment wie der Doppelklick, öffnet der Editor korrekt nicht. Der Toast zeigt aber den Rohtext `Error: Error invoking remote method 'notes:editing': Error: Diese Notiz wurde bereits eingeordnet.` Die Regex in `:67` erwartet kein führendes `Error: `. | `NotesApp.tsx:100` (gleich `:108`) | `notify(e instanceof Error ? e.message : String(e))` |
| b | **Widersprüchliches Label:** Wird ein Platzhaltertext erst nach leerem STT gespeichert, steht über dem eigenen Text weiter „Keine Sprache erkannt“. | `v5b B3`, `queue.js:59` | Beim Nutzer-Speichern ein Systemlabel zurücksetzen, oder hinnehmen. |
| c | **Broadcasts beim Tippen:** Solange eine Lease einen Rohknoten blockiert, nimmt die Queue den Moment etwa alle 3 s erneut. Jedes Mal sendet sie einen vollen Snapshot, und alle Bodies rendern neu. Bei 60 Notizen unkritisch. Nur auf großen Boards beobachten. | `queue.js:152` → `save` → `index.js` `changed()` | später: beim Busy-Rückfall nur `retryAt` speichern, ohne Broadcast |

## 4. Für Allans Testnotiz (`TESTEN.md`)

**Nur nötig, solange N9 offen ist:**

- Den Platzhalter während einer laufenden Aufnahme höchstens einmal bearbeiten. Oder den Editor schließen, bevor du mit Cmd+Y stoppst.
- Keine Texte über 20.000 Zeichen in eine einzelne Notiz einfügen. Tabellenköpfe kurz halten.
- Meldet ein offener Editor immer wieder „Die Notiz hat sich geändert“ oder „Ungültige Notes-Daten“, so kommst du heraus:
  1. Den Entwurf kopieren (⌘A, ⌘C).
  2. Die Notiz über den Papierkorb im Kontextmenü entfernen.
  3. Mit ⌘Z zurückholen. Der Editor öffnet dann mit dem aktuellen Stand.
  4. Den Entwurf einfügen.

**Unabhängig von N9:**

- Ein Wechsel in eine andere App (⌘Tab) speichert und schließt den offenen Editor. Die QA konnte den nativen Fenster-Blur nicht
  auslösen. Bitte einmal von Hand prüfen. Bleibt der Editor dabei offen, ist das harmlos: Der eine Moment wartet dann, bis der Editor geschlossen ist.
- Eine Rohkarte, die korrigiert wird, während die KI sie gerade einordnet, bleibt bewusst als Rohnotiz stehen. Der Eingang zeigt
  „Deine Bearbeitung bleibt“. Eine Aktion „Einordnen“ gibt es in v1 nicht.

## 5. Für Root

- Paket `d5c07bc4…57122` ist durch diese Prüfung abgedeckt und darf so als lokale Test-App übergeben werden.
- **Wird N9 behoben:**
  - Der Diff bleibt auf `bodies.tsx` beschränkt.
  - Dazu eine Unit- oder Renderer-Regression für „B erneut geöffnet“.
  - Die QA prüft als Stichprobe B mit zweitem Öffnen sowie B und A als Regression.
  - Hash in `EDITOR-QA.md` aktualisieren.
  - Eine weitere Opus-Runde ist dafür nicht nötig.
- **N10/N11 und P3 a–c** können warten. Sie kosten keine Tokens und verlieren nichts.
- **Vor einem Release** bleibt: der echte Squirrel-Neustart (N7) sowie physische Hotkeys, Mikrofon und Berechtigungsdialoge.

## 6. Nachtrag: Roots Fixes von 20:53–20:56, nachgeprüft

Geänderte Dateien:

- `src/lib/notes/editor.ts` (neu: `textEdit`) und `editor.test.ts`
- `bodies.tsx`: Konfliktbestätigung und `maxLength`
- `queue.js`: Kontext des Plancaches, `retry()` löscht den Cache
- `NotesApp.tsx:100`: Toast
- neue Regressionen in `core.test.js`

**Ausgeführt am Stand 20:56:**

- `npx vitest run notes src/lib/notes`: **79/79 grün**
- `npx tsc --noEmit`: Exit 0
- `v5d.cjs` nutzt die **echte** `textEdit()`, per esbuild transpiliert, statt einer Spiegelung
- `v5e.cjs` prüft den Konfliktpfad
- `v5.cjs` erneut

| Befund | Ergebnis | Beleg |
|---|---|---|
| **N9 Auslöser 1**: Platzhalter erneut geöffnet | **behoben** | `v5d B erneut geöffnet`: Speichern ok. Text = `Idee: und noch etwas\n\nSatz 0 …`, „Idee:“ genau einmal, 60/60 Sätze, Board gültig. Dasselbe mit Leerzeichen am Ende des ersten Entwurfs. `textEdit` erkennt das Transkript an `pending→false`, gleicher `sourceId` und mehr `sentenceIds`. Ein Präfix, das der Nutzer vorher gespeichert hat, wird abgeschnitten. |
| N9: Regression Normalfall B | **ok** | `v5d B einmal`: wie zuvor. `B leeres STT`: Entwurf bleibt, `pending:false`. |
| N9: Resize während des Editierens | **ok, neu abgedeckt** | `v5d B Resize während Edit`: Gleicher Text bei neuer Revision wird übernommen (`editor.ts:11`). Eine Geometrieänderung führt also nicht mehr zum Konflikt. |
| **N9 Auslöser 2**: Feldgrenzen | **behoben** | `maxLength` 100 für Spalten und Kriterien, 2.000 für Zellen. Die Textarea hat 20.000, bei einem wartenden Platzhalter 16.998, als Reserve für ein angehängtes Transkript bis 3.000 Zeichen. |
| N9: Ausweg bei echtem Konflikt | **ok** | Beim Konflikt wird `base` neu gesetzt und ein Hinweis gezeigt. Escape, Blur und Klick daneben lehnen danach still ab. „Übernehmen“ oder ⌘↩ speichert den Entwurf. `v5e`: Konflikt → Escape abgelehnt → Übernehmen → gespeichert. Für einen echten fremden Textwechsel ist kein Auslöser mehr bekannt. |
| **N10**: Revalidierung des Caches | **behoben** | `v5 D`: nach dem Schließen `complete`, `calls:1`. Root validiert gegen die IDs, die beim Request erlaubt waren (`queue.js:105–110,119`). Das ist sauberer als mein Vorschlag. |
| **N11**: „Erneut“ nach Fallback | **behoben** | `v5 E`: „Erneut“ fragt einmal neu an (`calls:2`). Mein Fehler-Wrapper ist absichtlich deterministisch, deshalb wieder `fallback`. `retry()` überschreibt `plan-*.json` nur bei Fallback-Einträgen, automatische Wiederholungen nutzen den Cache weiter. |
| **P3 a**: Toast | **behoben** | `NotesApp.tsx:100` nutzt `e.message`. Die vorhandene Regex in `:67` entfernt damit den IPC-Präfix. |
| A, A2, A3, C, G | unverändert grün | `v5`/`v5b` erneut ausgeführt |

**Restpunkte, alle P3, keiner blockiert:**

- **Zusätzlicher Klick im Konfliktfall:** `base.current = structuredClone(n)` (`bodies.tsx:33`) nutzt das `n` des Renders, in dem gespeichert wurde.
  War dieses `n` beim Konflikt noch alt, kommt beim ersten „Übernehmen“ ein zweiter Konflikt. Erst das nächste „Übernehmen“ speichert
  (`v5e` Schritt 1→3→4). Kein Festsitzen, nur ein zusätzlicher Klick. Außerdem gibt es dafür keinen bekannten Auslöser mehr.
  Später: auf den Board-Stand nach dem Neuladen setzen, zum Beispiel über einen Ref auf `board.nodes[id]`.
- **Sehr lange Bestandstexte:** Eine Notiz, die schon mehr als 20.000 Zeichen hat, lässt sich nur speichern, wenn sie kürzer wird.
  Das betrifft nur Sprachsätze ohne Satzzeichen über 20.000 Zeichen. `maxLength` kürzt vorhandenen Text nicht.
- **P3 b und c aus §3** bleiben offen. Kosmetik bzw. später beobachten.

**Für Root und QA, Stand 20:56:**

1. Endgültiges Paket aus genau diesem Stand bauen.
2. QA-Stichprobe:
   - B mit zweitem Öffnen vor dem Stopp: ein Text, „Idee:“ nur einmal
   - A und A2 als Regression: je genau 1 Planrequest
   - einmal einen Konflikt auslösen, dann „Übernehmen“: Editor schließt, Entwurf gespeichert
   - Text > 20.000 Zeichen per ⌘V in die Textarea: wird gekürzt, Speichern geht
3. Neuen Hash in `EDITOR-QA.md` eintragen.

Die Hinweise aus §4 zu N9 entfallen dann. Die zwei Punkte „Unabhängig von N9“ bleiben für `TESTEN.md` sinnvoll.
Eine weitere Opus-Runde ist nicht nötig.
