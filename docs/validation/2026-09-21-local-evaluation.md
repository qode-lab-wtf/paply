# Lokale Meeting-Vorprüfung — 21.09.2026

## Ergebnis

Noch **keine Modellkombination freigegeben**. Es wurde ein isoliertes
Vergleichswerkzeug implementiert, nicht die produktive Meeting-Pipeline ersetzt.

## Reproduzierbare technische Belege

- Apple M5 / 32 GB / macOS 26.2, Python 3.12.13, Swift 6.2.3.
- Qwen3-ASR 1.7B 4-Bit, Whisper Large v3 und Parakeet TDT v3 auf demselben
  historischen 90-s-Mikrofonausschnitt lokal ausgeführt.
- FluidAudio Offline auf demselben Ausschnitt lokal ausgeführt.
- Auf einer weiteren 21-s-Aufnahme alle vier Kandidaten mit
  `sandbox-exec ... (deny network*)` erfolgreich ausgeführt.
- Messwerte: [local-smoke.json](2026-09-21-local-smoke.json). Das sind Funktionsproben,
  keine kontrollierte Leistungsrangliste; Hintergrunddownloads und andere
  lokale Modellversuche liefen teilweise gleichzeitig. RSS umfasst nicht alle
  ausgelagerten CoreML-Systemdienste. Keine Genauigkeitswerte ohne Referenz.
- Modell-/Runtime-Digests: `tools/meeting-eval/models.lock.json`.
- 18 lokale Tests für Metriken, verweigerte Freigabe ohne Referenz, falsche/fehlende
  Sprecher, Überlappung, Quellenvalidierung, Abschneiden und sichere HTML-Einbettung.
- Hörprobe im In-App-Browser geprüft: Audio erkannt, Text und Abschnitte vorhanden,
  Download ohne bestätigte Prüfung gesperrt. Prüf-Tab und HTTP-Server danach geschlossen.

## Konkrete Grenzen

- Originales pyannote Community-1: anonymer Download wurde mit „Access denied“
  abgewiesen. Allan hat danach die kostenlose Browserfreigabe bestätigt; Zugriff
  ist auf der Modellseite sichtbar gewährt. Browserdownload liefert bisher keine
  lokal zugänglichen Dateien. Begrenzter Leseschlüssel vorbereitet, nicht erstellt.
- Beide lokalen Berichtsmodelle liefern bei der ersten Quellenkontrolle
  unbelegte Ergänzungen bzw. verwechselte Rollen. Ein korrektes JSON ist kein
  Qualitätsnachweis. Beim zweiten Vergleich werden nicht wortgetreue Belegzitate
  korrekt abgelehnt. Keine Berichtsfreigabe.
- Qwen-ASR-Worker gibt bisher Text ohne Wortausrichtung aus; nicht als fertige
  Zeitmarken-/Sprecher-Pipeline ausgeben.
- FluidAudio kann am letzten Modellfenster über das Dateiende hinausgehen.
  Der Adapter begrenzt diese Spanne auf die tatsächliche Audiodauer; Rohantwort bleibt
  lokal erhalten. Ein Regressionstest deckt das beobachtete Verhalten ab.
- Die vorhandenen historischen Paply-Labels sind keine verlässliche Referenz.
  Menschlich bestätigter Wortlaut/Sprecherverlauf für Raum/Telefon/Hybrid fehlt.

## Fortsetzung

Nach bestätigter Modellfreigabe originales pyannote mit denselben Dateien prüfen.
Die ausgewählte Hörprobe gemeinsam zur belastbaren Referenz machen und weitere
Gesprächsarten abdecken. Erst bei erfülltem Qualitätsgate die eigentliche App-Pipeline,
Report-Ansicht/Exporte, Wiederherstellung und automatische Sieben-Tage-Löschung
integrieren. Installierte v1.12.5, ihre Einstellungen und Originaldaten unverändert.

Private Aufnahmen, Transkripte, Modellantworten und Hörprobe bleiben lokal außerhalb
von Git. Instinct-Empfang ist nicht nachgewiesen.

## Erweiterung mit vorhandener Systemspur

90 s Systemton aus derselben historischen Aufnahme wurden netzgesperrt mit Whisper
(21,31 s), Parakeet (1,27 s) und FluidAudio (0,95 s) verarbeitet. Keine kontrollierte
Geschwindigkeitsrangliste. FluidAudio liefert 3 Sprecher-IDs auf der Mikrofonspur
und 2 auf der Systemspur; IDs sind kanalweise unabhängig, keine bestätigte Personenzahl.

`legacy_replay.js` spielt die unveränderte produktive `suppressBleed`-Regel mit
Whisper-Segmentzeiten nach: 36 Mikrofon-/31 Systemsegmente, 28 Mikrofonsegmente
mit zusammen 61,26 s Segmentdauer unterdrückt. Diese Zahl ist **keine gemessene
Verlustrate**: Kandidatensegmente können Echo enthalten, Referenz und präzise
Kanal-Synchronisation sind nicht bestätigt. Der Befund zeigt, wie stark die
rein zeitliche Regel in diesem Ausschnitt eingreift.

`compare.py` erstellt private selbstenthaltene Audio-/Textvergleiche mit Hashprüfung
und ausdrücklich ungeprüften Sprecherlisten. Bestehende Originalaufnahmen unverändert.
Allan erinnert die genaue Situation der kurzen Aufnahme nicht sicher; mögliches
Hintergrund-TV verhindert deren Einordnung als bestätigtes Zwei-Personen-Gespräch.
