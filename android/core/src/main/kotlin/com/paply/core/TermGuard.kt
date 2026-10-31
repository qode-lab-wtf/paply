package com.paply.core

import java.text.Normalizer
import java.util.Locale

internal object TermGuard {
    const val gap = 0.05
    const val spellingRatio = 0.6
    private val punctuation = Regex("[^\\p{L}\\p{N} ]")
    private val spaces = Regex("\\s+")
    private val marks = Regex("\\p{M}")
    private val repeats = Regex("(.)\\1+")
    private val separators = Regex("[,;\n\r]")
    private val substitutions = listOf("sch" to "s","ch" to "k","ph" to "f","ck" to "k","qu" to "k","th" to "t","dt" to "t","x" to "ks","[vfw]" to "w","[cqg]" to "k","[zs]" to "s","b" to "p","d" to "t","[^a-z]" to "","[aeiouyhj]" to "").map { Regex(it.first) to it.second }
    fun norm(text: String) = text.lowercase(Locale.ROOT).replace(punctuation, " ").replace(spaces, " ").trim()
    fun key(text: String): String {
        var s = Normalizer.normalize(text.lowercase(Locale.ROOT), Normalizer.Form.NFD).replace(marks, "").replace("ß","ss")
        for ((a,b) in substitutions) s = s.replace(a,b)
        return s.replace(repeats, "$1")
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
    private fun plain(text: String) = Normalizer.normalize(text, Normalizer.Form.NFD).replace(marks, "").replace(" ", "")
    private class Windows(text: String) {
        val words = norm(text).split(" ")
        val cache = mutableMapOf<Pair<Int,Int>, Pair<String,String>>()
        fun get(i: Int, length: Int) = cache.getOrPut(i to length) {
            val text = words.subList(i,i+length).joinToString(" ")
            key(text) to plain(text)
        }
    }
    private fun window(term: String, cache: Windows): Pair<Int,Int>? {
        val t = norm(term); val k = key(term); val p = plain(t)
        if (k.length < 3 || (" " + cache.words.joinToString(" ") + " ").contains(" $t ")) return null
        val n = t.split(" ").size+1
        val limit = kotlin.math.ceil(p.length * spellingRatio).toInt()
        for (i in cache.words.indices) for (length in 1..minOf(n,cache.words.size-i)) {
            val (x, spelling) = cache.get(i,length)
            if (x.length >= 3 && kotlin.math.abs(x.length-k.length) <= (if(k.length >= 4) 1 else 0) && distance(x,k) <= (if(k.length >= 4) 1 else 0) && distance(spelling,p) <= limit) return i to length
        }
        return null
    }
    fun near(term: String, text: String) = window(term,Windows(text)) != null
    fun accept(term: String, first: String, second: String, lpFirst: Double?, lpSecond: Double?): Boolean {
        if (lpFirst == null || lpSecond == null || !lpFirst.isFinite() || !lpSecond.isFinite() || lpSecond < lpFirst-gap) return false
        val cache = Windows(first); val t = norm(term); val s = " " + norm(second) + " "
        if (!s.contains(" $t ")) return false
        val (i,length) = window(term,cache) ?: return false
        val f = cache.words
        val rest = f.take(i) + f.drop(i+length)
        val parts = s.split(" $t ")
        if (parts.size > 2 && rest.size < 3) return false
        val left = parts.joinToString(" ").split(" ").filter { it.isNotEmpty() }.toMutableList()
        val gone = mutableListOf<String>()
        for (word in rest) if (!left.remove(word)) gone += word
        val allow = rest.size/10
        if (gone.size <= allow && left.size <= allow) return true
        return gone.size == allow+1 && left.size <= allow && rest.size >= 4 && (gone.contains(f.getOrNull(i-1)) || gone.contains(f.getOrNull(i+length)))
    }
    data class Candidates(val terms: List<String>, val prompt: String)
    fun candidates(vocabulary: String, response: Transcription): Candidates {
        val cache = Windows(response.text.orEmpty())
        val selected = vocabulary.split(separators).asSequence().map { it.trim() }.filter { it.isNotEmpty() && window(it,cache) != null }.take(3).toList()
        return Candidates(selected, selected.joinToString(" ") { "$it, $it." })
    }
}
