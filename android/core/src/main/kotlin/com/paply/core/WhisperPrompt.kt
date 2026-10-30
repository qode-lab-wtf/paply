package com.paply.core

internal object WhisperPrompt {
    const val tokenLimit = 200
    const val primerTokenShare = 64
    const val vocabularyTokenShare = 90

    fun scalarCost(s: Int) =
        when {
            s <= 0x24f -> 1
            s < 0x800 -> 2
            else -> s.scalarString().toByteArray(Charsets.UTF_8).size
        }

    fun estimateTokens(text: String): Int =
        text.words().sumOf { word ->
            var asciiAlnum = 0
            var cost = 0
            for (s in word.scalars()) if (s < 128 && (Character.isAlphabetic(s) || s in 48..57))
                asciiAlnum++
            else cost += scalarCost(s)
            maxOf(1, cost + (asciiAlnum + 1) / 2)
        }

    fun build(vocabulary: String, previousText: String?, primer: String? = null): String? {
        val parts = mutableListOf<String>()
        var used = 0
        primer
            ?.trimmed()
            ?.takeIf { it.isNotEmpty() && estimateTokens(it) <= primerTokenShare }
            ?.let {
                parts += it
                used += estimateTokens(it)
            }
        var vocab = PolishPrompt.vocabularyPrompt(vocabulary)
        if (estimateTokens(vocab) > vocabularyTokenShare)
            vocab = truncateItems(vocab, vocabularyTokenShare)
        if (vocab.isNotEmpty()) {
            val item = if (vocab.endsWith('.')) vocab else "$vocab."
            parts += item
            used += estimateTokens(item)
        }
        previousText
            ?.trimmed()
            ?.takeIf { it.isNotEmpty() }
            ?.let { tailWords(it, tokenLimit - used).takeIf(String::isNotEmpty)?.let(parts::add) }
        return parts.joinToString(" ").takeIf(String::isNotEmpty)
    }

    fun truncateItems(vocab: String, budget: Int): String {
        val kept = mutableListOf<String>()
        for (item in vocab.split(", ")) {
            if (estimateTokens((kept + item).joinToString(", ")) > budget) break
            kept += item
        }
        return kept.joinToString(", ")
    }

    fun tailWords(text: String, budget: Int): String {
        if (budget <= 0) return ""
        val words = text.words()
        var used = 0
        var start = words.size
        while (start > 0) {
            val cost = estimateTokens(words[start - 1])
            if (used + cost > budget) break
            used += cost
            start--
        }
        if (start == words.size && words.isNotEmpty()) {
            val scalars = words.last().scalars()
            var i = scalars.size
            var cost = 0
            while (i > 0) {
                val c = scalarCost(scalars[i - 1])
                if (cost + c > budget) break
                cost += c
                i--
            }
            return scalars.drop(i).joinToString("") { it.scalarString() }
        }
        return words.drop(start).joinToString(" ")
    }
}
