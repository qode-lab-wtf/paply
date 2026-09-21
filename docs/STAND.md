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

Original-pyannote-Zugang: Allan hat die kostenlose Freigabe ausdrücklich bestätigt;
Hugging Face zeigt den Zugriff als gewährt. Browserdownloads liefern bisher keine
lokal zugängliche Datei. Ein ausschließlich lesender, auf dieses Modell begrenzter
Download-Schlüssel ist vorbereitet, aber noch nicht erstellt; Bestätigung angefragt.
Berichtsvergleich Gemma3-4B / Qwen3-8B durchgeführt: beide produzieren mit einem
JSON-Schema strukturell gültige Ergebnisse, aber beim Quellenvergleich fallen
unbelegte Ergänzungen bzw. vertauschte Rollen auf. Zweiter Vergleich mit identischem
Whisper-Text, exakten Belegzitaten und Qwen-Analysemodus wird von der Zitatprüfung
bei beiden Modellen abgelehnt. Kein Berichtsmodell freigegeben.
Die separate originale pyannote-Laufzeit ist installiert; der autorisierte
Modell-Download ist noch offen (siehe Zugangsstatus oben).
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
