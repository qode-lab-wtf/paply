package com.paply.thoughts

import com.paply.thoughts.model.ThoughtJSON
import java.nio.file.*
import java.time.Instant

object StoreSupport {
    fun temporaryRoot(): Path = Files.createTempDirectory("paply-thought-tests-")

    fun remove(root: Path) {
        if (Files.exists(root))
            Files.walk(root).use { it.sorted(Comparator.reverseOrder()).forEach(Files::delete) }
    }

    fun thought(
        id: String = ThoughtIDs.thought(),
        createdAt: Instant = Instant.ofEpochSecond(1_793_093_400),
        state: ThoughtState = ThoughtState.done,
        title: String? = "Titel",
        text: String? = "Text",
        topicId: String? = null,
        languages: List<String> = listOf("de"),
    ) =
        Thought(
            id = id,
            createdAt = createdAt,
            durationMs = 4000,
            trigger = ThoughtTrigger.control,
            state = state,
            title = title,
            titleOwner = if (title == null) Owner.system else Owner.ai,
            text = text,
            textOwner = if (text == null) Owner.system else Owner.ai,
            topicId = topicId,
            topicOwner = if (topicId == null) Owner.system else Owner.ai,
            languages = languages,
            updatedAt = createdAt,
        )

    fun tone(seconds: Double, frequency: Double = 220.0) =
        FloatArray((seconds * 16000).toInt()) {
            (0.3 * kotlin.math.sin(2 * Math.PI * frequency * it / 16000)).toFloat()
        }

    fun source(text: String = "Hallo", at: Instant = Instant.ofEpochSecond(1_793_093_400)) =
        ThoughtSource(text, emptyList(), "whisper-large-v3", at, listOf("de"), 1.0)

    fun writeCorpus(count: Int, root: Path) {
        val words =
            listOf(
                "Wohnung",
                "Umzug",
                "Fluxo",
                "Beta",
                "Kita",
                "Garten",
                "Tomaten",
                "Halbmarathon",
                "Laufen",
                "Budget",
                "Familie",
                "Jana",
                "Mila",
                "Ben",
                "Porto",
                "Lissabon",
                "Flug",
                "Hotel",
                "Steuer",
                "Rechnung",
                "Investor",
                "Pitch",
                "Retention",
                "Android",
                "Kategorien",
                "Supabase",
                "Release",
                "Gitarre",
                "Akkorde",
                "Buch",
            )
        var previous: String? = null
        repeat(count) { i ->
            fun w(k: Int) = words[(i * 7 + k * 13) % words.size]
            val t =
                thought(
                        createdAt = Instant.ofEpochSecond(1_790_000_000L + i * 3600),
                        title = "${w(1)} und ${w(2)} planen",
                        text =
                            "Heute über ${w(1)} nachgedacht: ${w(3)} und ${w(4)} hängen zusammen. Bis Freitag ${w(5)} klären, danach ${w(6)} mit ${w(7)} besprechen. Ärger mit der Straße vermeiden, Café am Ende.",
                        topicId = "t_${i%20}",
                    )
                    .copy(
                        tasks =
                            listOf(
                                ThoughtTask(
                                    text = "${w(5)} klären",
                                    owner = Owner.ai,
                                    createdAt = Instant.EPOCH,
                                ),
                            ),
                        links =
                            previous?.let {
                                listOf(
                                    ThoughtLink(
                                        it,
                                        LinkKind.continues,
                                        "Gleiche Sache",
                                        Owner.ai,
                                        Instant.EPOCH,
                                    ),
                                )
                            } ?: emptyList(),
                    )
            val dir = Files.createDirectories(root.resolve("thoughts/${t.id}"))
            Files.write(dir.resolve("thought.json"), ThoughtJSON.encode(t))
            previous = t.id
        }
    }
}

class TestClock(var now: Instant = Instant.ofEpochSecond(1_793_093_400)) {
    fun advance(seconds: Long) {
        now = now.plusSeconds(seconds)
    }

    val function: () -> Instant
        get() = { now }
}
