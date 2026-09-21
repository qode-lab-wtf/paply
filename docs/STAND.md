# Paply — aktueller Stand

2026-09-21 · Phase: Entwicklung/Prüfung · Branch `codex/local-meeting-quality`

## Bestätigtes Ziel und aktuelle Grenze

[Plan](PLAN.md), [Entscheidungen](ENTSCHEIDUNGEN.md). Kostenloser lokaler
Gesprächsmodus; Diktat unverändert. Allan hat nach den Vergleichen ausdrücklich
Produktumsetzung und weitere vorhandene Beispiele angefordert. Deshalb wird eine
getrennte lokale Test-App gebaut. **Keine Qualitäts- oder Produktivfreigabe.**
Die installierte `/Applications/paply.app` und ihre Daten bleiben unverändert.

## Implementiert in der getrennten Testversion

- Eigene App-ID, eigener Datenordner und Shortcut Cmd+Option+Shift+X.
- Mikrofon und Systemton separat in atomaren Zwei-Sekunden-Dateien gesichert.
  Fortlaufende Abtastratenumrechnung statt Rundungsverlust je Audioblock;
  Endstücke werden vor Stop bestätigt und gespeichert.
- Lokales Whisper Large v3 und originales pyannote Community-1 in getrennten,
  sequenziellen Prozessen mit gesperrtem Netzwerk. Checkpoints/Wiederaufnahme.
- Neutrale Sprecher, Wortzeit-Zuordnung und sichtbare Unsicherheit. Erkannte Stimme
  ohne ASR-Text als Lücke sichtbar. Keine pauschale Löschung bei Zeitüberlappung;
  Audio-Korrelation markiert mögliches Echo, löscht keine Beiträge.
- Textstellen-Wiedergabe, unabhängige gespeicherte Text-/Sprecherkorrekturen,
  unverknüpfbare frühere Korrekturen sichtbar, TXT/HTML/PDF-Export.
- Versionierte Sitzung mit Aufnahmezeit, Modellversionen, Fehlern und Ablaufdatum.
  LaunchAgent für neue Audioaufnahmen nach sieben Tagen einschließlich Zwischenkopien.
  Historische Daten werden nicht rückwirkend bereinigt.
- Historische Testkopien behalten zunächst ihre Quellenübersicht. Neu berechnete
  Testgespräche erhalten einen abschnittsweisen lokalen Berichtsentwurf mit echten
  Quellenverweisen, zusätzlicher Aussagenprüfung und eigener Modellversion. Quellenbezug
  und Modellprüfung beweisen keine Faktentreue. Qwen3.8-27B bleibt ausdrücklich
  experimentell, keine zuverlässige Produktfreigabe. Abgelehnte Aussagen werden durch die
  Originalstellen ersetzt, statt unbelegte Beschlüsse/Aufgaben stehenzulassen.

## Nachgewiesen am 21.09.2026

- Ursprungsbasis `736f5aa` identisch mit damaligem GitHub main; vier relevante Module
  der installierten v1.12.5 bytegleich. M5/32 GB/macOS26.2.
- Fünf historische Gesprächsausschnitte, neun Tonspuren. Zusätzliche drei Gespräche
  mit zwölf erfolgreichen netzgesperrten Modellläufen:
  [Zusatzaufnahmen](validation/2026-09-21-additional-recordings.json).
- Der neue Zusammenführungscode erhält den gesamten erkannten ASR-Text auf allen
  neun Spuren: [Erhaltungsprüfung](validation/2026-09-21-product-text-preservation.json).
  Das beweist weder vollständige Spracherkennung noch richtige Sprecherzuordnung.
- Reale 21-s-Aufnahme mit dem neuen App-Backend vollständig offline verarbeitet:
  ASR → Sprecheranalyse → Zusammenführung → Quellenübersicht, Status ready.
- 138 App-Tests/18 Dateien; 34 Python-Tests. Fehler/Wiederaufnahme, Korrekturen,
  Aufnahme-Endstücke, Löschung während Verarbeitung, Erhalt überlappender Texte.
- Vite-Build erfolgreich. Vier bekannte TypeScript-Fehler Profile/CustomAgent in
  Dashboard bestehen auch auf der unveränderten Basis; nicht als grüner Typecheck ausgeben.
