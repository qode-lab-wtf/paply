# Gemeinsames Polieren

`system-prompt.txt` ist die **einzige Quelle** des System-Prompts. iOS, Android und
Desktop betten ihn ein und sichern die Byte-Gleichheit jeweils mit einem Test ab.
Änderungen nur hier vornehmen und anschließend in **allen drei Apps** übernehmen.
Der Desktop braucht die eingebettete Konstante, weil Electron nur `electron-menubar/` packt.
Die mobilen Einbettungen/Gleichheitstests müssen in ihren jeweiligen Branches mitgezogen werden;
dieser Desktop-Commit verändert keine anderen Worktrees.

`safety-cases.json` enthält ausschließlich künstliche, kurze Prüffälle aus den mobilen
Sicherheitsnetz-Tests und zusätzliche Regressionen. `expected` ist der Ablehnungsgrund
oder `null`; optional wählen `profile` und `strictEdits` das mobile Prüfprofil.
Desktop führt alle Fälle aus. Das Netz portiert `PolishSafetyNet`, `EditCheck`,
`TextAnalysis`, `Lexicon` sowie `SpokenNumbers` für das Gedanken-Profil.
Das Diktat-Profil bleibt Standard; bestehende Desktop-Profile coding/meeting/dictation
verwenden es weiterhin. Eigene Agenten behalten ihren bisherigen freien Vertrag.

`messages-swift.json` stammt aus Foundation/JSONEncoder (prettyPrinted, sortedKeys,
withoutEscapingSlashes), reproduzierbar mit:

```sh
swift shared/polish/generate-messages-fixture.swift > shared/polish/messages-swift.json
```

Bekannte gemeinsame Grenzen: Das Netz ist heuristisch, keine Bedeutungsprüfung.
Kurze Ersatzwörter können durchgehen (etwa isoliert „aussieht“ → „hat“ in einem langen
Satz); korrekt erhaltene Wiederholungen können als Einfügung gelten. Manche richtige
Grammatikänderungen überschreiten den erlaubten Wortabstand. Diese mobilen Regeln
werden hier bewusst nicht gelockert. „gepolisht“ → „gepolst“ wird als `replaced`
abgelehnt (Abstand 2, erlaubter Abstand 1); zusätzlich schützt die Prompt-Klausel
auch andere eingedeutschte Lehnwörter.
