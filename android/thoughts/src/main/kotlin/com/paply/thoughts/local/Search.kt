package com.paply.thoughts.local

import com.paply.core.TextAnalysis
import com.paply.thoughts.Thought
import com.paply.thoughts.model.SearchHit
import com.paply.thoughts.model.TextForm
import com.paply.thoughts.nlp.TopicMentions
import java.time.Instant

object ThoughtSearch {
    fun fold(text: String) =
        TopicMentions.plain(TextAnalysis.normalizedLower(text)).replace("ß", "ss")

    fun tokens(query: String) = TextAnalysis.alphanumericRuns(fold(query)).distinct()

    internal fun haystack(text: String): String =
        TextAnalysis.alphanumericRuns(fold(text)).let {
            if (it.isEmpty()) "" else " " + it.joinToString(" ") + " "
        }
}

/** Fold once on upsert, then AND word prefixes across fields. All highlight offsets are UTF-16. */
class ThoughtSearchIndex {
    private data class Field(val kind: SearchHit.Field, val text: String) {
        val weight = weights.getValue(kind)
        val words = TextAnalysis.runs(text, TextAnalysis::isWordScalar)
        val folded = words.map { ThoughtSearch.fold(it.word) }
        val haystack = if (folded.isEmpty()) "" else " " + folded.joinToString(" ") + " "
    }

    private data class Doc(val id: String, val createdAt: Instant, val fields: List<Field>)

    private data class Match(val doc: Doc, val score: Double, val hits: List<Int>)

    private val docs = linkedMapOf<String, Doc>()
    val count
        get() = synchronized(this) { docs.size }

    @Synchronized
    fun upsert(thought: Thought, topicName: String? = null, raw: String? = null) {
        val fields = mutableListOf<Field>()
        fun add(kind: SearchHit.Field, text: String?) {
            if (!text.isNullOrEmpty()) fields.add(Field(kind, text))
        }
        add(SearchHit.Field.title, thought.title)
        add(SearchHit.Field.text, thought.text)
        thought.tasks.forEach { add(SearchHit.Field.task, it.text) }
        add(SearchHit.Field.topic, topicName)
        add(SearchHit.Field.raw, raw)
        docs[thought.id] =
            Doc(thought.id, thought.createdAt, fields.filter { it.haystack.isNotEmpty() })
    }

    @Synchronized
    fun remove(id: String) {
        docs.remove(id)
    }

    fun search(query: String, limit: Int = 300): List<SearchHit> {
        val tokens = ThoughtSearch.tokens(query)
        if (tokens.isEmpty() || limit <= 0) return emptyList()
        val list = synchronized(this) { docs.values.toList() }
        val needles = tokens.map { " $it" }
        return list
            .mapNotNull { doc -> evaluate(doc, needles) }
            .sortedWith(
                compareByDescending<Match> { it.score }.thenByDescending { it.doc.createdAt },
            )
            .take(limit)
            .map { match ->
                val field =
                    match.doc.fields.indices
                        .filter { match.hits[it] > 0 }
                        .minWithOrNull(
                            compareByDescending<Int> { match.hits[it] }
                                .thenBy { snippetOrder.indexOf(match.doc.fields[it].kind) },
                        )
                        ?.let { match.doc.fields[it] }
                val snippet = field?.let { snippet(it, tokens) } ?: ("" to emptyList())
                SearchHit(
                    match.doc.id,
                    field?.kind ?: SearchHit.Field.text,
                    snippet.first,
                    snippet.second,
                    match.score,
                )
            }
    }

    private fun evaluate(doc: Doc, needles: List<String>): Match? {
        var score = 0.0
        val hits = MutableList(doc.fields.size) { 0 }
        for (needle in needles) {
            var best = 0.0
            for ((i, field) in doc.fields.withIndex()) if (field.haystack.contains(needle)) {
                hits[i]++
                best = maxOf(best, field.weight)
            }
            if (best == 0.0) return null
            score += best
        }
        return Match(doc, score, hits)
    }

    private fun snippet(
        field: Field,
        tokens: List<String>,
        before: Int = 30,
        length: Int = 120,
    ): Pair<String, List<IntRange>> {
        val text = field.text
        if (field.words.isEmpty()) return text to emptyList()
        fun matching(index: Int) =
            tokens.filter { field.folded[index].startsWith(it) }.maxByOrNull(TextForm::count)
        fun distance(start: Int, end: Int) = TextForm.count(text.substring(start, end))
        val first = field.words.indices.firstOrNull { matching(it) != null } ?: 0
        var startWord = 0
        if (distance(0, field.words[first].start) > before) {
            startWord = first
            while (
                startWord > 0 &&
                    distance(field.words[startWord - 1].start, field.words[first].start) <= before
            ) startWord--
        }
        val start = if (startWord == 0) 0 else field.words[startWord].start
        var endWord = field.words.lastIndex
        var end = text.length
        if (distance(start, end) > length) {
            endWord = startWord
            while (
                endWord + 1 < field.words.size &&
                    distance(start, field.words[endWord + 1].end) <= length
            ) endWord++
            end = field.words[endWord].end
        }
        val prefix = if (start == 0) "" else "…"
        val suffix = if (end == text.length) "" else "…"
        val ranges =
            (startWord..endWord).mapNotNull { i ->
                val token = matching(i) ?: return@mapNotNull null
                val word = field.words[i]
                val lower = prefix.length + word.start - start
                val markedLength = TextForm.prefix(word.word, TextForm.count(token)).length
                lower until lower + markedLength
            }
        return (prefix + text.substring(start, end).replace('\n', ' ') + suffix) to ranges
    }

    companion object {
        private val weights =
            mapOf(
                SearchHit.Field.title to 4.0,
                SearchHit.Field.topic to 3.0,
                SearchHit.Field.task to 2.0,
                SearchHit.Field.text to 1.5,
                SearchHit.Field.raw to 1.0,
            )
        private val snippetOrder =
            listOf(
                SearchHit.Field.text,
                SearchHit.Field.task,
                SearchHit.Field.raw,
                SearchHit.Field.title,
                SearchHit.Field.topic,
            )
    }
}
