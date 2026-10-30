# Endspurt 1 · Paply Android 0.1.0
29.10.2026 · Basis bba79e8; nur android/ geändert, kein Commit/Push.
## Build / Fix-Final
MacBook, PAPLY_WORK=final2; kein Gradle auf dem Mac mini.
Grün: :core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug,
:app:lintDebug :app:lintRelease sowie :app:compileDebugAndroidTestKotlin.
Finaler Gesamtbuild: BUILD SUCCESSFUL, 25 s; vorheriger Fixture-Gesamtlauf 1m46s.
Core: 297 Tests, 0 Fehler, 1 bestehender Skip (CapturedPauseEvidenceTest ohne externe Fixture).
Thoughts: 430 Tests; App: 115 Tests; jeweils 0 Fehler/Skips.
Fix-Final-Buildfehler: ShadowAlarmManager.setCanScheduleExactAlarms ist statisch;
ReminderAccessTest korrigiert. Endreview-Produktabsichten unverändert.
## Sample-Regression / Fixes
RegressionAudioTest: MockWebServer extrahiert WAVs aus jedem Multipart-Upload.
50 Kombinationen: synthetisch + beide Original-WAVs, 0/2/20 s Vorlauf,
320/3200 Samples, Chunking an/aus; beide WAVs zusätzlich 320 Samples/20 ms Echtzeittakt.
Jeder Caller-Block wird sofort überschrieben; unabhängige Quellpositionen via KMP.
Alle Uploads zusammen samplegenau: 0 fehlend/doppelt/verschoben, inklusive Anfang/Ende.
Normalfall erzwingt 3 Stücke; 300-ms-Stimmmarke schützt vor absichtlich ausgelassenem Stillenende.
Leiser Rest ohne Marke reproduzierte echten Altfehler: 41.440 Samples = 2.590 ms fehlten.
Fix: VAD-negativen Rest zusätzlich auf ≥90 ms zusammenhängende Periodizität prüfen,
Features bis −100 dBFS statt Verwerfen wegen normaler Energiegates; −72-dBFS-Test grün.
Stille insgesamt, Rausch-Nachlauf und Klick-Nachlauf bleiben ohne zusätzliche Uploads.
PCM16-WAVWriter übernimmt Shorts direkt; alle 65.536 PCM16-Werte samt Caller-Mutation getestet.
Debug-only-Schalter retain-pcm-on/off behält/löscht app-private debug-live.wav; Standard aus.
## Aufnahme / F1 und F2
Gleiche Quell-WAVs, gRPC MODE_REAL_TIME, AudioRecord→PCM-Mitschnitt; silenced=false, keine Readfehler.
Testname: Quelle 4.413,1875 ms, Aufnahme 13.760 ms (manuell später beendet), globaler Versatz +133,1875 ms.
Lang: Quelle 23.366,875 ms, Aufnahme 23.920 ms, globaler Versatz +218,9375 ms.
Lokale 20-ms-Sprachfenster mit Korrelation >0,99: 149/188 kurz, 930/1106 lang.
Erste 40–60 ms korrelieren schwach; spätere Versatzänderungen zeigen nicht sampletreuen Emulatorweg.
Letzte auswertbare Sprachfenster bei 4.360/23.320 ms erhalten (Korrelation 1,0).
Kein belegter Sprachverlust am Ende; schlecht korrelierende Fenster sind keine exakte Verlustdauer.
Lücken/Dehnung lassen sich mit diesen periodischen Sprachproben nicht eindeutig quantifizieren.
JVM-Puffer/Uploadverlust widerlegt; verändertes Signal besteht bereits im AudioRecord-Mitschnitt.
Historische F1/F2-Ursache bleibt ohne damaligen Mitschnitt offen; heutige Befunde beweisen
keinen damaligen Verlust ganzer Wörter durch Emulator oder App. Leiser-Rest-Fix erklärt keinen fehlenden Anfang.
## Echter Gegentest / Abschluss
paply:5580, Android 17: Testname-Satz vollständig korrekt im ersten Fremdfeld.
23-s-Satz vollständig korrekt im zweiten Feld, einschließlich Schluss „… schönen alten Film ansehen.“
Beide Male automatischer Gboard-Rückwechsel; je 1 gemeldeter Upload, kein FLAC-Fallback.
2 erfolgreiche Transkriptionen + 2 Polierläufe; Key ausschließlich via set-test-key.py zur Laufzeit.
Debug-Mitschnitt deaktiviert/gelöscht; ~/Android/emu-stop.sh bestätigt „paply ist beendet“.
Belege lokal /tmp/paply-endspurt/ (WAVs, Vergleichs-JSON, Felder, Screenshot, Logcat, Buildlogs);
remote ~/Android/work/final2/.local/endspurt/. Keine Stimmen/Keys im Repository.
Vergleich reproduzierbar mit scripts/compare-capture.py (NumPy/SciPy); Aufrufdetails README.
Keine Release-Freigabe aus dieser Runde; historische Ursache und genaue Capture-Lücken bleiben begrenzt belegbar.
