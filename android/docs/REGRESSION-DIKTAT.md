# Diktat-Regression: Ursachenanalyse

29.10.2026 · Nur Analyse/Dokumentation; kein Build/Gradle, kein Groq, kein Commit/Push. Zeilen beziehen sich auf `f9323b9`, nicht auf parallele Änderungen.
Pfadkürzel: A=`android/app/src/main/java/com/paply/android/`, C=`android/core/src/main/kotlin/com/paply/core/`, T=`android/thoughts/src/main/kotlin/com/paply/thoughts/`.

- **Ergebnis:** Keine neue Ursache für F1/F2 bewiesen. Arbeitshypothese: unterschiedliches aufgenommenes Signal bzw. Whisper-Ergebnis an anderen Stückgrenzen; ein Verlust innerhalb des PCM-Puffers ist nicht erkennbar.
- **Beweisgrenze:** `android/docs/E2E-FINAL.md:28–38` beschreibt dieselbe *Vorlage* in zwei Aufnahmen, keinen identischen Capture. Online-WAV, rohe HTTP-Antworten und vollständiges Release-Log fehlen lokal (`:49–52`); auch drei F2-Uploads sind dort nicht nachgewiesen.
- **Aliasing widerlegt:** A`AudioCapture.kt:107,135–136` kopiert genau `count`; A`dictation/DictationSession.kt:179` reicht synchron an `append`; C`DictationPipeline.kt:147,181,609–616` kopiert nochmals vor asynchroner Verarbeitung.
- **Leseschleife:** A`AudioCapture.kt:117–136` konsumiert jeden positiven Read einmal, 0 nur mit Warten, Fehler mit Abbruch/Rebuild; kein Doppel-Append. Puffergröße und Nonblocking-Read sind seit `da5cc3f` gleich. Hardware-/gRPC-Overruns sind damit nicht ausgeschlossen.
- **Neue Verlustmöglichkeit vor append:** A`AudioCapture.kt:125–136` überspringt stumm gemeldete Blöcke vollständig; A`dictation/ImePolicy.kt:49–56` pollt 1 Hz, Callback aktualisiert dazwischen (`AudioCapture.kt:53–56`). Ein veraltetes Flag kann den Anfang kosten, aber WAV und Live verlieren dieselben Blöcke; nur Capture-Logs können das bestätigen.
- **Offsets widerlegt:** C`ChunkPlanner.kt:29–36` liefert angrenzende exklusive Framegrenzen; C`DictationPipeline.kt:177–181,537–545` multipliziert beide Grenzen mit 480 und beginnt den Rest am letzten Ende. VAD-pending behält Teilframes (`VoiceActivityDetector.kt:227–243`); keine neue Offsetarithmetik im Diff.
- **VAD/Latch:** C`DictationPipeline.kt:147–151` puffert *vor* der Spracherkennung; der neue inkrementelle Latch (`VoiceActivityDetector.kt:131–166`) schaltet Erkennung/Uploads frei, verwirft keine Anfangssamples. Ein verspäteter Latch allein erklärt F1 nicht.
- **LongSilence/discard ausgeschlossen:** C`PublicAPI.kt:77` setzt `removeLongSilence=false`; A`dictation/DictationSession.kt:35–42` überschreibt das nicht. Daher ist C`DictationPipeline.kt:547–550` im IME aus. `discardSilentStart()` hat keinen App-Aufrufer (`rg`); Vorlauf bleibt erhalten.
- **Vorwärmen/Rücksprung ausgeschlossen:** A`dictation/DictationSession.kt:189–196` startet zuerst Audio, wärmt daneben nur HTTP vor; A`PaplyIme.kt:208–249` schaltet erst nach fertigem Text/Einsetzen zurück.
- **Retry ist weiterhin gestückelt:** A`dictation/DictationSession.kt:71–74,149–153` nutzt dieselbe Pipeline, aber 3200 Samples ohne Echtzeittakt statt maximal 320. Damit können kurze Pausen anders getroffen werden; „Retry korrekt“ isoliert weder Chunking noch Codec.
- **Konkretester Code-Kandidat für F2:** C`DictationPipeline.kt:540–545` lässt den ganzen Rest weg, wenn `hasAnyActivity` fehlschlägt; C`VoiceActivityDetector.kt:205–225,315–316` kann leise Sprache unter −70 dBFS übersehen. Das existiert schon in `da5cc3f`, erklärt keinen fehlenden Anfang und ist kein Nachweis einer neuen Regression.
- **Weiterer alter Kandidat:** C`ChunkPlanner.kt:8,19–31` zählt anfängliche Wartezeit zu den 10 s; nach langem Vorlauf kann bereits eine frühe 600-ms-Satzpause schneiden. Das kann kurze Whisper-Stücke mit viel Stille erzeugen, ist aber ebenfalls unverändert.
- **Zusammensetzen:** C`DictationPipeline.kt:452–488` wartet auf Stücke und verbindet in Planreihenfolge. `SilenceFilter.kt:230–244`/`TranscriptCleanup.kt:22–38,53–68` können Antworttext entfernen; ohne rohe Segmente/History-Rohtext ist Erkennung gegen Filter/Polieren nicht abgrenzbar. Diese Funktionen sind unverändert.
- **Bestätigter Nebenfehler:** A`AudioCapture.kt:135` → T`store/WAVWriter.kt:37` → C`AudioEncoder.kt:81–87` verändert beim WAV-Speichern positive PCM16-Werte um −1 LSB (32767→32766); Live behält das Original. Minimalfix hierfür: PCM16 direkt speichern. Das erklärt keine fehlenden Wörter.
- **Minimalfix für den F2-Kandidaten:** Rest nach bereits erkannter Sprache erhalten; nur nachweislich stille Samples auslassen, nicht den ganzen Rest wegen `hasAnyActivity=false`. Vorher den untenstehenden leisen Restfall bestätigen. Für F1 ist ohne Capture-/Uploadvergleich kein belastbarer Verhaltensfix ableitbar.
- **FLAC:** A`dictation/AndroidAdapters.kt:47–125` ist unverändert. Ein WAV-Fallback nach HTTP 400 beweist keine Korrektur erfolgreich transkribierter, verstümmelter Antworten. JVM-WAV-Test isoliert PCM/Plan/HTTP; Android-MediaCodec benötigt später separat einen Decode-Samplevergleich mit den echten Stücken.

