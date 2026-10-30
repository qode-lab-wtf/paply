# On-device-Diarisierung: Pilotmessung vom 29.10.2026

**Status: Pilot, keine Freigabe einer Produktionsschwelle.** Der geforderte Nachweis
„möglichst keine falsch zugeordneten Sätze auf jedem iOS-18-iPhone“ ist damit nicht
geführt. App-Code und Diktat wurden nicht verändert; nichts wurde committet.

## Empfehlung und Haupttabelle

**Für den nächsten iPhone-Prototyp: FluidAudio mit Nemotron-3 `fast128` FP16,
blockweise, 50 ms Mindestturn; CAM++ separat für Profile.** Auf drei AMI-Meetings
zusammen: 15,1 % falsch/unbekannt zugeordnete Wörter statt 14,9 % bei VBx, aber nur
7,6 % tatsächlich falsch festgelegte Sprecher statt 13,0 %; der Rest ist „unbekannt“.
Fehlerhafte Referenzsegmente: 65,5 % statt 72,0 %. Das Ziel fast korrekturfreier
Gespräche erreicht **keiner**. Die einfachen deutschen Simulationen sind dafür
kein Gegenbeweis.

VBx ist die kompakte Alternative und kann K=2 ausdrücklich erzwingen. Nemotron
hat acht Slots, aber im getesteten Adapter keine exakte K-Vorgabe; ES2004b erhält
fünf statt vier Sprecher. Die W8A8-Version wird wegen der reproduzierten auffälligen
M1-Ausgaben nicht empfohlen, auch mit erzwungenem ANE-Pfad. Ursache offen.
Die spektrale Nachgruppierung hilft manchen Fällen, verschlechtert andere; deshalb
keine pauschale Android-Produktionsfreigabe und keine feste 0,7-Regel.

**Zellen: WDER % / fehlerhafte Referenzsegmente %.** Beide zählen „unbekannt“ als
Korrekturbedarf. Deutsche Segmente = Quellclips, AMI-Segmente = Satz-/Pausenproxy;
keine direkt vergleichbaren grammatischen Satzfehlerquoten. Je deutscher Bedingung
zwei 5-min-Mischungen; — = nicht gemessen. WeSpeaker auf ES2004a mit bekannter K=4
(Oracle-Ablation), sonst K=2 für T1/T3 und automatische Zahl für T2.

| Bedingung | Nemotron FP16, 50 ms | Community-1/VBx | CAM++ + Spektral | WeSpeaker |
|---|---:|---:|---:|---:|
| ES2004a | 19.4 / 69.2 | 18.8 / 75.0 | 19.8 / 79.2 | 50.4 / 86.2 |
| ES2004b | 12.5 / 65.2 | 12.1 / 70.8 | — | — |
| IS1009a | 18.4 / 61.4 | 19.3 / 70.9 | 28.0 / 77.2 | — |
| T1 | 0.0 / 0.0 | 2.5 / 22.2 | 0.0 / 0.0 | 26.0 / 30.6 |
| T2-3 | 0.1 / 2.8 | 0.7 / 8.3 | 18.7 / 27.8 | 48.5 / 50.0 |
| T2-4 | 0.0 / 0.0 | 0.4 / 5.6 | 12.4 / 16.7 | 63.0 / 66.7 |
| T2-5 | 0.3 / 2.8 | 1.1 / 19.4 | 0.7 / 8.3 | 63.1 / 69.4 |
| T3 | 0.0 / 0.0 | 2.4 / 19.4 | 24.4 / 25.0 | 26.6 / 33.3 |

[Alle 182 Messzeilen, einschließlich DER/JER, Sprecherzahl, RTF und Roh-/Glättungsvarianten](../../tools/gespraeche-bench/results/messwerte.csv)
· [vollständige lesbare Tabelle](../../tools/gespraeche-bench/results/ERGEBNISSE.md).
Finaler Scorer **v4**: gleiche Sprecherintervalle vereinigen; bei identischer
Zeitüberlappung mehrerer Sprecher abstinieren, statt durch zufällige Reihenfolge
eine Person auszuwählen. Frühere Zwischenstände im Arbeitsverlauf sind dadurch ersetzt.

