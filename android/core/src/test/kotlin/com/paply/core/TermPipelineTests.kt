package com.paply.core
import kotlinx.coroutines.runBlocking
import org.junit.Test

class TermPipelineTests {
    @Test fun countercheck() = runBlocking {
        for (mode in listOf("accept","reject","empty","fail","echo","plain","uncertain","silence")) {
            val input = when(mode) { "echo" -> "Lamin danke."; "silence" -> "Vielen Dank."; "plain", "uncertain" -> "Das Wetter ist heute schön."; else -> "Hallo Lavi Min, wie geht es dir?" }
            val one = mode in listOf("empty","plain","uncertain","silence")
            MockServer { _, index ->
                when {
                    index == 0 -> Groq.transcription(input, logprob = if(mode == "uncertain") -0.8 else -0.3)
                    mode == "fail" -> Groq.error(422)
                    else -> Groq.transcription(if(mode == "echo") "Law Min, Law Min." else "Hallo Law Min, wie geht es dir?", logprob = if(mode == "reject") -0.9 else -0.1)
                }
            }.use { server ->
                val p = server.pipeline(PaplySettings(chunkedUpload = false, spokenLanguages = listOf("de","en"), primaryLanguage = "de", vocabulary = if(mode == "empty") "" else "Law Min"), PipelineOptions(polish = false))
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                val result = p.finish()
                expect(server.requests.size == if(one) 1 else 2)
                org.junit.Assert.assertEquals(if(one) 3.0 else 6.0, result.timings.sentAudioSeconds, 0.01)
                if(!one) {
                    expect(server.requests[1].field("language") == "de")
                    expect(server.requests[1].field("prompt") == "Law Min, Law Min.")
                }
                expect(result.raw == if(mode == "accept") "Hallo Law Min, wie geht es dir?" else input)
                p.close()
            }
        }
    }
}
