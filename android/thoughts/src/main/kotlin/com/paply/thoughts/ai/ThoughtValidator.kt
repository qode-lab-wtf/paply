package com.paply.thoughts.ai

import com.paply.core.*
import com.paply.thoughts.*
import com.paply.thoughts.model.*
import com.paply.thoughts.nlp.SnowballLemmatizer
import java.text.Normalizer
import kotlinx.serialization.*

object ThoughtValidator {
    @Serializable
    data class RawTopic(
        val choice: String,
        val id: String? = null,
        val new_name: String? = null,
        val symbol: String? = null,
    )

    @Serializable
    data class RawTask(val text: String, val quote: String, val due_hint: String? = null)

    @Serializable
    data class RawRelated(
        val ref: String,
        val kind: String,
        val reason: String,
        val confidence: String,
    )

    @Serializable
    data class RawAnswer(
        val title: String,
        val clean_text: String,
        val topic: RawTopic,
        val tasks: List<RawTask>,
        val related: List<RawRelated>,
    )

    @Serializable data class RawPart(val clean_text: String, val tasks: List<RawTask>)

    class Failure(val code: Code) : Exception(code.name) {
        enum class Code {
            unreadable,
            empty,
        }
    }

    const val maxTasks = 5
    const val maxRelated = 3
    const val maxTitleLength = 60
    const val maxTaskLength = 80
    const val maxReasonLength = 60
    const val mediumLinkScore = 0.75
    private val lemmatizer: Lemmatizer = SnowballLemmatizer()

    fun validate(
        json: String,
        input: StructureInput,
        aliases: ThoughtPrompt.Aliases,
        selfID: String? = null,
    ): Result<StructureResult> {
        val a =
            runCatching { ThoughtJSON.json.decodeFromString<RawAnswer>(plainHyphens(json)) }
                .getOrNull() ?: return Result.failure(Failure(Failure.Code.unreadable))
        val rawTitle = TextForm.trim(a.title)
        val rawText = TextForm.trim(a.clean_text)
        if (rawTitle.isEmpty() && rawText.isEmpty())
            return Result.failure(Failure(Failure.Code.empty))
        val rejections = mutableListOf<String>()
        val clean = checkText(rawText, input, rejections)
        val title =
            checkedTitle(rawTitle, input.transcript)
                ?: fallbackTitle(clean ?: input.transcript).also { rejections.add("title") }
        val topic = checkedTopic(a.topic, input, aliases, rejections)
        val tasks = checkedTasks(a.tasks, input.transcript, rejections)
        val related = checkedRelated(a.related, input.transcript, aliases, selfID, rejections)
        return Result.success(StructureResult(title, clean, topic, tasks, related, rejections))
    }

    private fun checkText(
        rawText: String,
        input: StructureInput,
        rejections: MutableList<String>,
    ): String? {
        val reason =
            if (rawText.isEmpty()) "empty"
            else ThoughtSafetyNet.rejection(input.transcript, rawText, input.vocabulary)
        if (reason != null) {
            rejections.add("text:$reason")
            return null
        }
        return rawText
    }

    fun validatePart(json: String, input: StructureInput): Result<StructureResult> {
        val p =
            runCatching { ThoughtJSON.json.decodeFromString<RawPart>(plainHyphens(json)) }
                .getOrNull() ?: return Result.failure(Failure(Failure.Code.unreadable))
        val rejections = mutableListOf<String>()
        val clean = checkText(TextForm.trim(p.clean_text), input, rejections)
        val tasks = checkedTasks(p.tasks, input.transcript, rejections)
        return Result.success(
            StructureResult("", clean, TopicDecision.None, tasks, emptyList(), rejections),
        )
    }

    fun assemble(
        first: StructureResult,
        firstTranscript: String,
        parts: List<Pair<StructureResult, String>>,
    ): StructureResult {
        val pieces = mutableListOf(first.cleanText ?: TextForm.trim(firstTranscript))
        var anyClean = first.cleanText != null
        val rejections = first.rejections.toMutableList()
        val tasks = first.tasks.toMutableList()
        parts.forEachIndexed { i, (r, t) ->
            pieces.add(r.cleanText ?: TextForm.trim(t))
            if (r.cleanText != null) anyClean = true
            rejections.addAll(r.rejections.map { "part${i+2}:$it" })
            tasks.addAll(r.tasks)
        }
        return first.copy(
            cleanText = if (anyClean) pieces.joinToString("\n\n") else null,
            tasks = tasks.distinctBy { taskKey(it.text, it.dueHint) }.take(10),
            rejections = rejections,
        )
    }

