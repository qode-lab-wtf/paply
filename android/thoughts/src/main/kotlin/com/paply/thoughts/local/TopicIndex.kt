package com.paply.thoughts.local

import com.paply.core.TextAnalysis
import com.paply.thoughts.*
import com.paply.thoughts.store.ThoughtStore
import kotlin.math.ln
import kotlin.math.sqrt

object TopicIndex : TopicSummarizing {
    const val maxActive = 24
    const val maxProvisional = 8
    const val maxMentioned = 8
    const val provisionalWindow = 60L * 24 * 3600
    const val dormantAfter = 90L * 24 * 3600

    fun isActive(topic: Topic, count: Int) = topic.owner == Owner.user || count >= 2

    override fun summaries(
        topics: List<Topic>,
        thoughts: List<Thought>,
    ): List<TopicSummarizing.Summary> {
        val members =
            thoughts
                .filter { it.deletedAt == null && it.state != ThoughtState.recording }
                .groupBy { ThoughtStore.resolve(it.topicId, topics)?.id }
        return topics
            .filter { it.mergedInto == null }
            .map { topic ->
                val list = members[topic.id].orEmpty()
                TopicSummarizing.Summary(
                    topic,
                    list.size,
                    list.maxOfOrNull { it.createdAt },
                    isActive(topic, list.size),
                    list.map { it.id },
                )
            }
    }

    internal data class Fit(val score: Double, val hint: List<String>)

    internal fun fit(
        summary: TopicSummarizing.Summary,
        index: LocalIndex,
        queryTerms: Map<String, Int>,
    ): Fit {
        val terms = mutableMapOf<String, Int>()
        for (id in summary.memberIDs) for ((term, count) in index[id]?.terms.orEmpty()) terms[
            term] = (terms[term] ?: 0) + count
        val nameTerms =
            TextAnalysis.letterRuns(summary.topic.title).map(Keywords::fold).filter {
                it.length >= 3
            }
        val hints = terms.toMutableMap()
        for (term in nameTerms) terms[term] = (terms[term] ?: 0) + 2
        summary.topic.describedNote?.let { note ->
            for (term in Keywords.terms(note, null)) terms[term] = (terms[term] ?: 0) + 1
        }
        for (term in nameTerms) hints.remove(term)
        return Fit(tfidfCosine(queryTerms, terms, index), Keywords.top(hints, 3, index::idf))
    }

    internal fun tfidfCosine(a: Map<String, Int>, b: Map<String, Int>, index: LocalIndex): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        fun weight(count: Int, term: String) = (1 + ln(count.toDouble())) * index.idf(term)
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for ((term, count) in a) {
            val w = weight(count, term)
            na += w * w
            b[term]?.let { dot += w * weight(it, term) }
        }
        for ((term, count) in b) {
            val w = weight(count, term)
            nb += w * w
        }
        return if (na > 0 && nb > 0) dot / (sqrt(na) * sqrt(nb)) else 0.0
    }
}
