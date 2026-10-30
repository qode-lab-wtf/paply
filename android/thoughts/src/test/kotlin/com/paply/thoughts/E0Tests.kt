package com.paply.thoughts

import com.paply.thoughts.local.CandidateFinder
import com.paply.thoughts.model.ThoughtJSON
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

/** Offline port of CandidatesBench.swift (the E0 entry used by ThoughtsEval). No HTTP client. */
internal data class E0Fixture(
    val thoughts: List<Thought>,
    val topics: List<Topic>,
    val cases: List<Case>,
) {
    data class Case(
        val id: String,
        val recordedAt: Instant,
        val transcript: String,
        val languages: List<String>,
        val required: List<List<String>>,
        val optional: List<List<String>>,
        val expectedTopics: List<String>,
    )

    companion object {
        fun load(): E0Fixture {
            fun resource(name: String) =
                requireNotNull(E0Fixture::class.java.getResourceAsStream("/$name"))
                    .bufferedReader()
                    .use { it.readText() }
            val json = ThoughtJSON.json
            val store = json.parseToJsonElement(resource("store-a.json")).jsonObject
            val thoughts =
                store.getValue("thoughts").jsonArray.map { json.decodeFromJsonElement<Thought>(it) }
            val topics =
                store.getValue("topics").jsonObject.getValue("topics").jsonArray.map {
                    json.decodeFromJsonElement<Topic>(it)
                }
            val cases =
                resource("eval.jsonl")
                    .lineSequence()
                    .filter { it.isNotBlank() }
                    .map { line ->
                        val obj = json.parseToJsonElement(line).jsonObject
                        val expect = obj.getValue("expect").jsonObject
                        val related = expect["related"]?.jsonArray.orEmpty()
                        fun groups(status: String) =
                            related
                                .filter {
                                    it.jsonObject["status"]?.jsonPrimitive?.content == status
                                }
                                .map { row ->
                                    row.jsonObject.getValue("ids").jsonArray.map {
                                        it.jsonPrimitive.content
                                    }
                                }
                        val topic = expect.getValue("topic").jsonObject
                        val expected =
                            if (topic["choice"]?.jsonPrimitive?.content == "existing")
                                listOfNotNull(topic["id"]?.jsonPrimitive?.content) +
                                    topic["alsoAccept"]?.jsonArray.orEmpty().mapNotNull {
                                        (it as? JsonObject)?.get("id")?.jsonPrimitive?.content
                                    }
                            else emptyList()
                        Case(
                            obj.getValue("id").jsonPrimitive.content,
                            Instant.ofEpochMilli(obj.getValue("recordedAt").jsonPrimitive.long),
                            obj.getValue("transcript").jsonPrimitive.content,
                            obj.getValue("meta")
                                .jsonObject
                                .getValue("spokenLanguages")
                                .jsonArray
                                .map { it.jsonPrimitive.content },
                            groups("required"),
                            groups("optional"),
                            expected,
                        )
                    }
                    .toList()
            return E0Fixture(thoughts, topics, cases)
        }
    }
}

class E0Tests {
    @Test
    fun localQualityWithoutEmbeddings() = runBlocking {
        val fixture = E0Fixture.load()
        assertEquals(40, fixture.thoughts.size)
        assertEquals(14, fixture.topics.size)
        assertEquals(36, fixture.cases.size)
        val clock = TestClock()
        val finder = CandidateFinder(fixture.thoughts, fixture.topics, now = clock.function)
        var hits = 0
        var total = 0
        var top6 = 0
        var sent = 0
        var optionalHits = 0
        var optionalTotal = 0
        var top1 = 0
        var top3 = 0
        var topicTotal = 0
        val misses = mutableListOf<String>()
        for (item in fixture.cases) {
            clock.now = item.recordedAt
            val ranked = finder.rank(item.transcript, item.languages, "")
            val candidates = finder.candidates(item.transcript, item.languages, "")
            val ids = candidates.map { it.thoughtID }.toSet()
            assertTrue(candidates.size <= 7)
            sent += ids.size
            for (group in item.required) {
                total++
                if (group.any { it in ids }) hits++ else misses.add(item.id)
                if (ranked.take(6).any { it.thoughtID in group }) top6++
                val rank = ranked.indexOfFirst { it.thoughtID in group }
                println(
                    "E0 required ${item.id}: sent=${group.any { it in ids }} rank=${rank+1} score=${ranked.getOrNull(rank)?.score}",
                )
            }
            for (group in item.optional) {
                optionalTotal++
                if (group.any { it in ids }) optionalHits++
            }
            if (item.expectedTopics.isNotEmpty()) {
                topicTotal++
                val topics = finder.topicIndex(item.transcript, item.languages).entries
                val rank =
                    topics
                        .indexOfFirst { it.topicID in item.expectedTopics }
                        .let { if (it < 0) 999 else it + 1 }
                if (rank == 1) top1++
                if (rank <= 3) top3++
                if (rank != 1)
                    println(
                        "E0 topic ${item.id}: rank=$rank expected=${fixture.topics.filter { it.id in item.expectedTopics }.map { it.title }} top3=${topics.take(3).map { it.name }}",
                    )
            }
        }
        println(
            "E0 SUMMARY required=$hits/$total top6=$top6/$total optional=$optionalHits/$optionalTotal meanSent=${sent.toDouble()/36} topicTop1=$top1/$topicTotal topicTop3=$top3/$topicTotal misses=$misses",
        )
        assertEquals(11, total)
        assertEquals(29, topicTotal)
        assertTrue("Required $hits/$total; misses=$misses", hits >= 10)
        assertTrue("Topic top1 $top1/29", top1 >= 21)
        assertTrue("Topic top3 $top3/29", top3 >= 27)
    }
}