    private val quoteCharacters = "\"'„“”‚‘’«»‹›「」『』".toSet()

    fun checkedTitle(raw: String, transcript: String): String? {
        var title =
            TextForm.trim(
                raw.split(Regex("[\\r\\n\\u000b\\u000c\\u0085\\u2028\\u2029]+")).firstOrNull {
                    it.isNotEmpty()
                } ?: "",
            )
        title =
            title
                .dropWhile { it in quoteCharacters || it == ' ' }
                .dropLastWhile { it in quoteCharacters || it in ".…!?:;,–—- " }
        title = title.split(' ', '\t').filter { it.isNotEmpty() }.joinToString(" ")
        return title.takeIf {
            TextForm.count(it) in 1..maxTitleLength &&
                digitsContained(it, transcript) &&
                sharesContentWord(it, transcript)
        }
    }

    fun fallbackTitle(text: String): String {
        val words =
            TextForm.words(text.replace("• ", " ")).filter {
                TextAnalysis.normalizedLower(it.replace(Regex("^\\p{P}+|\\p{P}+$"), "")) !in
                    Lexicon.fillers
            }
        if (words.isEmpty()) return "…"
        val head = words.take(6).joinToString(" ").trimEnd { it in ",;:." }
        return if (words.size > 6) "$head …" else head
    }

    fun checkedTopic(
        raw: RawTopic,
        input: StructureInput,
        aliases: ThoughtPrompt.Aliases,
        rejections: MutableList<String>,
    ): TopicDecision {
        fun reject(code: String): TopicDecision {
            rejections.add(code)
            return TopicDecision.None
        }
        return when (raw.choice) {
            "existing" ->
                aliases.topics[raw.id?.let(TextForm::trim)]?.let {
                    TopicDecision.Existing(it.topicID)
                } ?: reject("topic:alias")
            "new" -> {
                val name =
                    raw.new_name?.let(TextForm::trim)?.takeIf { it.isNotEmpty() }
                        ?: return reject("topic:name")
                val same = TopicHygiene.sameNamed(name, input.topics)
                if (same.size == 1) {
                    rejections.add("topic:duplicate")
                    return TopicDecision.Existing(same[0].topicID)
                }
                if (same.size > 1) return reject("topic:ambiguous")
                if (input.topicsFull) return reject("topic:full")
                if (!TopicHygiene.isValidNewName(name)) return reject("topic:name")
                TopicDecision.New(name, raw.symbol?.let(TopicIcon::fromRaw) ?: TopicIcon.sparkles)
            }
            "none" -> TopicDecision.None
            else -> reject("topic:choice")
        }
    }

    fun checkedTasks(
        raw: List<RawTask>,
        transcript: String,
        rejections: MutableList<String>,
    ): List<TaskDraft> {
        if (raw.size > maxTasks) rejections.add("tasks:limit")
        val result = mutableListOf<TaskDraft>()
        val seen = mutableSetOf<String>()
        for (task in raw.take(maxTasks)) {
            val quote = locateQuote(task.quote, transcript)
            if (quote == null) {
                rejections.add("task:quote")
                continue
            }
            val hint = TextForm.trim(task.due_hint ?: "")
            val due = hint.takeIf { it.isNotEmpty() && dueHintInQuote(it, quote) }
            val text = TaskText.tidy(task.text.replace("\n", " "), due)
            if (TextForm.count(text) !in 2..maxTaskLength) {
                rejections.add("task:text")
                continue
            }
            if (!taskWordsGrounded(text, quote)) {
                rejections.add("task:words")
                continue
            }
            if (!digitsContained(text, quote)) {
                rejections.add("task:digits")
                continue
            }
            if (effectiveNegations(text) != effectiveNegations(quote)) {
                rejections.add("task:negation")
                continue
            }
            if (hint.isNotEmpty() && due == null) rejections.add("task:due")
            if (!seen.add(taskKey(text, due))) {
                rejections.add("task:duplicate")
                continue
            }
            result.add(TaskDraft(text, quote, due))
        }
        return result
    }

    fun taskKey(text: String, dueHint: String?) =
        normalizedForMatch(text) + "\u001f" + normalizedForMatch(dueHint ?: "")

    const val maxDueSpan = 20

