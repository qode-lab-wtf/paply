# Android 0.1.2 (3): Startabsturz auf älteren Android-Versionen

29.10.2026. Betroffenes reales Gerät laut Nutzer: Xiaomi Mi 9, Android 11 / MIUI 12.x.

## Ursache und Fix

Die unveränderte signierte Desktop-APK 0.1.1 hat SHA-256
`59d4862de38dbaf028014ceefbfa129b037b14a2833e90cf5c3404d078a9c522`.
Sie ist bytegleich mit `~/Android/work/v011/app/build/outputs/apk/release/app-release.apk`.
Reproduktion auf API 30 und 33, ohne Schlüssel und ohne erlaubte Laufzeitrechte:

```text
java.lang.NoSuchMethodError: No interface method toList()Ljava/util/List; in class Ljava/util/stream/Stream;
  at com.paply.thoughts.store.ThoughtStore.loadThoughts(ThoughtStore.kt:96)
  at com.paply.thoughts.store.ThoughtStore.ensureLoaded(ThoughtStore.kt:78)
  at com.paply.thoughts.store.ThoughtStore.recover(ThoughtStore.kt:698)
```

Übersetzt mit `retrace` und dem unveränderten `v011/.../mapping/release/mapping.txt`.
Der Fehler entsteht im JVM-Modul `thoughts`, das gegen den JDK gebaut wird. Der Hintergrundstart
fängt `Exception`, aber keinen `NoSuchMethodError`. Dieser beendet den Prozess.
Beide produktiven Java-Stream-`toList()`-Aufrufe (`ThoughtStore` und `Parallel.map`)
sind durch `collect(Collectors.toList())` ersetzt. Kotlin-Collection-`toList()` bleibt unverändert.

## Fehlerbericht

`PaplyApplication.attachBaseContext` installiert früh einen Uncaught-Handler. Synchrone
Application-Initialisierungsfehler werden ebenfalls erfasst. Der Bericht enthält ausschließlich
Exception-Klassen, begrenzte Stackframes/Ursachenketten, App-Version, Hersteller/Modell und
Android-Version/API; keine Exception-Messages, unterdrückten Exceptions, Transkripte oder Schlüssel.
Die letzte Meldung liegt privat in `noBackupFilesDir` und ist von Backups ausgeschlossen.

Die nicht exportierte `StartupFailureActivity` läuft in `:recovery`, ohne Compose,
Paply-Repositories, Keystore oder WorkManager-Initialisierung. Der Teilen-Dialog übergibt nur
Klartext nach Tastendruck. „Erneut versuchen“ beendet einen eventuell teilweise initialisierten
Hauptprozess, entfernt den Bericht und startet neu. Ein fehlgeschlagener Haupt-Looper wird niemals
weiterbetrieben. Bei blockiertem sofortigem Start bleibt der Bericht für den nächsten App-Aufruf.
OS-Prozessabbruch, native Abstürze und Framework-Fehler vor `attachBaseContext` sind hierdurch
nicht abfangbar; eine absolute „nie schließen“-Garantie wäre technisch falsch.

## Prüfung

Alle Builds ausschließlich MacBook, `PAPLY_WORK=v012`; kein Groq-Aufruf, Commit oder Push.
Pflichtaufgaben: `:core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:lintRelease`.
`StartupFailureTest` prüft Datenschutz, zyklische Ursachen und LinkageErrors.
`StartupCompatibilityDeviceTest` führt Store-Recovery und Parallel.map auf Android 11 aus.
Der DUMP-geschützte, ausschließlich in Debug vorhandene Befehl `startup-failure-test` löst eine
ProviderException mit einem Datenschutz-Testmarker aus; der Marker darf nicht im Bericht auftauchen.

Reproduzierbare MacBook-Skripte: `scripts/startup-matrix.py`, `scripts/verify-startup-recovery.py`.
Belege: MacBook `~/Android/work/v012-evidence/`, Ablaufprotokolle `~/Android/logs/v01*-*.log`.
Die Matrix startet mit explizitem MAIN/LAUNCHER-Intent: `monkey` startete auf API 30 nicht zuverlässig.
Die Einrichtungskarte wird im Reiter Diktat geprüft; die App startet standardmäßig im Gedanken-Reiter.
Locale-Tests ändern die echte System-Locale mit anschließendem Neustart. GMS-Test deaktiviert
`com.google.android.gms` und aktiviert es danach wieder; er ersetzt keinen Huawei-/AOSP-Hardwaretest.

Echte MIUI-/Samsung-Hardware, OEM-Keystore und OEM-Paket-/Autostartregeln bleiben separat zu prüfen.
Auf dem Google-API-30-Emulator ist jedoch bereits ein konkreter, herstellerunabhängiger Startfehler bewiesen.
Ein erster API-37-Durchlauf zeigte einen Framework-NPE in
`ConfigurationController.updateLocaleListFromAppContext`, vor dem App-Code; separat gesichert als
`37-0.1.2-first-framework-failure.log`. Folgende Locale-/Dunkel-/GMS-/Update-Starts waren sauber.

## Abschlussergebnis

- Original 0.1.1: derselbe retracete Stream-Fehler auf API **29, 30, 31, 33**; Starts auf **34, 35, 36, 37** ohne diesen Fehler.
- 0.1.2: **48/48** abschließende Startfälle auf API **29, 30, 31, 33, 34, 35, 36, 37** ohne Paply-FATAL: frisch/ohne Rechte, Deutsch, Englisch, Dunkel, deaktiviertes GMS, Update über 0.1.1.
- Einrichtungskarte auf allen acht APIs explizit im Diktat-Reiter sichtbar. Der separate API-37-Frischstart wiederholt die vorher auffällige Prüfung erfolgreich, ohne Framework-FATAL.
- 848 Unit-Tests bestanden, keine Fehler; ein optionaler Core-Test wegen fehlender aufgezeichneter IME-WAV übersprungen. Debug-Build, signierter Release-Build und Release-Lint erfolgreich.
- API-30-Gerätetest bestanden; Fault-Injection bestätigt Fehlerseite, sanitisierten Bericht, echten Teilen-Dialog und erfolgreichen erneuten Start. Screenshot `30-recovery.png` visuell geprüft.
- Finale APK SHA-256: `a10c308b44f3949252a1469676ef62082794a7b5a77d296c3fea3a550b773410`.
- MacBook: `~/Desktop/Paply-Android/Paply-0.1.2.apk`, `.apk.sha256` und `Paply-0.1.2.zip`; APK-Signatur und ZIP geprüft. Die beiden 0.1.1-Dateien dort entfernt; ursprünglicher Build und Mapping unter `~/Android/work/v011` erhalten.
- Alle Emulatoren beendet, `adb devices` leer. Nur `android/` geändert, kein Commit oder Push, keine Groq-Aufrufe.
- Das Matrix-Skript für 36/35/33/31 wurde nach erfolgreichem API-31-Update absichtlich unterbrochen, um API 29 nicht doppelt zu testen; dessen komplette Matrix steht separat in `v012-matrix-29.log`.
