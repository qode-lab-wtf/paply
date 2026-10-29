# Fix-G · 29.10.2026
Basis `866a57f`; kein Commit/Push. MacBook `PAPLY_WORK=fixg`, ausschließlich `paply:5580`.
Belege: `/tmp/paply-android-fixg/`; zusätzliche WAV/Reports auf MacBook `~/Android/work/fixg/.local/evidence/`.

## Punkte 1–14
1. DeleteIntent postet sofort, Tick prüft alle 500 ms ID **und Tag**; Fehlschlag beendet/sichert.
   `CaptureSafetyTest`: verspäteter Android-Snapshot, abgelehntes Repost und begrenzte Bestätigung.
   API 37 verhindert echte Wisch-Entfernung auch ohne Live-Updates; Meldung blieb sichtbar. DeleteIntent instrumentiert.
2. `RetryableReady` speichert nur Erfolg; Discard-Journale einzeln, fehlerhafte Einträge werden isoliert.
   Retry/Parallel-Aufrufer sowie defekter Marker neben gesundem Marker: JVM/Robolectric grün.
3. IME-Poll bleibt 1 Hz; auch `isMicrophoneMute` benutzt diesen Takt. `CaptureSafetyTest`/`ImePolicyTest`.
4. `publish` unter Mutex und Store-Monitor; parallele Autoren/Publikationen: `FixGDeviceTest`.
5. `.tmp-trim-*` und alte `audio.trim.tmp`: App-Recovery und Publikation des `releaseAudio`-Changes räumen auf.
   `ThoughtPlatformTest` prüft beide Wege und den Erhalt kanonischen Audios bis zum dauerhaften Rohtext.
6. Kein Telefon-/VoIP-/Klingelmodus als Stummschaltung; nur Plattform-Stummflags. Echter Recorder im Klingelmodus getestet.
7. Beta aus sperrt Queue/Maintenance und cancelt laufende Verarbeitung/Hygiene; an weckt Wartendes.
   Device-Test plus echte Offline-Aufnahme: online bei Beta aus unverändert 1 Whisper/1 KI; nach an verarbeitet.
8. Retry-Wecker verwendet `hasPendingWork`, ohne `waitingKey`; WorkManager-Prüfung auf dem Gerät.
9. Foreground vor Widget-/Kachel-Zustand; direkte Assertion bei Veröffentlichung von `starting` im Device-Test.
10. 0 ms/Stille meldet „Nichts gespeichert“; Teilfehler mit PCM bleiben erhalten. JVM-Test.
11. WAV blockweise lesen, VAD-Messwerte separat; maximal 60 s PCM je Pipeline, sichere lange Stille weiterhin auslassen.
    Drei neue JVM-Tests: 600-s-WAV, begrenzte kontinuierliche Uploads, abgeschnittene Datei; alte Sprach-/Pausentests grün.
12. Nur „Verwerfen“ verlangt Authentifizierung. Robolectric und echtes gesperrtes Gerät: erst PIN löst Verwerfen aus.
    `discard-locked-state.txt`/`discard-unlocked.txt`; geschützte PIN-Oberfläche ergibt schwarzen Screenshot. Test-PIN entfernt.
13. Benachrichtigungsfreigabe 1 s gecacht; JVM-Test mit 1000 Zugriffen.
14. Widget-PendingIntent `FLAG_UPDATE_CURRENT`; alter PendingIntent bleibt nach Refresh gültig (Robolectric).
15. Unverändert: keine Umgehung von Lautlos/DND, keine Audiofokus-/Telefon-/Vibrationssperre.

## Abnahme
- Build, Debug/Test-APK, Lint und JVM: 292 Core (1 übersprungen), 429 Gedanken, 95 App; keine Fehler.
- 14 gezielte Device-Tests final bestanden, einschließlich Foreground-Reihenfolge und neuer Repost-Zeitmarke.
- Kachel → Karte → deutsches `say`/gRPC → Fertig → verarbeitet; kurze Tomaten-Aufnahme inhaltlich korrekt.
- Offen: Beta-Rohtext unvollständig („Für den kaufen“), Langprobe mit Wortfehlern; Audio/Transkripte zur Diagnose erhalten, keine Qualitätsfreigabe.
- Echte 600-s-Aufnahme automatisch beendet, 595,688 s/19 MB nach Randtrim erhalten und verarbeitet; zwei kurze Uploads, kein OOM.
  Sprache an beiden Enden erhalten; Warnung bei 9 Min. sichtbar. Gemessener Verarbeitungs-PSS maximal 118501 KB (Stichproben).
- Gesamt 4 Transkriptionen + 3 KI-Läufe; Budget eingehalten. Schlüssel ausschließlich via `set-test-key.py`.
- Zwei native Emulatorabbrüche (gRPC-Start, QEMU-Watchdog), kein App-FATAL in den gesicherten Logs; nur paply neu gestartet.
- Sechs vorhandene Quellen bytegleich, neun Gedanken `done`, keine Trimreste; Mikro frei, kein ThoughtService aktiv.
- Test-PIN entfernt, Beta/Netz/Live-Updates/Schlüssel zurückgestellt; `paply` am 29.10. um 01:55 CET gestoppt.