    fun dueHintInQuote(hint: String, quote: String): Boolean {
        val due = tokens(hint).map { it.word }
        if (due.isEmpty()) return false
        val words = tokens(quote).map { it.word }
        if ((" " + words.joinToString(" ") + " ").contains(" " + due.joinToString(" ") + " "))
            return true
        for (start in words.indices.filter { words[it] == due[0] }) {
            var position = start
            var pieces = 1
            var matched = true
            for (word in due.drop(1)) {
                val next = (position + 1 until words.size).firstOrNull { words[it] == word }
                if (next == null) {
                    matched = false
                    break
                }
                if (next != position + 1) pieces++
                position = next
            }
            if (matched && pieces <= 3 && position - start + 1 <= maxDueSpan) return true
        }
        return false
    }

    val reminderPhrases =
        listOf(
                "nicht vergessen",
                "vergiss nicht",
                "vergessen sie nicht",
                "nicht zu vergessen",
                "vergesst nicht",
                "don't forget",
                "do not forget",
                "dont forget",
                "n'oublie pas",
                "n'oubliez pas",
                "no olvides",
                "no olvidar",
                "non dimenticare",
                "não esquecer",
                "não esqueças",
                "niet vergeten",
                "vergeet niet",
                "nie zapomnij",
                "unutma",
                "unutmayın",
            )
            .map { TextAnalysis.normalizedLower(it).replace('’', '\'') }

    fun effectiveNegations(text: String): Int {
        val lower = TextAnalysis.normalizedLower(text).replace('’', '\'')
        val reminders = reminderPhrases.sumOf { lower.split(it).size - 1 }
        return maxOf(0, TextAnalysis.negationCount(text) - reminders)
    }

    val taskStopwords =
        listOf(
                "der",
                "die",
                "das",
                "den",
                "dem",
                "des",
                "ein",
                "eine",
                "einen",
                "einem",
                "einer",
                "und",
                "oder",
                "für",
                "mit",
                "von",
                "vom",
                "zu",
                "zum",
                "zur",
                "im",
                "in",
                "ins",
                "an",
                "am",
                "ans",
                "auf",
                "bei",
                "beim",
                "wegen",
                "noch",
                "the",
                "a",
                "an",
                "and",
                "or",
                "for",
                "with",
                "to",
                "of",
                "in",
                "on",
                "at",
                "le",
                "la",
                "les",
                "un",
                "une",
                "de",
                "du",
                "des",
                "et",
                "pour",
                "el",
                "los",
                "las",
                "y",
                "para",
                "con",
                "il",
                "lo",
                "gli",
                "e",
                "per",
                "o",
                "os",
                "as",
                "um",
                "uma",
                "het",
                "een",
                "en",
                "voor",
                "met",
            )
            .map(TextAnalysis::normalizedLower)
            .toSet()

    fun taskWordsGrounded(text: String, quote: String): Boolean {
        val quoteForms = wordForms(quote)
        var ungrounded = 0
        for (word in TextAnalysis.letterRuns(TextAnalysis.normalizedLower(text))) {
            if (TextForm.count(word) < 2 || word in taskStopwords || matches(word, quoteForms))
                continue
            ungrounded++
            if (ungrounded > 1) return false
        }
        return true
    }

    fun checkedRelated(
        raw: List<RawRelated>,
        transcript: String,
        aliases: ThoughtPrompt.Aliases,
        selfID: String?,
        rejections: MutableList<String>,
    ): List<RelatedDraft> {
        if (raw.size > maxRelated) rejections.add("related:limit")
        val result = mutableListOf<RelatedDraft>()
        val seen = mutableSetOf<String>()
        for (link in raw.take(maxRelated)) {
            val candidate = aliases.candidates[TextForm.trim(link.ref)]
            if (candidate == null) {
                rejections.add("related:ref")
                continue
            }
            if (candidate.thoughtID == selfID) {
                rejections.add("related:self")
                continue
            }
            val kind = LinkKind.fromRaw(link.kind)
            if (kind == null) {
                rejections.add("related:kind")
                continue
            }
            val reason = TextForm.trim(link.reason).replace("\n", " ")
            if (TextForm.count(reason) !in 1..maxReasonLength) {
                rejections.add("related:reason")
                continue
            }
            if (!digitsContained(reason, "$transcript ${candidate.title} ${candidate.excerpt}")) {
                rejections.add("related:digits")
                continue
            }
            if (
                link.confidence != "high" &&
                    !(link.confidence == "medium" && candidate.localScore >= mediumLinkScore)
            ) {
                rejections.add("related:confidence")
                continue
            }
            if (!seen.add(candidate.thoughtID)) continue
            result.add(RelatedDraft(candidate.thoughtID, kind, reason))
        }
        return result
    }