Testvorschlag für `:core:test`, **nur hier, nicht implementiert/ausgeführt**: bestehende `MockServer`/`Groq`/`Synth`-Helfer verwenden. Zwei echte PCM16/16-kHz/Mono-WAVs unter JVM-Property `paply.regression.fixtures` bereitstellen; fehlende Fixtures müssen fehlschlagen. 320/3200er-Blöcke, 0/2/20 s Stille und sofortiges Überschreiben jedes Blocks prüfen Live/Retry und Ownership; samplebasierter Planner ohne nötigen Echtzeittakt. Eindeutige Quellpositionen sind das unabhängige Orakel, nicht HTTP-Reihenfolge. Eine 300-ms-Stimmmarke schützt den Vollabgleich vor absichtlich ausgelassenem stillem Nachlauf; der zusätzliche leise Restfall ohne Marke soll die bestehende Lücke zeigen. Der synthetische Normalfall erzwingt drei Stücke.

```kotlin
package com.paply.core
import kotlinx.coroutines.*
import okio.ByteString.Companion.toByteString
import okio.ByteString.Companion.encodeUtf8
import org.junit.Assert.*
import org.junit.Test
class RegressionAudioTest {
  private fun pcm(b: ByteArray) = java.nio.ByteBuffer.wrap(b).order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().let { v -> ShortArray(v.remaining()).also { v.get(it) } }
  private fun wav(f: java.io.File) = javax.sound.sampled.AudioSystem.getAudioInputStream(f).use { a ->
    val f = a.format; require(f.encoding == javax.sound.sampled.AudioFormat.Encoding.PCM_SIGNED && f.sampleRate == 16000f && f.channels == 1 && f.sampleSizeInBits == 16 && !f.isBigEndian); pcm(a.readBytes()) }
  private fun upload(r: okhttp3.mockwebserver.RecordedRequest): ByteArray {
    val b = r.body.clone().readByteString(); val h = b.indexOf("name=\"file\";".encodeUtf8()); require(h >= 0)
    val s = b.indexOf("\r\n\r\n".encodeUtf8(), h); require(s >= 0)
    val boundary = r.getHeader("Content-Type")!!.substringAfter("boundary=").trim('"')
    val e = b.indexOf("\r\n--$boundary".encodeUtf8(), s + 4); require(e >= s + 4)
    return b.substring(s + 4, e).toByteArray()
  }
  @Test fun uploadsCoverSourceExactly() = runBlocking {
    val dir = java.io.File(requireNotNull(System.getProperty("paply.regression.fixtures")))
    val probe = Synth.speech(11.0) + Synth.silence(.9) + Synth.speech(11.0, -32.0) + Synth.silence(.9) + Synth.speech(2.0, -28.0)
    val weak = Synth.speech(11.0) + Synth.silence(.9) + Synth.speech(2.0, -72.0)
    val fixtures = listOf(wav(java.io.File(dir, "testname.wav")), wav(java.io.File(dir, "long.wav")), AudioEncoder.int16(probe), AudioEncoder.int16(weak))
    for ((case, fixture) in fixtures.withIndex()) for (pad in listOf(0, 32000, 320000)) for (blockSize in listOf(320, 3200)) for (chunked in listOf(false, true)) {
      val src = ShortArray(pad) + fixture + if (case == 3) shortArrayOf() else AudioEncoder.int16(Synth.voice(.3, -20.0))
      val expected = AudioEncoder.wav(src).let { it.copyOfRange(44, it.size) }.toByteString()
      val hits = java.util.concurrent.CopyOnWriteArrayList<Pair<Int, ByteArray>>()
      MockServer { r, _ ->
        val w = upload(r); val data = w.copyOfRange(44, w.size); val start = expected.indexOf(data.toByteString())
        hits += start to w; Groq.transcription("Abschnitt $start.")
      }.use { server ->
        val p = server.pipeline(PaplySettings(language = "de", chunkedUpload = chunked), PipelineOptions(uploadFormat = PipelineOptions.UploadFormat.wav, polish = false, codeSwitchPrimer = false))
        val out = p.use { for (i in src.indices step blockSize) { val b = src.copyOfRange(i, minOf(i + blockSize, src.size)); p.append(b); b.fill(0) }; withTimeout(10000) { p.finish() } }
        assertNull(out.error); assertTrue(hits.isNotEmpty()); if (case == 2 && chunked) assertEquals(3, hits.size)
        var cursor = 0; val ordered = hits.sortedBy { it.first }
        for ((start, w) in ordered) {
          val data = w.copyOfRange(44, w.size).toByteString(); assertTrue(data.size > 0); assertTrue(start >= 0); assertEquals(0, start % 2)
          assertEquals(start, expected.lastIndexOf(data)); assertEquals(cursor, start); assertArrayEquals(AudioEncoder.wav(pcm(data.toByteArray())), w)
          assertEquals(expected.substring(start, start + data.size), data); cursor += data.size
        }
        assertEquals(expected.size, cursor); assertEquals(ordered.joinToString(" ") { "Abschnitt ${it.first}." }, out.raw)
      }
    }
  }
}
```
