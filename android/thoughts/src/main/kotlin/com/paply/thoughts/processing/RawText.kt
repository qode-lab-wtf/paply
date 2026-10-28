package com.paply.thoughts.processing

import com.paply.core.TextAnalysis
import com.paply.thoughts.ThoughtTask
import com.paply.thoughts.model.TextForm
import com.paply.thoughts.nlp.TopicMentions
import java.util.Locale

object RawText {
    fun tidy(text: String): String {
        val collapsed =
            TextForm.trim(text.split(' ', '\t').filter { it.isNotEmpty() }.joinToString(" "))
        val out = StringBuilder()
        var next = true
        for (c in TextForm.characters(collapsed)) {
            val cp = c.codePointAt(0)
            if (next && Character.isLetter(cp)) {
                out.append(c.uppercase(Locale.ROOT))
                next = false
            } else {
                out.append(c)
                if (Character.isLetter(cp) || TextAnalysis.isNumber(cp)) next = false
            }
            if (c in listOf(".", "!", "?", "…", "\n")) next = true
        }
        return out.toString()
    }

    fun fallbackTitle(text: String): String {
        val words = TextForm.words(text)
        val head = words.take(6).joinToString(" ").trim { it in ".,;:!?…–- " }
        return if (head.isEmpty()) "Gedanke" else if (words.size > 6) "$head …" else head
    }

    fun key(text: String) =
        TextAnalysis.alphanumericRuns(TopicMentions.fold(text)).joinToString(" ")

    fun taskKey(text: String, dueHint: String?) = key(text) + "\u001f" + key(dueHint ?: "")

    fun sameTask(kept: ThoughtTask, draft: ThoughtTask): Boolean {
        if (key(kept.text) != key(draft.text)) return false
        val a = key(kept.dueHint ?: "")
        val b = key(draft.dueHint ?: "")
        return a.isEmpty() || b.isEmpty() || a == b
    }
}
