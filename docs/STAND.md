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
Das ist kein Genauigkeitsnachweis. 12 Harness-Tests bestanden; Referenzprüfung
verweigert ohne menschliche Bestätigung ausdrücklich eine Freigabe.
Private selbstenthaltene Hörprobe erzeugt und im In-App-Browser geprüft.
Modellrevisionen/Digests in `tools/meeting-eval/models.lock.json` festgehalten.

Original-pyannote-Zugang verlangt die kostenlose Freigabe der Kontaktweitergabe;
Allan ist im Browser angemeldet, explizite Zustimmung dazu angefragt.
Berichtsvergleich Gemma3-4B / Qwen3-8B läuft. Gemma produziert bei reinem JSON-Prompt
keine gültigen Quellenfelder; mit Schema strukturell gültig, inhaltlich weiterhin
unbelegte Ergänzungen. Kein Berichtsmodell freigegeben.
Die installierte App, produktive Aufnahmen und Diktierfunktion bleiben unverändert.

## Offen

Menschlich bestätigte Referenz für Sprecher/Inhalt und Abdeckung Raum/Telefon/Hybrid.
Noch keine Modellkombination qualifiziert; Integration/Ansicht/Retention/Export stehen
hinter diesem Qualitätsgate. Instinct-Empfang nicht nachgewiesen.
