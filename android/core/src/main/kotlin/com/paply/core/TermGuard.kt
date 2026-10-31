package com.paply.core

import java.text.Normalizer
import java.util.Locale

internal object TermGuard {
    const val gap = 0.05
    fun norm(text: String) = text.lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{N} ]"), " ").replace(Regex("\\s+"), " ").trim()
    fun key(text: String): String {
        var s = Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD).replace(Regex("\\p{M}"), "").replace("ß","ss")
        for ((a,b) in listOf("sch" to "s","ch" to "k","ph" to "f","ck" to "k","qu" to "k","th" to "t","dt" to "t","x" to "ks","[vfw]" to "w","[cqg]" to "k","[zs]" to "s","b" to "p","d" to "t","[^a-z]" to "","[aeiouyhj]" to "")) s = s.replace(Regex(a),b)
        return s.replace(Regex("(.)\\1+"), "$1")
    }
    fun distance(a: String, b: String): Int {
        var row = IntArray(b.length+1) { it }
        for ((i,x) in a.withIndex()) {
            val next = IntArray(b.length+1); next[0] = i+1
            for ((j,y) in b.withIndex()) next[j+1] = minOf(row[j+1]+1,next[j]+1,row[j]+if(x==y) 0 else 1)
            row = next
        }
        return row[b.length]
    }
    fun near(term: String, text: String): Boolean {
        if (norm(text).contains(norm(term))) return false
        val k = key(term); val w = norm(text).split(" "); val n = norm(term).split(" ").size+1
        for (i in w.indices) for (length in 1..minOf(n,w.size-i)) {
            val x = key(w.subList(i,i+length).joinToString(" "))
            if (x.length >= 2 && distance(x,k) <= if(k.length >= 4) 1 else 0) return true
        }
        return false
    }
    fun accept(term: String, first: String, second: String, lpFirst: Double?, lpSecond: Double?): Boolean {
        if (lpFirst == null || lpSecond == null || !lpFirst.isFinite() || !lpSecond.isFinite()) return false
        val f = norm(first); val s = norm(second); val t = norm(term)
        if (f.contains(t) || !s.contains(t) || lpSecond < lpFirst-gap) return false
        val a = f.split(" ").toSet(); val b = s.split(" ").toSet(); val n = t.split(" ").size
        return (b-a).size <= n+1 && (a-b).size <= n+2
    }
    data class Candidates(val terms: List<String>, val prompt: String)
    fun candidates(vocabulary: String, response: Transcription): Candidates {
        val terms = vocabulary.split(Regex("[,;\n\r]")).map { it.trim() }.filter { it.isNotEmpty() }
        val selected = terms.filter { near(it,response.text.orEmpty()) }.take(3).toMutableList()
        val uncertain = selected.isEmpty() && response.segments.orEmpty().any { (it.avgLogprob ?: 0.0) < -0.5 }
        if (uncertain) for (term in terms) {
            if (WhisperPrompt.estimateTokens((selected+term).joinToString(", ")) > 90) break
            selected += term
        }
        return Candidates(selected, if(selected.isEmpty()) "" else if(uncertain) selected.joinToString(", ") else selected.joinToString(" ") { "$it, $it." }+" Hallo ${selected.first()}.")
    }
}
