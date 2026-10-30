package com.paply.thoughts

import com.paply.thoughts.ai.*
import kotlinx.serialization.json.*
import okhttp3.mockwebserver.MockResponse

object AIFixture {
    val topics =
        listOf(
            TopicIndexEntry("t_paply", "Paply", 14, listOf("Tastatur", "Groq", "Sperrbildschirm")),
            TopicIndexEntry("t_umzug", "Umzug", 9, listOf("Wohnung", "Makler", "Kreuzberg")),
            TopicIndexEntry("t_wohnung", "Wohnung", 3, listOf("Miete")),
            TopicIndexEntry("t_lissabon", "Lissabon", 2, listOf("Reise")),
            TopicIndexEntry("t_garten", "Garten", 1, listOf("Tomaten", "Beet")),
        )
    val candidates =
        listOf(
            CandidateEntry(
                "s_oranien",
                "Wohnung Oranienstraße besichtigen",
                "t_umzug",
                "vor 2 Tagen",
                "Die Wohnung in der Oranienstraße hat zwei Zimmer und einen Balkon …",
                0.82,
            ),
            CandidateEntry(
                "s_tomaten",
                "Tomaten umtopfen",
                "t_garten",
                "gestern",
                "Die Tomaten brauchen größere Töpfe, am Wochenende umtopfen.",
                0.41,
            ),
            CandidateEntry(
                "s_sperr",
                "Sperrbildschirm-Knopf",
                "t_paply",
                "heute 08:10",
                "Der Knopf im Sperrbildschirm soll statt der Taschenlampe …",
                0.9,
            ),
            CandidateEntry("s_alt", "Alte Notiz", null, "12. Sep.", "Irgendwas.", 0.36),
        )
    const val transcript =
        "Ähm, also zur Wohnung in der Oranienstraße, ich hab jetzt nochmal mit dem Makler telefoniert. Die Miete ist 1.450 Euro warm und nicht verhandelbar. Ich muss bis Freitag die Unterlagen schicken. Und nicht vergessen, die Schufa-Auskunft zu bestellen."
    const val goodClean =
        "Zur Wohnung in der Oranienstraße: Ich habe jetzt nochmal mit dem Makler telefoniert. Die Miete ist 1.450 Euro warm und nicht verhandelbar.\n\nIch muss bis Freitag die Unterlagen schicken. Und nicht vergessen, die Schufa-Auskunft zu bestellen."

    fun input(
        transcript: String = this.transcript,
        topics: List<TopicIndexEntry> = this.topics,
        candidates: List<CandidateEntry> = this.candidates,
        topicsFull: Boolean = false,
        vocabulary: String = "",
        part: StructureInput.Part? = null,
        effort: String = "low",
    ) =
        StructureInput(
            transcript,
            emptyList(),
            listOf("de"),
            "de",
            vocabulary,
            topics,
            topicsFull,
            candidates,
            part,
            effort,
        )

    fun topic(choice: String, id: String? = null, name: String? = null, symbol: String = "home") =
        buildJsonObject {
            put("choice", choice)
            put("id", id?.let(::JsonPrimitive) ?: JsonNull)
            put("new_name", name?.let(::JsonPrimitive) ?: JsonNull)
            put("symbol", symbol)
        }

    fun task(text: String, quote: String, due: String? = null) = buildJsonObject {
        put("text", text)
        put("quote", quote)
        put("due_hint", due?.let(::JsonPrimitive) ?: JsonNull)
    }

    fun link(
        ref: String,
        kind: String = "continues",
        reason: String = "Gleiche Wohnung",
        confidence: String = "high",
    ) = buildJsonObject {
        put("ref", ref)
        put("kind", kind)
        put("reason", reason)
        put("confidence", confidence)
    }

    fun answer(
        title: String = "Wohnung Oranienstraße Unterlagen",
        clean: String = goodClean,
        topic: JsonObject = topic("existing", id = "t2"),
        tasks: List<JsonObject> = emptyList(),
        related: List<JsonObject> = emptyList(),
    ) = buildJsonObject {
        put("title", title)
        put("clean_text", clean)
        put("topic", topic)
        put("tasks", JsonArray(tasks))
        put("related", JsonArray(related))
    }
        .toString()

    fun validate(json: String, input: StructureInput = input(), selfID: String? = null) =
        ThoughtValidator.validate(json, input, ThoughtPrompt.build(input).aliases, selfID)
            .getOrThrow()

    fun reply(content: String, finish: String = "stop", total: Int = 3400) =
        MockResponse()
            .setResponseCode(200)
            .setHeader("Content-Type", "application/json")
            .setBody(
                buildJsonObject {
                    put(
                        "choices",
                        JsonArray(
                            listOf(
                                buildJsonObject {
                                    put("index", 0)
                                    put("finish_reason", finish)
                                    put(
                                        "message",
                                        buildJsonObject {
                                            put("role", "assistant")
                                            put("content", content)
                                        },
                                    )
                                },
                            ),
                        ),
                    )
                    put(
                        "usage",
                        buildJsonObject {
                            put("prompt_tokens", total - 900)
                            put("completion_tokens", 900)
                            put("total_tokens", total)
                        },
                    )
                }
                    .toString(),
            )
}
