# E3 Teil W — Aufgaben-Widgets und Erinnerungsanschluss

Stand: 29.10.2026; kein Commit/Push, keine Groq-Aufrufe.

- RemoteViews statt Glance: zwei feste Ansichten, keine neue Abhängigkeit; vorhandenes Widget-Muster.
- Klein: offene Gesamtzahl und nächste Aufgabe; mittel: bis drei Aufgaben mit separatem Abhak-Ziel.
- Auswahl/Reihenfolge aus dem portierten TaskDigest; Fälligkeit aus TaskSnapshot, keine zweite Agenda-Logik.
- Paply-Waldfarben aus ui/theme, in beiden Systemdarstellungen wie iOS; Systemrundung ab Android 12.
- Statische Picker-Vorschau plus PNG-Rückfall für Android 10/11; initial keine Beispieldaten.
- Private unveränderliche PendingIntents; Abhaken als idempotentes Set über Repository, auch bei kaltem Prozess.
- Receiver: goAsync, 8-s-Zeitgrenze, begrenzter WakeLock; danach Widget-Aktualisierung.
- Beta aus: Hinweis ohne Aufgaben, Zahl oder Abhak-Aktionen; alte Abhak-Intents werden ignoriert.
- Repository-Beobachter bündelt Änderungen für 400 ms, ohne Polling oder updatePeriodMillis.
- Ein persistierter WorkManager-Job zur nächsten sichtbaren Uhrzeit/Mitternacht; ohne Widgets keine Jobs.
- Zeit-/Zonen-/Boot-/Update-Ereignisse erneuern die Ansicht; Android darf Hintergrundjobs verzögern.
- Aufgaben-Tipps nutzen die vorhandenen ReminderLinks und öffnen das Detail mit focusTask.
- ReminderDeepLinkEffect sitzt in PaplyApp; ThoughtsHome erhielt nur einen Parameter und einen kleinen Effekt.
- ReminderInvitation steht einmal im Aufgaben-Reiter und im Aufgabenbereich des Details.
- Gedanken-Widget und Karten-Darstellung wurden nicht verändert.

## Sperrbildschirm
- Ausschließlich Home-Widgets; auf klassischen Android-Handys gab es kein iOS-entsprechendes Angebot.
- Neuere Android-Versionen führen Sperrbildschirm-Widgets wieder ein; deshalb explizites not_keyguard ab API 36.
- Meldet ein Host dennoch Keyguard, bleiben Aufgaben und Zahl verborgen; gesperrt kein Abhaken.
- Quelle: https://android-developers.googleblog.com/2025/03/widgets-on-lock-screen-faq.html

## Prüfung
- JVM: Auswahl, stabile Reihenfolge, Begrenzung, leer/erledigt, Beta aus, Keyguard, Laden, Mitternacht.
- Geräteabnahme: paply3 / emulator-5600, PAPLY_WORK=wid; Belege /tmp/paply-android-e3/wid-*.png.
- Finaler MacBook-Bau: assembleDebug, lintDebug, testDebugUnitTest und assembleDebugAndroidTest grün.
- 88 App-JVM-Tests grün, davon acht neue Widget-Inhaltsfälle; drei funktionale Widget-Gerätetests grün.
- Launcher: beide Widgets hinzugefügt; kalter Prozess ohne PID → Abhaken dauerhaft, Zahl 5 → 4.
- App zeigt dieselbe Aufgabe erledigt; kleine/mittlere Aufgaben-Tipps öffnen das richtige Detail mit Fokus.
- Einladung im Detail und im Reiter jeweils angenommen; beide AlarmManager-Einträge per dumpsys belegt.
- Beta am echten App-Schalter aus/an: Aufgaben/Zahlen weg/zurück; Erinnerungsalarm abgesagt/wieder geplant.
- 16 PNGs: Leer-/Aufgabenzustand, Beta aus, Einladungen hell/dunkel, Picker, Deep-Link und Erledigt.
- Protokolle/JVM-Zählung/Build/Alarm-/Kaltstart-Nachweise unter /tmp/paply-android-e3/evidence/wid-*.
- Physische Geräte/OEM-Verhalten bleiben die spätere Geräteabnahme; keine offene Implementierungsarbeit.
- paply3 um 01:17 CET mit dem vorgegebenen Stop-Skript beendet; Port 5600 nicht mehr verbunden.