- Test-App lokal gepackt/ad-hoc signiert und gestartet. Nicht-ASCII-Executable-Name
  verursachte Startabsturz; ASCII-Bündelname `Paply Meeting Test` behebt ihn auf diesem Mac.
- In echter App-Oberfläche fünf Testgespräche geöffnet; Textstelle startet Audio bei
  17,64 s; Korrektur gespeichert; PDF aus der App als Datei erzeugt.
- LaunchAgent geladen, letzter Exit 0. Bei geschlossener Test-App abgelaufene Test-
  Audiodatei entfernt, Transkript und historische Testaufnahme erhalten.

- Apple-MPS-Sprecheranalyse: neun Tonspuren identisch zur CPU-Ausgabe; bei der
  Kurzaufnahme 7,37 statt 28,17 Sekunden. Kein Nachweis korrekter Sprecherlabels:
  [MPS-Vergleich](validation/2026-09-21-mps-comparison.json).
- Vollständige historische Aufnahme mit 1.655 s Mikrofon und 3.342,6 s Systemton
  offline verarbeitet, nach absichtlichem Prozessabbruch mit Checkpoint fortgesetzt.
  Alle erkannten Texte beider Spuren inklusive Wortreihenfolge erhalten. Ein Fehler
  bei gleichen Wortzeitstempeln wurde dabei behoben und als Regressionstest ergänzt:
  [Langtest](validation/2026-09-21-long-offline.json).
- Diese historische Quelle hat ungleiche Spurlängen und Indexdauer 0; sie beweist
  keine korrekte neue Aufnahmesynchronisierung. Neue Aufnahmen markieren Abweichungen
  zwischen Audio- und Aufnahmeuhr. Beide Quellen werden beim Stop sofort gestoppt.
- Die Test-App verhindert einen zweiten gleichzeitigen Prozess mit demselben
  Datenordner, damit keine doppelten Modellläufe/Sitzungsschreibvorgänge entstehen.
- Ausgewählte Python-Laufzeiten, Modelle und Berichtsprozess im eigenen Supportordner
  vorbereitet, keine Abhängigkeit der Test-App von Entwicklungs-Venv-Pfaden.
- Neu gepackte App: 21-s-Testkopie per UI vollständig neu verarbeitet, Status ready;
  Whisper → Community-1/MPS → Qwen3.8-27B-Entwurf mit Aussagenprüfung. Bericht und
  Quellenverknüpfung zu Sprecher 2 in der echten Oberfläche geprüft. Frühere
  Testkorrektur blieb gespeichert und wurde bei geänderten IDs als unverknüpft gezeigt.

## Bedienklarheit / Absturzmeldung geprüft

- 21.09.2026, 16:04: Genau eine installierte Paply-App und eine separate Test-App
  liefen. Vier vorhandene Crashberichte betreffen ausschließlich den alten Build
  „Paply Gespräch Test“ von 14:41–14:42; kein neuer Bericht zum aktuellen Build.
- Testfenster heißt jetzt „Paply Gespräch – TESTVERSION“, Versionsfußzeile nennt
  ausdrücklich den lokalen Test statt einer vermeintlich aktuellen Release-Version.
  Zusätzlich Dock-Badge TEST gesetzt. Neuer Build gestartet, Fenstertitel und
  Fußzeile in der echten Oberfläche verifiziert; normale App nicht neu gestartet.
- Allan braucht keinen GitHub-Download und kein Update. Nächster Praxistest direkt
  über Cmd+Option+Shift+X: zwei bekannte Personen, zunächst ohne zusätzliche Tonquelle.
  Die inhaltlichen Qualitätsgrenzen unten bleiben bestehen.

## Aktueller fehlgeschlagener Raumtest

Allan meldete am 21.09.2026 drei Personen im Raum, stark falschen Text und nur eine
sichtbare Stimme. Die neue 106-s-Aufnahme ist kein bestandener Test. Original-ASR
übersprang ungefähr 11–52 s trotz dort erkannter Sprache; die akustische Analyse
fand automatisch zwei statt drei Gruppen. Der Bericht war noch in Arbeit und wurde
zur Untersuchung angehalten. Kein Polishing des Originaltranskripts.

