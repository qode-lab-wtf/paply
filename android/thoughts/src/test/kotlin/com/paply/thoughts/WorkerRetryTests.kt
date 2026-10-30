package com.paply.thoughts

import com.paply.thoughts.processing.*
import com.paply.core.PaplySettings
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class WorkerRetryTests {
    @Test fun rejectedKeySurvivesNewWorkersAndOnlyNewKeyResumes() { runBlocking {
        Harness(transcriber = MockTranscriber(listOf(TranscriptionResult.Failure(TranscriptionFailure.unauthorized)))).use { h ->
            val id = h.capture()
            h.run()
            assertEquals(ThoughtState.waitingKey, h.thought(id)!!.state)
            fun worker() = ThoughtProcessor(h.store, h.structurer, h.finder, h.ledger,
                ProcessorEnvironment({ h.flags.key }, { true }, { false }, { PaplySettings() }, "de"),
                TestTopicIndex, h.finder, h.transcriber, ThoughtProcessor.Options(autoRetry = false), h.clock.function)
            repeat(10) { worker().use { it.kick("worker"); it.waitUntilIdle(); assertFalse(it.hasPendingWork()) } }
            assertEquals(1, h.transcriber.calls)
            assertFalse(h.root.resolve("rejected-key.sha256").toFile().readText().contains(h.flags.key!!))
            h.flags.key = "replacement-placeholder"
            worker().use { it.kick("key"); it.waitUntilIdle() }
            assertEquals(ThoughtState.done, h.thought(id)!!.state)
            assertEquals(2, h.transcriber.calls)
        }
    } }
    @Test fun limitAndNetworkNeverRetryBeforeDeadline() { runBlocking {
        for ((failure, seconds) in listOf(TranscriptionFailure.rateLimited to 900L, TranscriptionFailure.network to 30L)) {
            Harness(transcriber = MockTranscriber(listOf(TranscriptionResult.Failure(failure)))).use { h ->
                val id = h.capture(); h.run()
                assertEquals(h.clock.now.plusSeconds(seconds), h.thought(id)!!.status.retryAt)
                repeat(10) { h.run() }
                assertEquals(1, h.transcriber.calls)
            }
        }
    } }
}