| Modellpaket (ohne App-Runtime) | Gemessene Modelldateien | M1-Inferenz / Ressourcen |
|---|---:|---|
| Community-1 | 21,8 MB | AMI RTF 0,010–0,018; 90-min-Dateitest unten beschrieben |
| Nemotron fast128 FP16 | 199,1 MB | Blockweise AMI RTF ca. 0,004; 90 min: 106 MB Prozess-RSS |
| Nemotron c128 W8A8 | 100,0 MB | Schnell, hier aber unbrauchbare Ausgabe; keine Empfehlung |
| sherpa Segmentierung + CAM++ | 6,0 + 28,3 MB | AMI RTF 0,108–0,306 unter Last; ES2004a RSS bis 436 MB |
| sherpa Segmentierung + WeSpeaker | 6,0 + 26,5 MB | ES2004a RTF 0,623 unter Last; RSS 397 MB |

Download beim ersten Start statt in der IPA; Paketgrößen sind entpackte Dateien,
nicht gemessene IPA-Zuwächse. Nemotron plus CAM++ benötigt etwa 228 MB Gewichte.
Runtime-/Binarygröße nicht gemessen. sherpa 60/90-min-RAM nicht empirisch geprüft;
allein das Float32-Audio braucht 230/346 MB, dazu Modell-/Feature-/Clusterpuffer.

## Versuchsaufbau und Aussagegrenzen

Mac mini M1, 8 GB RAM, Swift 6.2. FluidAudio-Commit
`e15287985625dbf544a343df679436789ffb03fb`; Python-Versionen und Modellhashes in den
Ergebnisdateien. Einige Läufe liefen unter Konkurrenzlast: RTF ist die tatsächlich
beobachtete Laufzeit, kein isolierter Geschwindigkeitsvergleich. RTF = Sekunden
Rechenzeit / Sekunden Audio, kleiner ist schneller. Modellladen getrennt.