Ein Anzeigeproblem hielt den vorläufigen Text bis zum Abschluss des langen Berichts
sichtbar: korrigiert durch Aktualisierung unmittelbar nach Zusammenführung. Live-Text
wird ausdrücklich als noch nicht sprecherzugeordnet markiert. Bei mindestens zehn
Sekunden erkannter, aber untranskribierter Sprache bleibt ein generativer Bericht
zurückgestellt; die Quellenübersicht und Aufnahme bleiben verfügbar. Diese Schwelle
ist ein konservativer Vollständigkeitshinweis, kein Qualitätsnachweis.

Whisper auf isolierter Lücke liefert zusätzlichen, weiterhin teils fraglichen Text.
Nur Abschalten des Stille-Schwellwerts behebt es nicht; Verstärkung verschlechterte
den Ausschnitt. Parakeet und Qwen-ASR zeigen ebenfalls erkennbare Abweichungen. Mit
bekannter Anzahl drei erhält Community-1 drei Gruppen; Identitätsrichtigkeit bleibt
unbewiesen, deshalb nicht als automatisch behobene Sprechererkennung übernommen.
139 App-Tests und 35 Python-Tests bestanden. Neu gepackte Test-App geöffnet;
Bericht für dieselbe Aufnahme per UI neu angefordert: `needs-transcript-review`,
Hinweis auf fehlende Sprache und zwei automatisch erkannte Sprecher sichtbar.
Die Listen-Sprecherzahl wird jetzt ebenfalls vor dem Bericht aktualisiert. [Befund](validation/2026-09-21-room-three-failure.json).
Originalaufnahme bleibt unter der bestätigten Sieben-Tage-Regel; keine neuen
Audio-Kopien außerhalb der Sitzung. Allan bestätigte danach unterschiedliche Abstände: er direkt vor dem MacBook,
eine Person weiter weg, die dritte noch weiter. Neue Anweisung: andere Modelle
oder Aufbereitung für bessere Erkennung von Anfang an prüfen und umsetzen.
Keine weitere Aufnahme angefordert. Ein isolierter Vergleich mit anderer
Whisper-Decodierung und Sprachverbesserung nutzt dieselbe Originalaufnahme.

## Raumtest: neue experimentelle Verarbeitung

Auf derselben 106-s-Aufnahme arbeitet faster-whisper Large-v3 (CPU/int8, Beam 5,
VAD) auf dem Originalton. Es liefert 203 statt 128 Wörter; die zuvor weitgehend
fehlende Passage ist teilweise wieder enthalten. Das ist ein Vollständigkeits-
hinweis, keine nachgewiesene Wortfehlerrate. Ein zweiter historischer 21-s-Ausschnitt
wurde ebenfalls verglichen, ohne menschlich bestätigte Referenz.

MossFormerGAN SE 16K bereitet ausschließlich den Mikrofonton für Community-1 auf.
Die Analyse findet damit automatisch drei statt zwei Gruppen, ohne vorgegebene
Teilnehmerzahl. Identitätsrichtigkeit bleibt ungeprüft. Derselbe aufbereitete Ton
verschlechterte teils die Worterkennung; daher bleiben ASR und Wiedergabe beim
Original. Systemton bleibt unbearbeitet. Vorbereitung, ASR und Sprecheranalyse
laufen nacheinander in getrennten, netzgesperrten Prozessen. Modellrevisionen und
Python-Pakete sind festgeschrieben; die normale Paply-App bleibt unverändert.

Neue Zwischen-WAVs bleiben unter derselben Sieben-Tage-Frist. Unterbrechung und
Wiederaufnahme der Aufbereitung, fehlende Zwischenkopie, abgelaufene Audiodaten,
Original-/Ableitungshashes und unveränderte ASR-Quelle sind automatisiert geprüft.
140 App- und 37 Python-Tests bestanden. Test-App gebaut und ad-hoc-Signatur geprüft;
die vier vorhandenen TypeScript-Fehler bleiben unverändert. Der echte Durchlauf
reproduziert den Vergleichstext und die aufbereitete Audiodatei identisch.
Vollständiger Durchlauf abgeschlossen (`ready`), Bericht als `local-draft`.
Aktualisierte Test-App geöffnet und das echte Gespräch darin geprüft: drei Sprecher,
Transkript verfügbar, Quellenbelege und sichtbare unklare Zuordnungen. Die Aufnahme
bleibt zur Prüfung geöffnet; Allan muss nichts installieren oder neu aufnehmen.
[Messung und Grenzen](validation/2026-09-21-room-acoustic-improvement.json).

