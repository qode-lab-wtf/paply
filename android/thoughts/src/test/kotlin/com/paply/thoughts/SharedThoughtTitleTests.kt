package com.paply.thoughts

import com.paply.thoughts.ai.ThoughtValidator
import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class SharedThoughtTitleTests(private val case: JsonObject) {
    @Test fun sharedTitle() {
        fun str(key: String) = case.getValue(key).jsonPrimitive.content
        val checked = ThoughtValidator.checkedTitle(str("title"), str("transcript"),
            case.getValue("spoken").jsonArray.map { it.jsonPrimitive.content }, str("ui"))
        val input = AIFixture.input(transcript = str("transcript")).copy(
            spokenLanguages = case.getValue("spoken").jsonArray.map { it.jsonPrimitive.content }, uiLanguage = str("ui"))
        val result = AIFixture.validate(AIFixture.answer(title = str("title"), clean = str("transcript")), input)
        assertEquals(str("name"), !case.getValue("ok").jsonPrimitive.boolean, "title" in result.rejections)
        assertEquals(str("name"), case.getValue("ok").jsonPrimitive.boolean, checked != null)
    }
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{index}: {0}")
        fun cases(): List<Array<JsonObject>> = Json.parseToJsonElement(
            File(checkNotNull(System.getProperty("paply.shared.thoughts")), "titel-faelle.json").readText()
        ).jsonArray.map { arrayOf(it.jsonObject) }
    }
}
