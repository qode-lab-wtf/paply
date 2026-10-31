package com.paply.core

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class SharedLanguageTests(private val case: JsonObject) {
    @Test fun sharedDecision() {
        fun str(key: String) = case[key]?.jsonPrimitive?.contentOrNull
        val needed = LanguageGuard.needsCheck(str("expected"), str("detected"),
            case.getValue("users").jsonArray.map { it.jsonPrimitive.content },
            case.getValue("spoken").jsonPrimitive.double)
        assertEquals(str("name"), case.getValue("check").jsonPrimitive.boolean, needed)
        fun response(text: String, key: String) = Transcription(text = text,
            segments = listOf(WhisperSegment(start = 0.0, end = 1.0,
                avgLogprob = case[key]?.jsonPrimitive?.doubleOrNull)))
        val same = case["sameText"]?.jsonPrimitive?.booleanOrNull == true
        val expected = needed && LanguageGuard.chooseExpected(response("first", "lpDetected"),
            response(if (same) "first" else "second", "lpExpected"), case.getValue("spoken").jsonPrimitive.double)
        assertEquals(str("name"), str("result"), if (expected) "expected" else "detected")
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{index}: {0}")
        fun cases(): List<Array<JsonObject>> = Json.parseToJsonElement(
            File(checkNotNull(System.getProperty("paply.shared.language")), "faelle.json").readText()
        ).jsonArray.map { arrayOf(it.jsonObject) }
    }
}
