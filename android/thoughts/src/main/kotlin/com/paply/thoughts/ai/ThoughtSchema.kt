package com.paply.thoughts.ai

import com.paply.thoughts.TopicIcon
import com.paply.thoughts.model.ThoughtJSON
import kotlinx.serialization.json.*

object ThoughtSchema {
    const val name = "paply_thought"
    const val partName = "paply_thought_part"
    val symbols
        get() = TopicIcon.entries.map { it.rawValue }

    private fun obj(vararg properties: Pair<String, JsonElement>): JsonObject = buildJsonObject {
        put("type", "object")
        put("additionalProperties", false)
        put("required", JsonArray(properties.map { it.first }.sorted().map(::JsonPrimitive)))
        put("properties", JsonObject(properties.toMap()))
    }

    private val string
        get() = buildJsonObject { put("type", "string") }

    private val nullableString
        get() = buildJsonObject {
            put("type", JsonArray(listOf("string", "null").map(::JsonPrimitive)))
        }

    private fun enumeration(values: List<String>) = buildJsonObject {
        put("type", "string")
        put("enum", JsonArray(values.map(::JsonPrimitive)))
    }

    private fun array(items: JsonElement) = buildJsonObject {
        put("type", "array")
        put("items", items)
    }

    val task
        get() = obj("text" to string, "quote" to string, "due_hint" to nullableString)

    val full
        get() =
            obj(
                "title" to string,
                "clean_text" to string,
                "topic" to
                    obj(
                        "choice" to enumeration(listOf("existing", "new", "none")),
                        "id" to nullableString,
                        "new_name" to nullableString,
                        "symbol" to enumeration(symbols),
                    ),
                "tasks" to array(task),
                "related" to
                    array(
                        obj(
                            "ref" to string,
                            "kind" to enumeration(listOf("continues", "same_matter", "changes")),
                            "reason" to string,
                            "confidence" to enumeration(listOf("high", "medium", "low")),
                        ),
                    ),
            )

    val part
        get() = obj("clean_text" to string, "tasks" to array(task))

    fun data(schema: JsonObject) = ThoughtJSON.sorted(schema).toString().toByteArray(Charsets.UTF_8)
}
