# E3 Teil R — Erinnerungen (29.10.2026)

Implementierung und Abnahme auf MacBook, `PAPLY_WORK=rem`, `paply3` / `emulator-5600`.
Keine Groq-Aufrufe, kein Commit/Push; iOS und Diktat nicht verändert.

## Anschluss für den UI-Helfer
- `ReminderInvitation(task: ThoughtTask, thought: Thought, modifier, onError)` in `ui/reminders/`.
  Alternative: `ReminderInvitation(task: ThoughtsRepository.TaskEntry, modifier, onError)`.
  Einmal für eine kommende Aufgabe mit Uhrzeit einbetten; „Nicht jetzt“ pausiert sieben Tage.
- In `PaplyApp`: `ReminderDeepLinkEffect(thoughtRepository) { thoughtID, taskID -> … }`.
  Callback öffnet den Gedanken und setzt `focusTask`; MainActivity nimmt kalte/warme Intents entgegen.
  Alternativ `repository.reminderDestination` lesen und `consumeReminderDestination(key)` aufrufen.
- Die Einbettung in `ui/thoughts/**` und `ui/PaplyApp.kt` gehört dem parallelen UI-Helfer.

## Umsetzung
- Unveränderter `:thoughts`-Plan: nur offene, künftige Aufgaben mit bestätigter Uhrzeit; Tagesangaben bleiben still.
- Explizite Einladung/Schalter nötig, selbst wenn Aufnahme-Mitteilungen schon erlaubt sind.
- AtomicFile unter `noBackupFilesDir/reminders/`: Einstellungen, Alarmjournal, Zustellstatus, „In 1 Stunde“.
- Eigener privater Kanal „Erinnerungen“, öffentliche Version „Paply-Erinnerung“ ohne Inhalt.
- „Erledigt“ setzt über Repository idempotent; „In 1 Stunde“ bleibt bei Neustart/Beta aus und an erhalten.
- Receiver mit `goAsync` und begrenztem WakeLock; Start/Änderung/Boot/Uhr/Zone/Update/Exakt-Erlaubnis planen neu.
- Nur `SCHEDULE_EXACT_ALARM`: erlaubt → `setExactAndAllowWhileIdle`, sonst `setWindow` um ±10 Minuten.
  Android kann das Fenster im Energiesparen weiter verzögern; Hinweis und Systemknopf in Einstellungen.
  [Android-Alarmvertrag](https://developer.android.com/develop/background-work/services/alarms).
- Beta aus oder keine Mitteilungen: Geplantes und zugestellte Erinnerungen absagen.
- „Dringlich“/konfigurierbare Entsperrpflicht entfallen: in iOS reine Entwickleroptionen.

## Abnahme
- `:app:assembleDebug :app:lintDebug :app:testDebugUnitTest :app:assembleDebugAndroidTest`: grün.
- 64 App-JVM-Tests, davon 18 neue; zusätzlich alle 20 `:thoughts:TaskReminderPlanTests` grün.
- JVM: Auswahl/Zeit, Absagen, Idempotenz, Zeitzone, Beta/Erlaubnis, Fenster, Boot, Journal, Snooze, Einladung,
  Nachrücken nach früher Fenster-Zustellung und Wiederholung fehlgeschlagener Plattform-Planung.
- Offline-Debugweg: `ReminderDeviceTest#seedReminderInTwoMinutes`; nur auf Emulator ohne Groq-Key.
- Zwei-Minuten-Termin: kalter Prozess, Zustellung +0,764 s; `rem-notification.png`, `evidence/rem-delivered.txt`.
- „Erledigt“ aus System-Mitteilung: dauerhaft erledigt, Alarm weg; `rem-completed-tasks.png`.
- Echte PendingIntent-Broadcasts: „In 1 Stunde“, Beta aus/an, dauerhaftes Snooze, doppeltes Abhaken grün.
  `ReminderDeviceTest#snoozeAndDoneUseRealBroadcastsAndDurableRepository`, `evidence/rem-platform-actions.txt`.
- `adb reboot`: offener Alarm ohne App-Öffnen wieder geplant; `evidence/rem-after-reboot-alarm.txt`.
- Berlin → New York → Berlin: gleiche Fälligkeit, neue Zonen-Signatur, genau ein offener Alarm.
- Exakt-Recht entzogen: `setWindow`, ±10 Min.; Hinweis/Systemknopf in `rem-window-settings.png`.
  In der Systemseite wieder erlaubt: bereits im Hintergrund wieder exakt; `evidence/rem-exact-restored.txt`.
- Benachrichtigungen entzogen: keine geplanten Erinnerungen, Hinweis in `rem-no-notifications.png`.
- Beta über den App-Schalter aus/an: Alarm weg/zurück; `evidence/rem-beta-{off,on}.txt`.
- Alle Nachweise unter `/tmp/paply-android-e3/`; keine echten Groq-Aufrufe.
- Offen beim UI-Helfer: Einladung und Deep-Link-Effect in dessen Ansichten einbetten (Anschluss oben).
- `paply3` um 00:25 CET mit `PAPLY_AVD=paply3 ~/Android/emu-stop.sh` gestoppt; `paply`/`paply2` laufen weiter.
