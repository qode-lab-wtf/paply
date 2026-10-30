# Fix-Final · Paply Android 0.1.0 (1)
Basis: `2f9c649`; Fixes uncommitted, kein eigener Commit/Push. Parallel kam Doku-HEAD `eb1fa3c`.
Stand: 29.10.2026, 02:51 MEZ; Code fertig, Build/Tests ausstehend.

- 1: Inexakte Alarme beginnen bei fireAt; exakte Systemfreigabe nach Erinnern mit Erklärung.
- 2: Audio nach 30 Tagen: Diktat und Gedanken, lokal und unabhängig von Beta/Netz/Schlüssel.
  Start, Vordergrund und separater stündlicher Worker; aktive Aufnahmen/Neuversuche geschützt.
  Texte bleiben; fehlgeschlagene Löschungen werden erneut versucht.
- 3: Gesendeter Text mit unbekanntem Rücklesen bleibt im Verlauf; keine automatische Kopie.
  Panel: „Gesendet“. Kopie weiterhin bei fehlgeschlagenem Senden/Feldwechsel.
- 4: Nur eindeutig dauerhafte KeyVault-Fehler ersetzen den Alias; sonst ein Versuch zusätzlich.
  Wiederholte Fehler erhalten Ciphertext; dauerhafter Verlust wird gemeldet.
- 5: Verbrauchte thoughtId wird aus dem Intent entfernt, neuere Links bleiben erhalten.
- 7: Audio-400 bei FLAC: einmal WAV mit gleichem PCM/Modell/Sprache/Prompt; kein Retry-Loop.
- 8: CaptureBar und ImePanel verwenden Navigation-WindowInsets inklusive Verbrauch durch Eltern.
- Tests 1: ReminderPlanningTest, ReminderAccessTest; 2: HistoryStoreTest, AudioRetentionTest, FixGDeviceTest.
- Tests 3: ClipboardTest; 4: KeyVaultTest und angepasster KeyVaultDeviceTest.
- Tests 5: ThoughtLinkTest; 7: FlacFallbackTests; 8: NavigationInsetsDeviceTest.
  Insets: 0/24/48/80 px und bereits vom Elternlayout konsumierte Insets.
- Lokal: git diff --check grün. Kein Gradle auf dem Mac mini, keine Emulatoren benutzt.
- MacBook: 9 SSH-Prüfungen 02:27–02:51 MEZ im 3-Minuten-Takt, alle Timeout; kein Sync/Build.
- Nachholen: `PAPLY_WORK=final2 android/scripts/mb.sh sync`
- Dann: `PAPLY_WORK=final2 GRADLE_TASKS=":core:test :thoughts:test :app:testDebugUnitTest :app:assembleDebug :app:lintDebug :app:lintRelease" android/scripts/mb.sh build`
- Auch androidTest unkompiliert; zusätzlich `:app:compileDebugAndroidTestKotlin` nachholen, keine Emulatoren nutzen.
- Punkte 6/9 unberührt. Parallele Doku (E2E-FINAL, STAND, REGRESSION-DIKTAT) nicht bearbeitet.