AMI: ES2004a, ES2004b und IS1009a, ausdrücklich **Array1-01**, zusammen ca. 70,6 min.
Manuelle Wörter aus AMI v1.6.2. Der aktuelle FluidAudio-Downloader bezeichnet
`Mix-Headset.wav` als SDM; diesen Download haben wir bewusst nicht verwendet.
DER/JER: Collar 0,25 s, Überlappung eingeschlossen, UEM ganze Datei. Die Referenz
wird aus manuellen Wörtern aufgebaut, nicht aus einem anders ausgerichteten RTTM.
[AMI-Referenzkonvention](https://github.com/pyannote/AMI-diarization-setup).

WDER zählt falsche **und unzugeordnete** Wörter nach optimaler globaler
Cluster↔Person-Zuordnung. Satzfehler zählt Referenzsegmente mit mindestens einem
solchen Wort; zusätzlich wird der Anteil mit falscher Mehrheit gespeichert.
AMI-Satzgrenzen sind Proxys aus Interpunktion/Pausen >0,8 s je Sprecher. Viele kurze
Einwürfe zählen dadurch stärker als in der Wortmetrik. Keine manuell geprüften
„grammatischen Sätze“; kein Anspruch auf Gleichheit mit dem späteren UI.

Deutsch: zehn deterministische Mischungen à 5 min aus
[MLS German](https://huggingface.co/datasets/facebook/multilingual_librispeech),
CC BY 4.0, echte Sprecher-IDs. T1 zwei Sprecher mit Bandpass 300–3400 Hz,
Mu-law-Quantisierung und Verzerrung für den entfernten Kanal; T2 drei/vier/fünf
Sprecher; T3 zwei im Raum. Reflexionen und Rauschen sind einfache Simulationen,
kein validiertes Raummikrofon-/Telefonmodell. Kein Nachweis gleichgeschlechtlicher
Paare, kein realistischer Test natürlicher „mhm/ja/genau“-Einwürfe. Wiederverwendete
Lesesprachclips machen die Mischungen statistisch abhängig.

Nur diese deutschen Mischungen gehen an Groq `whisper-large-v3`; Antworten werden
gehasht gecacht. Deutsche Wortzeiten stammen aus ASR, Sprecherwahrheit aus den
Quellclip-Intervallen. Mehrdeutige Überlappungswörter werden separat gezählt und
ausgeschlossen. Fehlende/halluzinierte ASR-Wörter sind nicht lexikalisch aligniert.
**Deutsche WDER ist deshalb eine bedingte Pilotmetrik; deutsche DER/JER sind nur
Zeitproxies, keine belastbare Goldreferenz.** Sie rechtfertigen keine Aussage
„0 % Fehler in echten Telefonaten“.

## Kandidaten, Lizenzen und Integration

| Motor | Code | Modellgewichte | Einordnung |
|---|---|---|---|
| FluidAudio Community-1, WeSpeaker, PLDA/VBx | Apache-2.0; Third-Party-Notices mitliefern | Community-1-Artefakte CC BY 4.0 | Direkte Swift/CoreML-Integration, OS-Mindeststand passt zu iOS 18 |
| sherpa-onnx + segmentation-3.0 + CAM++ advanced | Apache-2.0 | Segmentierung MIT; CAM++ laut ModelScope Apache-2.0, Exportprovenienz vor Vertrieb zusätzlich archivieren | CPU/ONNX; Android-nahe Referenz |
| sherpa-onnx + segmentation-3.0 + WeSpeaker ResNet34-LM | Apache-2.0 | Segmentierung MIT, **WeSpeaker-Gewichte CC BY 4.0** | Nicht pauschal aus Code-Lizenz auf Gewichte schließen |
| FluidAudio Nemotron-3 c128-split-w8a8 / fast128 | FluidAudio Apache-2.0 | OpenMDW 1.1 | Acht Sprecher, real verfügbarer CoreML-Kandidat seit Sep. 2026 |
| DiariZen v2 | MIT | CC BY-NC 4.0 | Für kommerzielles Paply ohne separate Rechte ausgeschlossen |
| Sortformer v2.1 | NeMo Apache-2.0 | NVIDIA Open Model License | Vier-Sprecher-Grenze passt nicht zu T2 mit fünf; Nachfolger Nemotron-3 ist relevanter |

Primärquellen: [FluidAudio](https://github.com/FluidInference/FluidAudio),
[genauer Community-1-/Legacy-Lizenzumfang](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/main/NOTICE.md),
[segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0),
[WeSpeaker-Modellkarte](https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34-LM),
[CAM++](https://modelscope.cn/models/iic/speech_campplus_sv_zh_en_16k-common_advanced),
[sherpa-Modelle](https://k2-fsa.github.io/sherpa/onnx/speaker-diarization/models.html),
[Nemotron-3](https://huggingface.co/nvidia/Nemotron-3-Diarization),
[CoreML-Presets](https://huggingface.co/FluidInference/nemotron-3-diarization-coreml),
[DiariZen](https://huggingface.co/BUT-FIT/diarizen-wavlm-large-s80-md-v2),
[Sortformer v2.1](https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1).
Keine zusätzliche SpeakerKit-Pipeline mit hier nachgewiesenem Vorteil aufgenommen.

Modellgewichte sollten nach ausdrücklichem Start der Funktion heruntergeladen und
anschließend offline verwendet werden; dadurch erhöht sich die initiale App-Größe
nur um Runtime/Code. Downloadgröße und entpackte CoreML-Größe sind verschieden.
Legacy-FluidAudio wurde nicht zusätzlich gemessen: seine Modelllizenzen sind im
verlinkten NOTICE getrennt dokumentiert, kein pauschaler Community-1-Lizenzumfang.

## Plattformneutral beschrieben

1. Mono 16 kHz, feste Zeitbasis; Engine liefert Sprachintervalle und Embeddings.
   Überlappung erhalten. Für Telefonate K=2 erzwingen, für Meetings VBx verwenden.
   Die getestete spektrale Heuristik ist keine belegte Verbesserung und kein Ersatz
   für die passende PLDA/VBx-Kalibrierung.
2. Für jedes Wort Zeitüberschneidung pro Sprecher aufsummieren, größte wählen.
   Ohne Evidenz „unbekannt“. Im Produktionspfad bei knapper Differenz ebenfalls
   abstinieren; Enthaltungsrate neben Fehlerquote berichten, damit nicht alles
   durch „unbekannt“ scheinbar richtig wird.
3. Beobachtbare Satzzeichen und Pausen >0,8 s bilden Glättungsgruppen. Nur bei
   ≥70 % Wortmehrheit ändern; Wörter mit normalisierter Differenz der zwei besten
   Überlappungssummen ≥0,6 behalten ihren Sprecher. Diese Werte sind experimentelle
   Startwerte, keine auf unabhängigen Daten optimierten Produktionsschwellen.
   Kurze sichere Einwürfe behalten; kleine Cluster nicht allein wegen Dauer löschen.
4. Profile aus 3–5 **separaten** Clips: normierte Embeddings, Medoid bestimmen,
   stark abweichende Clips verwerfen, normierten Mittelwert bilden. Nicht mit
   nachträglich zugeordneten unsicheren Gesprächssegmenten automatisch anlernen.
5. Clusterzentroid aus mehreren langen, überlappungsarmen Segmenten bestimmen.
   Profilvergleich im **gleichen Embeddingraum**; WeSpeaker und CAM++ nicht mischen.
   Besitzer nur bei absolutem Score UND Abstand zum zweitbesten Cluster akzeptieren.
   Sonst neutraler Sprecher. Kalibrieren mit unbekannten Personen, Besitzer-abwesend,
   getrennten Sitzungen und Nah-/Fernfeldwechsel. Dasselbe gilt für weitere Profile.
6. Android kann Schritte 2–5 identisch mit sherpa-Embeddings implementieren.
   Schwellen neu kalibrieren, sobald Modell/Quantisierung/Preprocessing wechseln;
   CoreML- und ONNX-Ausgaben durch identische Clips auf Cosinus-Parität prüfen.

## Noch nötige Freigabetests

Keine belastbare Falsch-Besitzer-Rate aus wenigen Personen: selbst 0 Fehler bei
N unabhängigen Negativfällen erlaubt grob noch 3/N als obere 95%-Grenze. Für <1 %
braucht es ungefähr 300 unabhängige Negativfälle, nicht 300 Varianten derselben Stimme.
Nahbesprechungsprofile, kontaminierte Enrollmentclips und AMI a→b–d müssen mit
getrennten Kalibrier-/Testsätzen umfassend geprüft werden.

„Jedes iPhone mit iOS 18“ umfasst auch iPhone XR/XS (A12), nicht nur iPhone 12/14.
Auf echten Geräten offen: CoreML-Fallback CPU/ANE, Modellkompilierung, Jetsam,
Wärme/Drosselung, Akku, Hintergrundausführung und Unterbrechungen, 60–90-min-Dateien.
16-kHz-Float32-Audio allein benötigt für 60/90 min 230/346 MB (dezimal); Float64
verdoppelt dies. Datei-/Chunkverarbeitung und begrenzte Featurepuffer sind Pflicht.
Clustering darf keine quadratische Matrix über alle 10-ms-Frames aufbauen.
Mac-RSS ist kein iOS-Jetsam-Nachweis. iPhone-12/14-Zeiten lassen sich nur sehr grob
als 1–5× Mac-Inferenzzeit budgetieren; das ist **eine Planungsspanne, keine Messung**,
und bei CPU-Fallback oder thermischer Drosselung keine garantierte Obergrenze.

## Zusätzliche gemessene Befunde

- **90 min, wiederholtes ES2004a, Speichertest (keine zusätzliche Qualitätsprobe):**
  VBx 74,02 s Wall inklusive Laden, 496 MB maximaler RSS, 869 MB Peak Footprint.
  Nemotron fast128 komplett: 32,20 s Wall, 942 MB RSS, 984 MB Footprint.
  Nemotron fast128 in 10-s-Leseblöcken: 26,36 s Wall, **106 MB RSS**, 65 MB Footprint.
  Alle 2.665 ausgegebenen Intervalle waren zwischen kompletter und Blockverarbeitung
  exakt identisch. CoreML-/ANE-Systemspeicher ist durch Prozess-RSS nicht vollständig
  abgedeckt; warme Systemcaches und Konkurrenzlast begrenzen den Vergleich.
- **CPU-Fallback-Smoke-Test:** Nemotron fast128, `.cpuOnly`, 60 s echte AMI-Daten:
  0,704 s Verarbeitung, 2,22 s Wall inklusive Laden, 431 MB RSS. Das belegt den
  ausführbaren CPU-Pfad auf diesem Mac, keine iPhone-Dauerleistung.
- **Kurze natürliche AMI-Turns:** Für Referenzsegmente mit höchstens zwei Wörtern
  liegen mit Standard-Minimaldauer die geglätteten Wortfehler bei VBx bei
  496/543 (91,3 %), Nemotron fast128 bei 358/543 (65,9 %). Lexikalische englische
  Einwürfe (`yeah`, `yes`, `right`, `okay`, usw.): 483/645 (74,9 %) versus
  364/645 (56,4 %). Das ist genau der Bereich, in dem globale WDER zu günstig wirkt.
- **Enrollment mit einem fremden Clip von drei:** CAM++-Medoid plus Cosinus 0,6
  verwarf in 30 konstruierten Fällen den fremden Clip, ohne einen der zwei richtigen
  zu verwerfen. Nicht getestet: zwei fremde Clips, Mischsprecher innerhalb eines
  Clips, Telefon-/Nahfeld-Domänenwechsel auf echten iPhones.
- **Besitzerprofil auf VBx-Clustern, CAM++, Score ≥0,8 und Abstand ≥0,1:**
  deutsche Simulation 30/32 Treffer (93,8 %), 0/268 falsche Besitzer bei Abwesenheit.
  AMI ES2004a→b: 2/4 Treffer; alle vier ES2004a-Profile auf IS1009a abwesend:
  0/4 falsch. Identitäten in AMI `meetings.xml` geprüft. Enrollment dort aus
  aneinandergehängten, nicht überlappenden Referenzwörtern der Fernfeldaufnahme:
  **kein realistisches Nahbesprechungsprofil**. Bei Score 0,6: 4/4 AMI-Treffer,
  aber zu wenig Negativmaterial, um diese niedrigere Schwelle freizugeben.
- WeSpeaker statt CAM++ war für dieses Profilverfahren erheblich schlechter:
  bei Score 0,8 nur 11/32 simulierte Treffer und 15/268 falsche Abwesenheits-Zuordnungen;
  AMI 1/4 Treffer und 2 falsche Zuordnungen über die acht Prüfungen. Deshalb hier
  keine Empfehlung für WeSpeaker als Besitzer-Embedding.

Für mehrere gleichzeitig gespeicherte Profile zusätzlich eine globale
Eins-zu-eins-Zuordnung mit „unbekannt“-Option einsetzen und den Abstand auch zum
zweitbesten **Profil** prüfen. Der Pilot prüft jeweils ein Besitzerprofil gegen
alle Cluster, nicht die vollständige gemeinsame Galeriezuordnung.

Die 50-ms-Variante verbessert die kurze-Turn-WDER auf 349/543 (64,3 %),
lexikalische Einwürfe auf 356/645 (55,2 %): weiterhin nicht gut genug.
CAM++ auf Nemotron-FP16-Clustern bestätigt in der Simulation bei 0,8 / Abstand 0,1
ebenfalls 30/32 Treffer und 0/268 falsche Abwesenheits-Zuordnungen. Diese Schwellen
sind nur Pilotwerte. Eine automatische Namenszuordnung sollte erst nach unabhängigen
Tests freigegeben werden.

## Abschluss und Ablage

Sechs Scorer-Regressionsprüfungen bestanden; alle 182 Messzeilen verwenden Scorer v4.
Groq: zehn unterschiedliche Dateien, zusammen **50 Audiominuten**, ausschließlich
`whisper-large-v3`; Antworten und Reservierungsledger bleiben für Wiederholungen erhalten.
Rohdaten, venv, Swift-Build, fremder Source-Checkout und eigene Download-/Buildcaches
wurden gelöscht. Unter `~/paply-gsp-bench/` bleiben **379 MiB**: etwa 374 MiB Modelle
und 5,1 MiB kleine JSON-Ergebnisse einschließlich Groq-Cache. Auf dem Datenvolume
sind danach rund 19 GiB frei. Keine fremden Caches oder App-Dateien angefasst.

## Implementierungsänderung nach Review 2

Der iOS-Adapter verteilt nun höchstens fünf CAM-Ausschnitte über den gesamten Verlauf eines Sprechers,
statt nur die längsten Turns auszuwählen. Paarweise zu stark abweichende Abdrücke liefern keinen automatisch
zuordenbaren Schwerpunkt. Fragmentcluster müssen mit allen Mitgliedern kompatibel sein. Die obigen
Pilotmesswerte wurden mit diesen Änderungen nicht erneut erhoben; eine neue Qualitätsmessung und der
Laufzeit-/Thermal-Test auf iOS 18 stehen aus.
