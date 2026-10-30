package com.paply.thoughts.local

import kotlin.math.ln

/** Rebuildable in-memory derivative of the store; no embeddings.bin in Android V1. */
class LocalIndex {
    data class Entry(
        val id: String,
        val contentHash: ULong,
        val language: String?,
        val terms: Map<String, Int>,
    ) {
        val length: Int
            get() = terms.values.sum()
    }

    private val documents = linkedMapOf<String, Entry>()
    private val frequencies = mutableMapOf<String, Int>()
    val entries: Map<String, Entry>
        get() = documents.toMap()

    val documentFrequency: Map<String, Int>
        get() = frequencies.toMap()

    var totalLength = 0
        private set

    val count
        get() = documents.size

    val averageLength
        get() = if (count == 0) 1.0 else maxOf(1.0, totalLength.toDouble() / count)

    operator fun get(id: String) = documents[id]

    fun upsert(entry: Entry) {
        remove(entry.id)
        val copy = entry.copy(terms = entry.terms.toMap())
        documents[copy.id] = copy
        totalLength += copy.length
        for (term in copy.terms.keys) frequencies[term] = (frequencies[term] ?: 0) + 1
    }

    fun remove(id: String) {
        val old = documents.remove(id) ?: return
        totalLength -= old.length
        for (term in old.terms.keys) {
            val next = (frequencies[term] ?: 1) - 1
            if (next > 0) frequencies[term] = next else frequencies.remove(term)
        }
    }

    fun idf(term: String): Double {
        val df = (frequencies[term] ?: 0).toDouble()
        return ln(1 + (count - df + 0.5) / (df + 0.5))
    }

    fun bm25(query: Map<String, Int>, document: Entry, k1: Double = 1.2, b: Double = 0.75): Double {
        val norm = k1 * (1 - b + b * document.length / averageLength)
        return query.keys.sumOf { term ->
            val f = document.terms[term]?.toDouble() ?: return@sumOf 0.0
            idf(term) * f * (k1 + 1) / (f + norm)
        }
    }

    fun selfScore(query: Map<String, Int>, k1: Double = 1.2, b: Double = 0.75): Double {
        val norm = k1 * (1 - b + b * query.values.sum() / averageLength)
        return query.entries.sumOf { (term, count) ->
            val f = count.toDouble()
            idf(term) * f * (k1 + 1) / (f + norm)
        }
    }
}