## Erneuter Raumtest: Ursachenprüfung statt weiterer Umbau

Allan bestätigte nach erneutem Fehlschlag: zunächst beide neuen Aufnahmen prüfen,
keine weiteren blinden Modellwechsel und keine neue Nutzeraufnahme verlangen.
Der Programmstand und die Test-App wurden bei dieser Ursachenprüfung nicht verändert.

Der 30-s-Test hat im gespeicherten Original mit unverändertem Community-1 automatisch
**drei** Gruppen. Die aktivierte Aufbereitung reduziert sie auf **zwei**; die zweite
Gruppe liegt ausschließlich in vom Modell als überlappend markierten Bereichen. Die konservative Wortzuordnung
zeigt deshalb nur **eine** eindeutig zugeordnete Stimme. Im 106-s-Test gilt das Gegenteil:
Original zwei, aufbereitet drei. Damit ist die pauschale Aufbereitung als verlässlicher
Standard nicht bestätigt und zeigt einen konkreten Rückschritt. Gruppenanzahl allein beweist weiterhin keine Identitätsrichtigkeit.

Zusätzlich startet der gespeicherte Mikrofonton im zweiten Test 3,993 s nach dem
App-Startzeitpunkt; keine Warnung gespeichert. Der Code meldet Aufnahme schon vor
abgeschlossenem getUserMedia/AudioWorklet-Start; seine Endzeitprüfung erkennt diesen
Anfangsverlust nicht. Das beweist eine Startverzögerung, nicht welche Worte davor
gesprochen wurden. Keine Übersteuerung festgestellt, Systemspur in beiden Raumtests
vollständig digital still. Hörverständlichkeit ist damit nicht menschlich bestätigt.

Der gesamte erkannte Wortlaut bleibt bei beiden Zusammenführungen erhalten.
Die frühere MLX-Erkennung auf demselben 30-s-Original benötigt isoliert 10,3 s;
die aktuelle Pipeline hatte Text nach 26,5 s, zugeordnete Ausgabe nach 83,1 s und
Bericht nach 246,9 s ab Stop. Unterschiedliche Wörter, keine bestätigte WER-Referenz:
kein bewiesener Genauigkeitsgewinn der langsameren Erkennung.

Nächste technische Korrekturen: pauschale Aufbereitung zurücknehmen, Aufnahmebereitschaft
und Startlücken sichtbar/prüfbar machen; danach Sprecher- und Textqualität an denselben
Referenzen vergleichen. Vor einer erneuten Testfreigabe konkrete Sprecherreferenz prüfen.
Allan wurde nur um Zuordnung dreier bereits vorhandener Äußerungen gebeten.
[Ursachenbeleg](validation/2026-09-21-two-room-root-cause.json).

## Akustische Stabilität ohne Nutzerzuordnung geprüft

Allan möchte keine Namen oder manuelle Sprecherreferenz liefern. Bestätigter nächster
Schritt: akustische Stimmenmerkmale, Wiedererkennung und Verfahrenswidersprüche prüfen;
kein Zuordnen anhand des Gesprächsinhalts. Diese Prüfung ist abgeschlossen, ohne die
App erneut zu ändern und ohne neue Aufnahme oder Audio-Kopien anzulegen.

Originalton beider neuen Aufnahmen mit Community-1 sowie FluidAudio offline verglichen.
Community-1 zusätzlich bei halber Amplitude und einer Sekunde vorangestellter Stille
(in RAM, Zeitversatz korrigiert) geprüft: kurzer Test durchgehend drei Gruppen,
langer durchgehend zwei. Zuordnungen auf beidseitig als Einzelstimme erkannten
Zeitabschnitten stimmen nach Abgleich der neutralen Kennungen zu etwa 98,6–99,9 %
überein. Das ist Stabilität, ausdrücklich KEINE Sprecher-Genauigkeit.

