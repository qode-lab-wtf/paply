# Paply: kostenloser, verlässlicher Gesprächsmodus

Bestätigt am 21.09.2026 durch Allans ausdrücklichen Implementierungsauftrag.

## 1. Richtung und Grenzen

Keine laufenden API-Kosten, Abos oder Abhängigkeit von zeitlich begrenztem Testguthaben.
Vorhandenen M5/32-GB-Mac nutzen; Strom und Speicher fallen an. Lokale Verarbeitung
ist bevorzugt. Kostenpflichtiges Deepgram/pyannote Precision entfällt. Kostenlose
Cloud-Dienste höchstens optional, niemals alleinige Betriebsgrundlage und niemals
automatischer kostenpflichtiger Fallback. Die funktionierende Diktierfunktion bleibt unverändert.

## 2. Isolierter Qualitätsvergleich vor Integration

Transkription: Parakeet TDT v3, Qwen3-ASR 1.7B, Whisper Large v3 jeweils lokal.
Sprecher: FluidAudio Offline gegen originales pyannote Community-1.
Bericht: Qwen3-8B in 4 Bit gegen vorhandenes Gemma3-4B.

Alle Kandidaten bekommen identische deutsche Referenzaufnahmen. Komponenten
einzeln prüfen: Sprecherzuordnung und Vollständigkeit zuerst, dann Berichtstreue,
Stabilität, Speicherverbrauch und Geschwindigkeit. Quellen/Versionen/Hashes und
Ressourcenmessungen speichern. Gewinner nur unter bestandenen Kandidaten auswählen;
bei Gleichstand weniger Speicher und dann kürzere Laufzeit. Keine Siegerbehauptung
ohne Referenz und Messung. Lizenzbedingungen beim Download beachten.

Bestandene Kombination mit festen Modell-/Softwareversionen in separatem
Hintergrundprozess integrieren; nur benötigte Modelle ausliefern, schwere Schritte
nacheinander. Neue Aufnahmen dürfen von der Auswertung nicht blockiert werden.

## 3. Aufnahme, Transkript und Bericht

Shortcut startet sofort getrennte Mikrofon-/Systemtonspuren mit gemeinsamer Zeitbasis.
Startverzögerung, Gerätewechsel und Unterbrechungen erfassen; Lücken nicht durch
Zusammenschieben kaschieren. Letzte Audioreste beim Stop sichern. Anruferkennung
nur Hinweis, keine Ausschlussregel für aufgezeichneten Systemton. Fehler sichtbar.

Raumgespräche mit 2–3 Personen, mehrere Telefonpartner und Mischsituationen unterstützen.
Live-Text vorläufig, endgültige Auswertung nach Stop. Tonhöhenheuristik, erstes
Sprechen als „Ich“ und textbasiertes Umsortieren entfernen. Neutrale stabile IDs,
nachträgliche Namen/Korrekturen; Teilnehmerzahl nicht vorab verpflichtend.

Zeitüberschneidung allein darf kein Echo-Löschkriterium sein. Audiosignal als Referenz
zum Echoabgleich verwenden. Echte eigene Überlappungen behalten; unklare Stellen
markieren statt Wörter zu erfinden. Originaltranskript mit Zeitmarken/Nachhören;
Erkennung und Nutzerkorrekturen getrennt speichern. Neuberechnung überschreibt
Korrekturen nicht unbemerkt.

Bericht: kurze Orientierung und inhaltsabhängige Themen, Erklärungen, Standpunkte,
Entscheidungen mit Gründen, Aufgaben und offene Fragen. Lange Gespräche abschnittsweise
analysieren, dann nachvollziehbar zusammenführen. Aussagen auf Textstellen beziehen.
Keine pauschale kurze Ausgabelänge; ungültige/abgeschnittene Ausgabe ist Fehler.
Tabellen/Ablaufgrafiken nur bei inhaltlichem Nutzen. Vorschlag, Entscheidung und
offene Frage unterscheiden. Keine erfundenen Fakten, Beschlüsse oder Zuständigkeiten.
Paply-Anzeige; Text-Transkript, eigenständiges HTML und PDF exportieren.
Größere Ansichtänderungen erst als Vorschau zur ausdrücklichen Auswahl zeigen.

## 4. Speicherung und Schnittstellen

Versioniertes Datenmodell: stabile Sprecher-/Segment-IDs, Aufnahmezeitpunkte,
Verarbeitungsstatus/Fehler, Modellversionen, Nutzerkorrekturen, Quellverweise und
Löschzeitpunkt. Aufnahme/STT/Sprecheranalyse/Bericht getrennt wiederaufnehmbar.
Lokale Aufnahme bei Netzausfall/Modellfehler erhalten; atomare Persistenz.

Neue Originalaufnahmen sieben Tage ab Aufnahmeende behalten. Danach sämtliche
Original-/Zwischen-/Fehlerkopien entfernen; Transkripte/Berichte bleiben.
macOS-Hintergrundauftrag unabhängig vom Paply-Fenster; ausgeschalteter Mac löscht
fällige Dateien beim nächsten Start. Historische Gespräche bleiben lesbar, keine
ungefragte Bereinigung. Fehlender alter Originalton ist nicht rekonstruierbar.

## 5. Freigabe und Einführung

Referenzsatz mit bekannten Sprecherwechseln und Gesprächsinhalten: Raum, Telefon,
Hybrid; ähnliche Stimmen, kurze Einwürfe, Überlappungen, Lautsprecher/Kopfhörer,
lange Gespräche. Testreferenzen bleiben lokal und werden menschlich bestätigt.

- Mindestens 95 % verständliche, nicht überlagerte Sprecherzeit korrekt, je Situation.
- Höchstens 10 % Wortfehler auf verständlichen deutschen Referenzabschnitten.
- Keine durch Paply-Zusammenführung verlorenen Beiträge.
- Alle markierten Entscheidungen/Aufgaben/Zahlen/Gegenpositionen im Bericht.
- Keine erfundenen Beschlüsse/Verantwortlichen; Überlappungen gesondert bewerten.
- Offline-Dauerlauf, Gerätewechsel, Absturz/Wiederaufnahme, Export, Löschung testen.
- Bestehende Diktierfunktion mit Shortcut/Polieren/Einfügen regressionsprüfen.

Keine kostenlose Kombination besteht: konkrete Grenze dokumentieren, keine
Produktivfreigabe oder Verschlechterung der installierten App. Arbeit in separater
Testversion mit eigenen Daten. Geprüfte Zwischenstände samt Plan/Belegen committen
und auf Arbeitsbranch pushen; Remote frisch vergleichen. Instinct-Empfang separat prüfen.
