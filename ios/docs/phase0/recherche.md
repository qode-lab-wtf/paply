# Paply iOS – Recherche Phase 0 (Stand 27.10.2026)

Sicherheit je Antwort: hoch / mittel / niedrig. „Fakt“ = belegt, „Vermutung“ = eigene Schlussfolgerung.

## Das Wichtigste für den Bau

1. **App öffnen:** Responder-Kette bis `UIApplication`, dann `open(_:options:completionHandler:)`. Genau diesen Code zeigt Apple DTS. Unter iOS 26 geht das nur mit **Vollzugriff** (`hasFullAccess` im Onboarding prüfen).
2. **Kein automatischer Rücksprung.** Es gibt keine öffentliche API, ab iOS 26.4 auch keinen privaten Weg mehr. Plane: Start tippen, App kurz sichtbar, Nutzer tippt den „◀ App“-Pfeil oder wischt am unteren Rand nach rechts. Das passiert nur einmal pro Sitzung.
3. **Mikro nur im Vordergrund starten.** Apple sperrt den Start einer Aufnahme-Session im Hintergrund. Session im Vordergrund aktivieren, `UIBackgroundModes: audio`, Engine laufen lassen.
4. **Nach Anruf oder Siri ist Weiterlaufen nicht garantiert.** Baue einen Fallback: Tastatur zeigt „Mikro aus“, Tippen startet den Rundlauf neu.
5. **AirPods:** nur `.allowBluetoothA2DP` (ohne `.allowBluetooth`), Eingang fest auf das eingebaute Mikro. Auf dem Gerät testen.
6. **Leerlauf-Timeout selbst einbauen** (Wispr 5 min, Willow 30 s bis 2 h). Akku-Zahlen gibt es nicht, selbst messen.
7. **`AudioRecordingIntent` nicht für v1.** Er startet keine Aufnahme aus dem Hintergrund und braucht zwingend eine Live Activity.
8. **Tastatur:** Höhe nicht hartkodieren (System passt automatisch an). `needsInputModeSwitchKey` auswerten, `hasDictationKey = true` setzen. Guideline 4.4.1 verlangt Funktion ohne Vollzugriff und Weiterschalten, sonst droht Ablehnung.
9. **Signieren:** Personal Team reicht vermutlich für App Group + Tastatur (7 Tage, 10 App-IDs pro Woche, kein TestFlight).
10. **Groq:** `whisper-large-v3-turbo`, 16-kHz-Mono-WAV (~1,9 MB/min) reicht. `no_speech_prob` ist unbrauchbar (immer 0). Stille lokal erkennen. Mindestabrechnung 10 s.
11. **Markt:** Apples KI-Diktat ist nur Englisch und nur auf iPhone 17 Pro/Air. Für Deutsch und das 14 Pro Max keine Konkurrenz.

## 1. App aus der Tastatur öffnen

- **Technik (Fakt, hoch):** Apple DTS (Ziqiao Chen) nennt es erlaubt: Guideline 4.4.1 („keine anderen Apps außer Einstellungen“) meine nicht die eigene Container-App, App Review habe das bestätigt. Code: `var r: UIResponder? = self; while r != nil { if let app = r as? UIApplication { app.open(url) {…}; break }; r = r?.next }`. developer.apple.com/forums/thread/812091
- **iOS 18 (mittel):** Der alte Selector `openURL:` wird abgelehnt („BUG IN CLIENT OF UIKIT“). Community-Workaround: Selector `open:options:completionHandler:`, nur bei `isMemberOfClass: UIApplication`. DTS nennt es einen Hack. developer.apple.com/forums/thread/764570
- **iOS 26 (mittel):** Der Aufruf scheitert ohne Vollzugriff (`_LSIsRequestAllowed`, -54). Unter iOS 18 ging er noch. DTS hält das für Absicht. Siehe Thread 812091.
- **`extensionContext.open`:** Laut Apple nur für Today-Widgets (sekundär zitiert, Thread 848791). Berichte widersprechen sich (niedrig).
- **Zulassung (mittel):** Wispr Flow, Willow, Superwhisper, Letterly und Typeless sind im Store. Willow erklärt den Rundlauf öffentlich. help.willowvoice.com/en/articles/12855752
- **Vermutung:** Ein schriftlicher Policy-Text fehlt. Ein Entwickler liefert deshalb den Release-Build ohne Startpfad aus (developer.apple.com/forums/thread/843118).

## 2. Zurück zur vorherigen App

