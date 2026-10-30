# Android-API-29-Sicherheitsnetz

`:core` und `:thoughts` werden mit JDK 21 gebaut. `jvmTarget`/`--release 17`
schützen nicht vor Java-APIs, die auf Android 10 fehlen. Deshalb prüft Animal
Sniffer 2.0.1 den **Produktionsbytecode** beider JVM-Module mit der auf Maven
Central verfügbaren Signatur `com.toasttab.android:gummy-bears-api-29:0.14.0@signature`.
Keine Ignore-Liste, keine unterdrückenden Annotationen. Host-Tests werden nicht
gegen Android geprüft. `check` und beide `test`-Tasks führen `animalsnifferMain`
aus; `mb.sh build` führt beide Tests, App-Tests, Debug-APK und Release-Lint aus.
Auch `mb.sh release` erzwingt beide Bytecodeprüfungen und `lintRelease`.

Core-Library-Desugaring ist weiterhin **ausgeschaltet**: Für den einzigen Fund
reicht die kompatible Java-Alternative; eine zusätzliche Laufzeitbibliothek ist
nicht nötig. Die Signatur hat daher **keinen** `coreLib2`-Classifier. Gummy Bears
berücksichtigt normales D8-Language-Desugaring/Backports, z. B. `List.of`.
Sie behauptet also nicht, dass jede erlaubte Methode auf dem nackten API-29-JVM
existiert: Der Android-Build mit D8 ist Teil dieses Vertrags.

Quellen: [Signaturen](https://github.com/open-toast/gummy-bears),
[Animal-Sniffer-Plugin](https://github.com/xvik/gradle-animalsniffer-plugin).
Alle Gradle-Befehle ausschließlich auf dem MacBook ausführen:

```sh
PAPLY_WORK=v013 android/scripts/mb.sh sync
PAPLY_WORK=v013 android/scripts/mb.sh build
PAPLY_WORK=v013 android/scripts/mb.sh release
```

Negativkontrolle auf dem MacBook im synchronisierten Android-Verzeichnis:
`bash scripts/verify-api29-gate.sh`. Sie fügt vorübergehend inkompatiblen
Produktionscode ein und verlangt, dass **`:core:test`** mit allen sechs
Diagnosen scheitert: Stream.toList, InputStream.readNBytes, Optional.isEmpty,
Files.readString, Collectors.toUnmodifiableList, ArrayList.removeFirst.
Ein EXIT-Trap entfernt die Probe; danach regulären Build wiederholen.

Zusätzlich disassembliert `scripts/audit-release-api.py` alle `classes*.dex`
der fertig signierten APK mit SDK-`dexdump`. Tatsächliche `invoke-*`-Instruktionen
werden mit `api-versions.xml` (inklusive geerbter Methoden und Minor-APIs)
abgeglichen. Der Release-Ablauf legt `build/reports/release-api29.txt` an.
Das ist ein konservativer Reviewbericht: SDK-geschützte AndroidX-/Compose-Aufrufe
werden ebenfalls gemeldet; unbekannte Referenzen werden separat ausgewiesen.
Er ersetzt weder Kontrollflussanalyse noch Lint oder Gerätetests. Reflexion,
native Methoden und dynamisch geladener Code werden damit nicht bewiesen.

Fund am Ausgangsstand 114a31a: genau ein JVM-Verstoß, `WAVWriter.kt`:
`InputStream.readNBytes(int)` beim Lesen des WAV-Headers. Ersetzt durch
`DataInputStream.readFully(byte[])`; EOF/IO-Fehler liefern unverändert `null`.
Ein Regressionstest prüft alle Headerlängen 0–43, gültigen/ungültigen Header
und fehlende Datei. Kotlin `repeat`/`isBlank` usw. erzeugen hier keine verbotenen
Java-Aufrufe. Release-Version deshalb 0.1.3 (4).

## Prüfung am 29.10.2026

- MacBook `PAPLY_WORK=v013`: sync, vollständiger build und signierter release
  erfolgreich. 850 Tests, 0 Fehler, 1 optionaler WAV-Fixture-Test übersprungen.
- Negativkontrolle: alle sechs inkompatiblen Aufrufe über `:core:test` abgewiesen;
  Probe entfernt und regulären Build anschließend erfolgreich wiederholt.
- `lint-results-release.xml`: 0 NewApi, 71 sonstige Warnungen, kein Buildfehler.
- Release-DEX: 1 DEX, 3233 unterschiedliche Plattformmethoden, 171 Referenzen auf
  neuere Android-APIs, **keine** neueren `java`/`javax`-Aufrufe, 0 unbekannte
  Referenzen. Die Android-Referenzen umfassen SDK-geschützten App-/AndroidX-/Compose-
  Code; deren bloße Existenz ist kein Absturzbeweis. Lint und die Geräteläufe
  ergänzen diesen Bericht, ersetzen aber keine vollständige Pfadanalyse.
- API 30 (`paplyfix30`) und API 37 (`paply3`): signiertes Update 0.1.2 → 0.1.3,
  Start/Einrichtung, je eine echte Kachel-Aufnahme mit gRPC-Audio und erfolgreicher
  Verarbeitung, je ein Diktat ins Kontakte-Textfeld, Landkarte, Aufgabe und
  platziertes Aufgaben-Widget geprüft. API 37 hatte zunächst eine inkompatibel
  signierte alte Debug-App; diese vor dem signierten 0.1.2→0.1.3-Test entfernt.
- API 30: Launcher hielt nach dem Update einen gelöschten APK-Pfad im Cache;
  Widget nach Launcher-Neustart korrekt. Keine Paply-FATAL-/LinkageErrors.
  Kurze synthetische Sprache auf API 30 ungenau erkannt; keine Wiederholung.
- Vier Sprachaufnahmen insgesamt (zwei Gedanken, zwei Diktate), keine manuell
  ausgelösten Wiederholungen. Zweimal Aufgabenstrukturierung erfolgreich.
- Belege: MacBook `~/Android/work/v013-evidence/`, DEX-Bericht zusätzlich unter
  `~/Android/work/v013/build/reports/release-api29.txt`.
- Abschluss: Alle MacBook-Emulatoren beendet, `adb devices` leer. Desktop-APK
  und ZIP bytegleich verifiziert, 0.1.2-Dateien entfernt, keine `.sha256` dort.
  Nur `android/` geändert, kein Commit oder Push; kein Gradle auf dem Mac mini.
