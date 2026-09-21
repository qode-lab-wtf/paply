# Paply — aktueller Stand

2026-09-21 · Phase: Entwicklung/Prüfung · Branch `codex/local-meeting-quality`

## Bestätigtes Ziel

[Kostenloser Gesprächsmodus](PLAN.md), [Entscheidungen](ENTSCHEIDUNGEN.md).
Erst isolierter lokaler Qualitätsvergleich, danach Integration bei bestandenem Gate.

## Nachgewiesen

- Basis `736f5aa` stimmt mit GitHub main überein, ursprünglicher Checkout sauber.
- Vier relevante Meeting-Module der installierten v1.12.5 stimmen byteweise mit Basis überein.
- Basis: 129 Tests in 17 Dateien bestanden (21.09.2026); kein Nachweis echter Sprecherqualität.
- Apple M5, 32 GB, macOS 26.2. Lokale historische Audiodateien vorhanden.
- Keine offenen GitHub-Issues beim Sitzungsstart.

## Aktuelle Arbeit / nächster Schritt

Isolierte Laufzeiten und reproduzierbares Vergleichswerkzeug in `tools/meeting-eval/` angelegt.
Qwen-ASR, Whisper, Parakeet und FluidAudio auf echten lokalen Ausschnitten ausgeführt.
Alle vier bestanden einen 21-s-Probelauf mit gesperrtem Netzwerk; Messwerte in
[`validation/2026-09-21-local-smoke.json`](validation/2026-09-21-local-smoke.json).
Das ist kein Genauigkeitsnachweis. 18 Harness-Tests bestanden; Referenzprüfung
verweigert ohne menschliche Bestätigung ausdrücklich eine Freigabe.
Private selbstenthaltene Hörprobe erzeugt und im In-App-Browser geprüft.
Modellrevisionen/Digests in `tools/meeting-eval/models.lock.json` festgehalten.

Original-pyannote-Zugang freigegeben, begrenzter Leseschlüssel nach Allans explizitem
Ja erstellt und zum Download benutzt. Kein Schlüssel in Projekt/CLI-Konfiguration
abgelegt; Zwischenablage anschließend geleert. Originalmodell lokal vorhanden,
Revision und sieben Artefakthashes festgeschrieben. Erster netzgesperrter 21-s-Lauf
erfolgreich (28,17 s, 4,07 GB Einzelprozess-RSS), ohne Teilnehmerzahl-Vorgabe.
Auch beide 90-s-Spuren wurden erfolgreich netzgesperrt verarbeitet.
[Messwerte](validation/2026-09-21-pyannote-offline.json). Auf der Mikrofonspur
findet pyannote zwei, FluidAudio drei Sprechergruppen; richtige Zuordnung ungeprüft.
Alle drei privaten Hörvergleiche um pyannote ergänzt. Kein Zugangshindernis mehr.
Berichtsvergleich Gemma3-4B / Qwen3-8B durchgeführt: beide produzieren mit einem
JSON-Schema strukturell gültige Ergebnisse, aber beim Quellenvergleich fallen
unbelegte Ergänzungen bzw. vertauschte Rollen auf. Zweiter Vergleich mit identischem
Whisper-Text, exakten Belegzitaten und Qwen-Analysemodus wird von der Zitatprüfung
bei beiden Modellen abgelehnt. Kein Berichtsmodell freigegeben.
Die separate originale pyannote-Laufzeit und das Modell sind installiert.
Die installierte App, produktive Aufnahmen und Diktierfunktion bleiben unverändert.

## Offen

Menschlich bestätigte Referenz für Sprecher/Inhalt und Abdeckung Raum/Telefon/Hybrid.
Allan kann Hintergrund-TV bei der 21-s-Aufnahme nicht ausschließen. Sie bleibt
unklassifiziert. Auf seinen Wunsch vorhandene Aufnahmen weiterverwenden; keine neue
Aufnahme oder QuickTime-Bedienung erforderlich. Zusätzlich 90 s Systemton mit
Whisper, Parakeet und FluidAudio bei gesperrtem Netzwerk erfolgreich ausgewertet.
Private Hörvergleiche für Mikrofon/Systemton erstellt. Diagnose mit der bisherigen
Zeitüberlappungsregel verwirft 28 von 36 neuen Whisper-Mikrofonsegmenten; das beweist
noch nicht, wie viel davon Echo bzw. echter Gesprächsbeitrag ist.
Noch keine Modellkombination qualifiziert; Integration/Ansicht/Retention/Export stehen
hinter diesem Qualitätsgate. Instinct-Empfang nicht nachgewiesen.
