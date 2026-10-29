# CAM++ → CoreML

Quelle und Hash: `provenance.json`. Das Modell entspricht dem in der Pilotmessung verwendeten ONNX-Export. Die CoreML-Dateien sind klein genug für das App-Bundle (14 MB); keine zusätzliche ONNX-Runtime.

Reproduktion auf dem Mac:

```sh
python3 -m venv ~/paply-gsp-bench/venv-cam
~/paply-gsp-bench/venv-cam/bin/pip install --no-cache-dir -r ios/tools/gespraeche-bench/cam-coreml/requirements-lock.txt
~/paply-gsp-bench/venv-cam/bin/python ios/tools/gespraeche-bench/cam-coreml/convert.py
```

Die Konvertierung ergänzt fehlende Rank-Metadaten im onnx2torch-Adapter (BatchNorm1d und AveragePool1d), nutzt einen statischen 800-Frame-Eingang und FP16-Gewichte. Das erzeugte Paket liegt unter `~/paply-gsp-bench/CAMPlus.mlpackage`. Die ursprünglichen ONNX-Gewichte bleiben unverändert. `skip_model_load=True` vermeidet eine ungefragte ANE-Kompilierung während des Exports; Paply lädt CAM++ auf CPU.

Parität: drei identische 8-s-Ausschnitte von ES2004a.Array1-01 bei 10, 80 und 200 s. ONNX Runtime CPU und kaldi-native-fbank als Referenz; 16 kHz, normiertes Audio, 80 Bänder, 20–7600 Hz, Povey, kein Dither, `snip_edges=false`, Mittelwertabzug. Gegen die vollständige Swift-Fbank/CoreML-Ausgabe ergeben sich Kosinuswerte 0,999682 / 0,999789 / 0,999628. Dies prüft Konvertierung und Vorverarbeitung, nicht die Identifikationsqualität auf neuen Personen. Der Swift-Test `CAMFbankTests` prüft zusätzlich gegen Kaldi-Referenzwerte einschließlich Randfenstern.

Das temporäre venv nach der Prüfung löschen. Die Modelle in `~/paply-gsp-bench/models` behalten.
