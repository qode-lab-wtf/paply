# Paply iOS – TestFlight

Stand 27.10.2026 · App in App Store Connect: „Paply“, Bundle-ID `com.paply.ios`, Team Aram UG.

## Hochladen (Allan, am MacBook, ca. 5 Min.)

1. In `ios/Config/Base.xcconfig` steht `PAPLY_BUILD`. Jeder Upload braucht eine höhere Zahl (die Bauleitung setzt sie vorher).
2. iPhone muss nicht angeschlossen sein. Oben in Xcode als Ziel **„Any iOS Device (arm64)“** wählen.
3. **Product › Archive**. Nach dem Bauen öffnet sich der Organizer.
4. **Distribute App › App Store Connect › Upload** (bzw. „TestFlight & App Store“), alles auf Standard lassen, **Upload**.
5. Nach 5–20 Min. erscheint der Build in App Store Connect unter **TestFlight**. Exportbestimmungen: „Keine“ (bereits über `ITSAppUsesNonExemptEncryption = NO` beantwortet).

## Interne Tests (sofort, ohne Apple-Prüfung)

TestFlight › **Interne Tests** › Gruppe anlegen (z. B. „Allan“) › sich selbst hinzufügen. Die TestFlight-App auf dem
iPhone zeigt Paply dann direkt.

## Externe Tests für Freunde (einmalige kurze Apple-Prüfung)

TestFlight › **Externe Tests** › Gruppe „Freunde“ › Build hinzufügen › **Öffentlichen Link aktivieren** → Link an
Freunde schicken. Vorher einmal die Testinformationen ausfüllen:

### Beta-App-Beschreibung

> Paply ist Sprache für dein iPhone – auf zwei Wegen.
> **Diktat:** In jeder App die Weltkugel (🌐) tippen, sprechen, auf die Fläche tippen – der Text steht aufgeräumt
> im Feld. Paply erkennt deine Sprache selbst, auch gemischt Deutsch/Englisch.
> **Gedanken:** Paply-Knopf auf dem Sperrbildschirm, als Widget unter der Uhr oder im Kontrollzentrum drücken,
> reden, „Fertig“. Paply ordnet den Gedanken auf einer Karte deiner Themen ein – mit Titel, aufgeräumtem Text und
> Aufgaben, die im Reiter „Aufgaben“ landen. Gespeichert wird nur Text; die Aufnahme wird nach der Umschrift gelöscht.
> Zum Start brauchst du einen kostenlosen Groq-Schlüssel – die App führt dich in vier Schritten durch die Einrichtung.

### Was soll getestet werden?

> 1. Einrichtung oben in der App (Mikro, Groq-Schlüssel, Tastatur mit Vollzugriff, Gedanken-Knopf).
> 2. Diktat in WhatsApp/Notizen: 🌐 → sprechen → tippen. Wie gut ist der Text? Wie schnell?
> 3. Gedanke vom Sperrbildschirm: drücken → sprechen → Fertig. Passen Titel, Thema, Aufgaben?
> 4. Karte und Aufgaben: Thema antippen, zoomen, Aufgaben abhaken. Fühlt sich das klar und schnell an?
> 5. Was war unklar oder hat gehakt? Bitte über „Feedback senden“ in den Einstellungen oder per Screenshot in
>    TestFlight melden.

### Feedback-E-Mail

Allans Kontakt-Adresse (in App Store Connect eintragen).

### Hinweise für die Apple-Prüfung (Beta App Review)

> Paply needs a free Groq API key (speech recognition and text cleanup run via the user's own key). A demo key for
> review: `<HIER DEN EXTRA-SCHLÜSSEL EINTRAGEN – nach der Prüfung bei Groq löschen>`.
> Setup: open Paply → paste the key (Settings › Groq key). Keyboard: Settings › General › Keyboard › Keyboards ›
> Add › Paply, then enable Full Access (needed to share the recording state with the app via App Group; no data is
> collected by us). Dictation: in any text field tap the globe key until Paply appears, speak, tap the green area.
> Thoughts: add the „Gedanke“ control to Control Center or the Lock Screen (or the „Paply-Gedanke“ Lock Screen
> widget below the clock), press, speak, press again. Recordings are deleted once transcribed; only text is kept.
> Background audio: while the user keeps Paply ready, the app holds the microphone so the keyboard can start
> dictation instantly (keyboards cannot access the microphone). Nothing is recorded or sent while idle; iOS shows
> the microphone indicator.

**Schlüssel für die Prüfung:** Allan legt bei console.groq.com einen eigenen Schlüssel nur für Apple an und löscht
ihn nach der Freigabe. Nicht den Alltagsschlüssel nehmen. Nie ins Repository.

### Datenschutz-Text (für eine Datenschutz-URL, falls App Store Connect sie verlangt)

> **Paply – Datenschutz**
> Paply speichert Diktat-Verlauf und Gedanken nur auf deinem iPhone, als Text. Aufnahmen werden nach der
> Umschrift sofort gelöscht. Zur Spracherkennung und zum Aufräumen des Textes sendet Paply die Aufnahme bzw.
> den erkannten Text an Groq (groq.com), mit deinem eigenen Groq-Schlüssel; dafür gelten die Bedingungen von Groq. Der Entwickler von Paply erhält keine Daten. Im
> Bereitschaftsmodus hält Paply das Mikrofon nur offen, damit das Diktat sofort startet – dabei wird nichts
> gespeichert oder gesendet. Es gibt kein Tracking und keine Werbung. Kontakt: Aram UG (haftungsbeschränkt).

Ort für die Seite: noch offen (z. B. GitHub Pages oder eine öffentliche Notion-Seite) – erst nötig, wenn App Store
Connect beim externen Test danach fragt.