- **Wispr-Artikel (Fakt, hoch):** Er nennt die Änderung nicht. Er sagt nur: Nach „Start Flow“ kehrt man zurück. Klappt das nicht, zeigt „Flow is on“ keinen Knopf, und man soll am unteren Rand nach rechts wischen. docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4
- **Was sich änderte (Fakt, mittel):** Superwhisper schreibt, iOS 26.4 erlaube Dritt-Tastaturen die automatische Rückkehr nicht mehr (FB22247647). superwhisper.com/docs/common-issues/ios-26-keyboard-changes. Wispr zeigt den Wisch-Bildschirm „Swipe back to your app“, gestaffelt ausgerollt.
- **Vorher (mittel):** Die Tastatur las per KVC `_hostBundleID` bzw. `_hostApplicationBundleIdentifier` und gab sie per URL weiter. Die App öffnete den Host dann über privates `LSApplicationWorkspace openApplicationWithBundleID:`. Ab 26.4 ist der Wert nil oder gesperrt. developer.apple.com/forums/thread/826851, github.com/KeyboardKit/KeyboardKit/issues/1014
- **DTS (hoch):** Es gibt keine öffentliche API. FB22247647 ist offen, ohne Zeitplan. Es gibt keine „privaten APIs“, nur Implementierungsdetails, die brechen dürfen.
- **iOS 18 tauglich (mittel):** Der System-Pfeil „◀ App“ oder die Wischgeste, beides durch den Nutzer. Private Schlüssel verstoßen gegen Guideline 2.5.1. Yandex bekommt die Host-ID angeblich noch (Thread 836168, niedrig).

## 3. Hintergrund-Mikro-Sitzung

- **Konfiguration:** `.playAndRecord`, Modus `.default`, `.mixWithOthers` (Wispr nimmt „neben anderem Audio“ auf, docs.wisprflow.ai/articles/8415579688). Außerdem `setPrefersNoInterruptionsFromSystemAlerts(true)`: Anruf-Banner unterbrechen dann nicht (Apple-Doku, hoch). Ein Voll-Bildschirm-Anruf unterbricht trotzdem.
- **HFP vermeiden (mittel):** Ein Entwickler löste „Ausgabe fällt auf Lautsprecher/HFP“ mit nur `.allowBluetoothA2DP` plus `setPreferredInput(builtInMic)`, Antwort aus einem WWDC-Lab. developer.apple.com/forums/thread/741513. Ab iOS 26 gibt es `.bluetoothHighQualityRecording` (nicht in der EU, keine Echtzeit-Eignung). Wispr bietet „Built-in mic“ als Einstellung.
- **Lange Sitzungen (niedrig):** Ein Zeitlimit ist nicht dokumentiert. Die Anbieter setzen eigene Timeouts. Ein Entwickler meldet Suspendierung nach Sekunden, ohne Antwort (thread/800500).
- **Wiederaufnahme (mittel):** DTS Kevin Elliott sagt, Aufnahme-Sessions dürfen im Hintergrund nicht aktiviert werden. Ausnahmen sind CallKit, LiveCommunicationKit und PushToTalk (thread/816408). Die Aussage gilt dem Start. Vermutung: Sie trifft auch die Wiederaufnahme. Thread 813278 (ohne DTS) zeigt `.ended` und dann `setActive` mit Fehler „!int“ bis zum Vordergrund. Wispr behauptet das Gegenteil für kurze Unterbrechungen (Vendor-Aussage).
- **Akku (niedrig):** Es gibt nur anekdotische Berichte, keine Messwerte.

## 4. AudioRecordingIntent (iOS 18+)

- **Anforderung (hoch):** Eine Live Activity ist Pflicht, sonst stoppt die Aufnahme. developer.apple.com/documentation/appintents/audiorecordingintent. Ein Bericht meldet unter iOS 27 einen Absturz ohne Live Activity (github.com/straff2002/OpenGlasses/pull/695, niedrig).
- **Prozess (mittel):** `LiveActivityIntent` startet den App-Prozess ohne Öffnen (Apple-Doku). Ein Control-Button-Intent läuft laut Praxisberichten in der Erweiterung, außer er ist `LiveActivityIntent` oder `ForegroundContinuableIntent`. `AudioRecordingIntent` allein genügt nicht. github.com/anthonytw/sempere/pull/29. Bei Kurzbefehl und Rückseite läuft der Intent im App-Prozess (Vermutung).
- **Start aus dem Hintergrund (mittel):** Das scheitert (Fehler „Target is not foreground“, „!int“, „!rec“). Ein Apple-Mitarbeiter empfahl den Intent zwar einmal (thread/771457), DTS verneint den Start (thread/816408). Kurzbefehle brauchen `openAppWhenRun` (thread/756507).
- **Bereits laufende Engine (Vermutung, niedrig):** Das Hindernis ist die Session-Aktivierung. Läuft die Engine schon, entfällt sie. Die Live Activity bleibt trotzdem nötig. Willow nutzt eine Live Activity zum Abschalten.

