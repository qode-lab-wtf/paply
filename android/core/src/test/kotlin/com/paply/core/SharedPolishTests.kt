package com.paply.core

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.experimental.runners.Enclosed
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

/** Read the repository source directly: never maintain a module-local fixture copy. */
@RunWith(Enclosed::class)
class SharedPolishTests {
    class Prompt {
        @Test
        fun promptMatchesSharedSource() {
            assertArrayEquals(
                sharedFile("system-prompt.txt").readBytes(),
                PolishPrompt.systemPrompt.toByteArray(Charsets.UTF_8),
            )
        }
    }

    @RunWith(Parameterized::class)
    class SafetyCases(private val case: SafetyCase) {
        @Test
        fun safetyNetMatchesSharedCase() {
            val rejection = when (case.profile) {
                "thought" -> PolishSafetyNet.rejection(
                    case.raw, case.result, case.vocabulary, PolishSafetyNet.Profile.thought,
                )
                "dictation" -> PolishSafetyNet.rejection(
                    case.raw, case.result, case.vocabulary, PolishSafetyNet.Profile.dictation,
                )
                else -> PolishSafetyNet.rejection(
                    case.raw, case.result, case.vocabulary, case.strictEdits,
                )
            }
            assertEquals(case.toString(), case.expected, rejection)
        }

        companion object {
            @JvmStatic
            @Parameterized.Parameters(name = "{index}: {0}")
            fun cases(): List<Array<SafetyCase>> =
                Json.parseToJsonElement(sharedFile("safety-cases.json").readText(Charsets.UTF_8))
                    .jsonArray.map { element ->
                        val c = element.jsonObject
                        arrayOf(
                            SafetyCase(
                                raw = c.getValue("raw").jsonPrimitive.content,
                                result = c.getValue("result").jsonPrimitive.content,
                                vocabulary = c.getValue("vocabulary").jsonPrimitive.content,
                                expected = c.getValue("expected").jsonPrimitive.contentOrNull,
                                profile = c["profile"]?.jsonPrimitive?.contentOrNull,
                                strictEdits = c["strictEdits"]?.jsonPrimitive?.boolean ?: true,
                            ),
                        )
                    }
        }
    }
}

data class SafetyCase(
    val raw: String,
    val result: String,
    val vocabulary: String,
    val expected: String?,
    val profile: String?,
    val strictEdits: Boolean,
) {
    override fun toString() = "$raw → $result (profile=$profile, strictEdits=$strictEdits)"
}

private fun sharedFile(name: String) = File(
    checkNotNull(System.getProperty("paply.shared.polish")) {
        "Gradle must supply paply.shared.polish pointing to shared/polish in the repository"
    },
    name,
)
