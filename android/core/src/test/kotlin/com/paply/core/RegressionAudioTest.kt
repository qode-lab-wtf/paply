package com.paply.core
import kotlinx.coroutines.*
import okio.ByteString.Companion.toByteString
import okio.ByteString.Companion.encodeUtf8
import org.junit.Assert.*
import org.junit.Test
class RegressionAudioTest {
  // Linear-time matching, including long zero prefixes (ByteString.indexOf is quadratic).
  private fun positions(source: ByteArray, needle: ByteArray): List<Int> {
    require(needle.isNotEmpty())
    val prefix = IntArray(needle.size)
    var j = 0
    for (i in 1 until needle.size) {
      while (j > 0 && needle[i] != needle[j]) j = prefix[j - 1]
      if (needle[i] == needle[j]) j++
      prefix[i] = j
    }
    val found = mutableListOf<Int>(); j = 0
    for (i in source.indices) {
      while (j > 0 && source[i] != needle[j]) j = prefix[j - 1]
      if (source[i] == needle[j]) j++
      if (j == needle.size) { found += i - j + 1; j = prefix[j - 1] }
    }
    return found
  }
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
  @Test fun silenceNeverUploads() = runBlocking {
    MockServer { _, _ -> error("Silence must not upload") }.use { server ->
      server.pipeline().use { p ->
        repeat(1000) { p.append(ShortArray(320)) }
        assertTrue(p.finish().noSpeech)
        assertTrue(server.requests.isEmpty())
      }
    }
  }
  @Test fun uploadsCoverSourceExactly() = runBlocking {
    val dir = System.getProperty("paply.regression.fixtures")?.let { java.io.File(it) }
    val probe = Synth.speech(11.0) + Synth.silence(.9) + Synth.speech(11.0, -32.0) + Synth.silence(.9) + Synth.speech(2.0, -28.0)
    val weak = Synth.speech(11.0) + Synth.silence(.9) + Synth.speech(2.0, -72.0)
    val fixtures = listOf(AudioEncoder.int16(probe), AudioEncoder.int16(weak)) + (dir?.let { listOf(wav(java.io.File(it, "testname.wav")), wav(java.io.File(it, "long.wav"))) } ?: emptyList())
    for ((case, fixture) in fixtures.withIndex()) for (pad in listOf(0, 32000, 320000)) for (blockSize in listOf(320, 3200)) for (chunked in listOf(false, true)) for (paced in if (case >= 2 && pad == 0 && blockSize == 320 && chunked) listOf(false, true) else listOf(false)) {
      val src = ShortArray(pad) + fixture + if (case == 1) shortArrayOf() else AudioEncoder.int16(Synth.voice(.3, -20.0))
      val expected = AudioEncoder.wav(src).let { it.copyOfRange(44, it.size) }.toByteString()
      val hits = java.util.concurrent.CopyOnWriteArrayList<Pair<Int, ByteArray>>()
      MockServer { r, _ ->
        val w = upload(r); val data = w.copyOfRange(44, w.size); val start = positions(expected.toByteArray(), data).singleOrNull() ?: -1
        hits += start to w; Groq.transcription("Abschnitt $start.")
      }.use { server ->
        val p = server.pipeline(PaplySettings(language = "de", chunkedUpload = chunked), PipelineOptions(uploadFormat = PipelineOptions.UploadFormat.wav, polish = false, codeSwitchPrimer = false))
        val out = p.use { for (i in src.indices step blockSize) { val b = src.copyOfRange(i, minOf(i + blockSize, src.size)); p.append(b); b.fill(0); if (paced) delay(20) }; withTimeout(10000) { p.finish() } }
        assertNull(out.error); assertTrue(hits.isNotEmpty()); if (case == 0 && chunked) assertEquals(3, hits.size)
        var cursor = 0; val ordered = hits.sortedBy { it.first }
        for ((start, w) in ordered) {
          val data = w.copyOfRange(44, w.size).toByteString(); assertTrue(data.size > 0); assertTrue(start >= 0); assertEquals(0, start % 2)
          assertEquals(listOf(start), positions(expected.toByteArray(), data.toByteArray())); assertEquals(cursor, start); assertArrayEquals(AudioEncoder.wav(pcm(data.toByteArray())), w)
          assertEquals(expected.substring(start, start + data.size), data); cursor += data.size
        }
        assertEquals(expected.size, cursor); assertEquals(ordered.joinToString(" ") { "Abschnitt ${it.first}." }, out.raw)
      }
    }
  }
}