FluidAudio findet in beiden Aufnahmen zwei Gruppen. Auf vergleichbaren Abschnitten
stimmen die beiden Verfahren nur zu rund 67–69 % überein; abweichende Sprachaktivität
und Überlappungen sind separat erfasst. Widersprüchliche Zeitintervalle gespeichert.
Im kurzen Original sind 13 von 26 ausgegebenen Sprecherabschnitten kürzer als 0,2 s.
Diese kurzzeitigen Sprünge erklären einen Teil der zerstückelten Zuordnung; sie dürfen
nicht einfach durch kontextbasiertes Umsortieren verdeckt werden.

Stimmenmerkmale aus sechs bzw. 19 separat extrahierten, mindestens einsekündigen,
modellseitig nicht überlappten Ausschnitten verglichen. Ähnlichkeitsbereiche derselben
und unterschiedlicher zugeordneter Gruppen überlappen deutlich. Der Merkmalsextraktor
ist zudem Teil der ursprünglichen Gruppierung, also kein unabhängiger Richtigkeitsbeweis.
Keine kalibrierte Identitätswahrscheinlichkeit, keine Namensbestimmung, keine Freigabe.

Praktische Konsequenz bleibt: Originalton als Grundlage, pauschale Aufbereitung nicht
als Standard, kurzfristige Grenzwechsel und Verfahrenswidersprüche gezielt prüfen.
Keine weiteren Nutzeraufnahmen oder Namensangaben für diese technischen Schritte nötig.
Der Benchmark hat eine getrennte Übereinstimmungsmessung mit exakten Zeitintervallen;
41 Python-Tests bestanden. [Belege](validation/2026-09-21-acoustic-stability.json).

## Offen / nächster Schritt

- Qwen3.5-9B mit Ollama0.34.2 liefert jetzt strukturell gültige Berichte auf zwei
  Beispielen; inhaltlich weiterhin unzulässige Vereinfachungen/Zuordnungen. Nicht
  aktiviert. Qwen3.8-27B lokal geprüft: bessere Kontrollfälle, aber auf echtem Gespräch
  ebenfalls eine unzulässig veränderte Bedingung. Zusätzliche Aussagenprüfung wird
  praktisch überprüft: Selbstprüfung übersah den Fehler; Denkmodus mit strukturierten
  Ausgaben scheiterte zusätzlich am lokalen Ollama-Fehler. Kein Fakten-Gate daraus
  ableiten. Berichte bleiben als Entwurf gekennzeichnet:
  [Berichtsgrenzen](validation/2026-09-21-report-review.json). Qwen3-8B und Gemma3-4B
  hatten Rollen-/Bedeutungsfehler und bleiben ungeeignet für eine Freigabe.
- Erneute UI-Prüfung bestanden: zwei Sprecher ohne Mitzählen unklarer Zuordnung;
  Wiedergabe auch nach gespeicherter Korrektur bei 17,64 s. PDF vollständig und lesbar
  auf zwei A4-Seiten geprüft. Mikrofon-Neuverbindung erhält erkannte Zeitlücken mit
  Stille; automatischer Test bestanden, echte Gerätewechsel noch ausstehend.
- Echte Aufnahmeberechtigungen, Gerätewechsel, neue lange Aufnahmen und Raum/Telefon/
  Mischsituation praktisch abnehmen. Systemtonbeginn derzeit aus erster Ankunft
  geschätzt; keine nachgewiesene hardwareübergreifende Langzeitsynchronität.
- Menschlich bestätigte Referenz fehlt: 95 % Sprecherzeit, ≤10 % WER und vollständige
  faktentreue Berichte sind weiterhin Prüfziele. Kurze Anisa-Aufnahme kann TV enthalten.
- Größere Modelle/weitere Sprecherverfahren nur anhand realer Qualitätsverbesserung
  auswählen. Keine Umstellung auf kostenpflichtige Dienste.
- Instinct-Empfang weiterhin nicht nachgewiesen; GitHub-Sichtbarkeit reicht nicht.

Private Rohaufnahmen, Transkripte, Modellartefakte und Laufzeitprotokolle bleiben
lokal in ignoriertem `work/` bzw. im separaten Test-App-Datenordner.
