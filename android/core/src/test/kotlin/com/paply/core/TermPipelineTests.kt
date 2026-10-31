package com.paply.core
import kotlinx.coroutines.runBlocking
import org.junit.Test

class TermPipelineTests {
    @Test fun countercheck() = runBlocking {
        for (mode in listOf("accept","reject","empty","fail")) {
            MockServer { _, index ->
                when {
                    index == 0 -> Groq.transcription("Hallo Lavi Min, wie geht es dir?", logprob = -0.3)
                    mode == "fail" -> Groq.error(422)
                    else -> Groq.transcription("Hallo Law Min, wie geht es dir?", logprob = if(mode == "reject") -0.9 else -0.1)
                }
            }.use { server ->
                val p = server.pipeline(PaplySettings(chunkedUpload = false, spokenLanguages = listOf("de","en"), primaryLanguage = "de", vocabulary = if(mode == "empty") "" else "Law Min"), PipelineOptions(polish = false))
                feed(p, Synth.withFloor(Synth.speech(3.0)))
                val result = p.finish()
                expect(server.requests.size == if(mode == "empty") 1 else 2)
                expect(result.raw == if(mode == "accept") "Hallo Law Min, wie geht es dir?" else "Hallo Lavi Min, wie geht es dir?")
                p.close()
            }
        }
    }
}