## 5. Custom Keyboard

- **Höhe (mittel):** Apple veröffentlicht keine Tabelle (nichts gefunden). Standard ist die Systemhöhe, Breite ist fest. Eigene Höhe über die Höhen-Constraint der `view`, Priorität 999, in `viewWillAppear`. Beim Start gibt es ein bekanntes Flackern (Frames 0×0, Vollbild, dann Zielhöhe nach ~390 ms, thread/813579). **Messen:** `keyboardWillShow` im Testhost auf dem 14 Pro Max, jeweils hoch und quer, mit und ohne Vorschlagsleiste.
- **Speicher (niedrig):** Das Limit variiert je Gerät und ist nicht veröffentlicht. Inoffiziell werden 48 bis 60 MB genannt.
- **Haptik/Klick:** `playInputClick` braucht Vollzugriff (hoch, Archiv-Doku). Für Haptik gibt es keine Aussage, testen.
- **`advanceToNextInputMode()` (hoch/niedrig):** „Nächste Tastatur in der Liste der aktivierten“ (Apple). Es gibt keine API für die Liste. Ob Emoji dazugehört, ist nicht dokumentiert, testen. Lang drücken zeigt die Liste über `handleInputModeList(from:with:)` mit `.allTouchEvents`.
- **Face ID (hoch):** iOS zeichnet 🌐 und Mikro unter die Tastatur. `needsInputModeSwitchKey` ist false. Mit `hasDictationKey = true` entfällt das System-Mikro. Ohne Face ID muss die eigene 🌐 da sein, sonst Ablehnung (thread/849736).
- **Undo per Wisch/Schütteln:** nicht belegt, auf dem Gerät testen.
- **Ladezeit:** Es gibt keine veröffentlichten Zahlen.
- **Ausnahmen (hoch):** Passwortfelder und `phonePad`/`namePhonePad` zeigen die Systemtastatur. Apps können Dritt-Tastaturen sperren.

## 6. Signieren

Mittel. Fakt: App-IDs maximal 10 pro 7 Tage, 3 Geräte, 3 Apps pro Gerät, Profil 7 Tage (developer.apple.com/support/compare-memberships). App Groups liefen im Forenfall mit Personal Team; DTS: jedes Team braucht eigene Bundle-ID und Group-ID (thread/834802). Tastatur plus App sind 2 App-IDs. Kein TestFlight und kein Store. Ob alle Capabilities (Push) gehen, nicht geprüft.

## 7. Groq Speech-to-Text

Hoch (console.groq.com/docs/speech-to-text):
- **Preis und Tempo:** `whisper-large-v3` $0,111/h, 189×, WER 10,3 %. `-turbo` $0,04/h, 216×, WER 12 %, nur Transkription. Beide 99+ Sprachen. Sekundär ist Turbo bei Deutsch minimal schlechter (niedrig).
- **Limits:** `prompt` max. 224 Token. Dateien 25 MB (Free) bzw. 100 MB (Dev). Mindestabrechnung 10 s.
- **Formate:** flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, webm. Groq wandelt auf 16 kHz mono um. FLAC für kleine Dateien, WAV für niedrigste Latenz.
- **verbose_json:** Segmente liefern `avg_logprob`, `compression_ratio`, `no_speech_prob`. Ein Top-Level-`language` steht nicht in der Doku (mittel, mit einem Testaufruf prüfen). `duration` nutzt der Desktop-Code. `no_speech_prob` ist laut `docs/STAND.md` immer 0.

## 8. Markt: Apples KI-Diktat in iOS 27

Hoch/mittel. iOS 27 erschien laut Berichten am 14.09.2026. „Advanced Dictation“ (Modell AFM Core Advanced, auf dem Gerät) läuft auf iPhone 17 Pro, 17 Pro Max und Air (12 GB RAM). Es ist **nur Englisch** (9 Varianten) und in der Beta ein ausgeschaltetes Opt-in. Normales Diktat deckt ~80 Varianten inkl. Deutsch ab. apple.com/ios/feature-availability, 9to5mac.com/2026/06/12/ai-advanced-dictation-preview-ios-27-beta
