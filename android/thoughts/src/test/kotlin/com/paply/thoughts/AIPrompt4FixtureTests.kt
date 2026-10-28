package com.paply.thoughts

import com.paply.thoughts.ai.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class AIPrompt4FixtureTests {
    @Test
    fun expectedTasksMatchTheCodeAndTheValidator() {
        val f =
            Json.parseToJsonElement(javaClass.getResource("/prompt4.json")!!.readText()).jsonObject
        val cases = f.getValue("cases").jsonArray
        val regressions = f.getValue("regression").jsonArray
        assertEquals(6, cases.size)
        assertEquals(6, regressions.size)
        for (e in cases) {
            val item = e.jsonObject
            val id = item.getValue("id").jsonPrimitive.content
            val transcript = item.getValue("transcript").jsonPrimitive.content
            for (task in
                item
                    .getValue("expect")
                    .jsonObject
                    .getValue("tasks")
                    .jsonArray
                    .map { it.jsonObject }
                    .filter { it.getValue("required").jsonPrimitive.boolean }) {
                val dues =
                    (task["due_hint"] as? JsonArray).orEmpty().mapNotNull {
                        it.jsonPrimitive.contentOrNull
                    }
                dues.forEach {
                    assertTrue("$id due $it", ThoughtValidator.dueHintInQuote(it, transcript))
                }
                task.getValue("quote").jsonArray.forEach {
                    assertNotNull(
                        "$id quote",
                        ThoughtValidator.locateQuote(it.jsonPrimitive.content, transcript),
                    )
                }
                for (text in task.getValue("texts").jsonArray.map { it.jsonPrimitive.content }) {
                    assertEquals("$id form", text, TaskText.tidy(text, dues.firstOrNull()))
                    assertTrue(
                        "$id words $text",
                        ThoughtValidator.taskWordsGrounded(text, transcript),
                    )
                    assertTrue("$id digits", ThoughtValidator.digitsContained(text, transcript))
                    assertEquals(
                        "$id negation",
                        ThoughtValidator.effectiveNegations(transcript),
                        ThoughtValidator.effectiveNegations(text),
                    )
                }
            }
            for (w in listOf("Tilda", "Baumarkt")) assertFalse(transcript.contains(w))
        }
        val eval = javaClass.getResource("/eval.jsonl")!!.readText()
        regressions.forEach {
            assertTrue(
                eval.contains("\"id\": \"${it.jsonObject.getValue("id").jsonPrimitive.content}\""),
            )
        }
    }
}