    fun plainHyphens(json: String) =
        json
            .replace('\u2011', '-')
            .replace('\u2010', '-')
            .replace("\\u2011", "-")
            .replace("\\u2010", "-")

    fun normalizedForMatch(text: String) = tokens(text).joinToString(" ") { it.word }

    data class MatchToken(val word: String, val start: Int, val end: Int)

    fun tokens(text: String) =
        TextAnalysis.runs(text, TextAnalysis::isWordScalar).map {
            MatchToken(
                Normalizer.normalize(TextAnalysis.normalizedLower(it.word), Normalizer.Form.NFD)
                    .replace(Regex("\\p{M}"), ""),
                it.start,
                it.end,
            )
        }

    fun locateQuote(quote: String, transcript: String): String? {
        val q = tokens(quote).map { it.word }
        if (q.isEmpty()) return null
        val t = tokens(transcript)
        if (t.isEmpty()) return null
        val words = t.map { it.word }
        fun span(start: Int, end: Int) = transcript.substring(t[start].start, t[end].end)
        if (q.size <= words.size)
            for (start in 0..words.size - q.size) if (words.subList(start, start + q.size) == q)
                return span(start, start + q.size - 1)
        var bestScore = 0.0
        var bestStart = 0
        var bestEnd = 0
        for (length in maxOf(1, q.size - 2)..q.size + 2) if (length <= words.size)
            for (start in 0..words.size - length) {
                val common = lcsLength(words.subList(start, start + length), q)
                val score = common.toDouble() / maxOf(q.size, length)
                if (score >= 0.9 && score > bestScore) {
                    bestScore = score
                    bestStart = start
                    bestEnd = start + length - 1
                }
            }
        if (bestScore > 0) return span(bestStart, bestEnd)
        return elidedSpan(quote, words, ::span)
    }

    const val maxElidedSpan = 30

    private fun elidedSpan(
        quote: String,
        words: List<String>,
        span: (Int, Int) -> String,
    ): String? {
        val pieces =
            quote
                .replace("...", "…")
                .split('…')
                .map { tokens(it).map { t -> t.word } }
                .filter { it.isNotEmpty() }
        if (pieces.size < 2) return null
        fun find(piece: List<String>, from: Int): Int? =
            if (from + piece.size > words.size) null
            else
                (from..words.size - piece.size).firstOrNull {
                    words.subList(it, it + piece.size) == piece
                }
        var starts = 0
        while (true) {
            val first = find(pieces[0], starts) ?: break
            var end = first + pieces[0].size
            var complete = true
            for (piece in pieces.drop(1)) {
                val next = find(piece, end)
                if (next == null || next + piece.size - first > maxElidedSpan) {
                    complete = false
                    break
                }
                end = next + piece.size
            }
            if (complete) return span(first, end - 1)
            starts = first + 1
        }
        return null
    }

    fun lcsLength(a: List<String>, b: List<String>): Int {
        var previous = IntArray(b.size + 1)
        for (x in a) {
            val current = IntArray(b.size + 1)
            for ((j, y) in b.withIndex()) current[j + 1] =
                if (x == y) previous[j] + 1 else maxOf(previous[j + 1], current[j])
            previous = current
        }
        return previous[b.size]
    }

    fun digitsContained(text: String, source: String) = SpokenNumbers.digitsContained(text, source)

    fun wordForms(text: String): Set<String> =
        TextAnalysis.letterRuns(TextAnalysis.normalizedLower(text)).toSet() +
            lemmatizer.lemmas(text).filter { it.isNotEmpty() }.map(TextAnalysis::normalizedLower)

    fun matches(word: String, forms: Set<String>): Boolean {
        if (word in forms || wordForms(word).any { it in forms }) return true
        val w = word.codePoints().toArray()
        for (form in forms) {
            val f = form.codePoints().toArray()
            val shorter = minOf(w.size, f.size)
            if (shorter < 4) continue
            var common = 0
            while (common < shorter && w[common] == f[common]) common++
            if (common >= 4 && common >= shorter - 3) return true
        }
        return false
    }

    fun sharesContentWord(title: String, transcript: String): Boolean {
        if (TextAnalysis.containsScriptioContinua(title)) {
            val units = TextAnalysis.contentUnits(transcript).toSet()
            return TextAnalysis.contentUnits(title).any { it in units }
        }
        val forms = wordForms(transcript)
        return TextAnalysis.letterRuns(TextAnalysis.normalizedLower(title)).any {
            TextAnalysis.weightedLength(it) >= 3 &&
                it !in taskStopwords &&
                it !in Lexicon.fillers &&
                matches(it, forms)
        }
    }
}
