package com.paply.thoughts.local

import com.paply.core.LanguageDetector
import com.paply.core.NoLanguageDetector
import com.paply.core.detectLanguage
import com.paply.thoughts.*
import com.paply.thoughts.model.StableHash
import com.paply.thoughts.model.TextForm
import com.paply.thoughts.nlp.TopicMentions
import com.paply.thoughts.store.ThoughtStore
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.sqrt
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Local preselection, identical BM25 scoring/caps to iOS's unavailable-embedding path. */
class CandidateFinder
private constructor(
    private val source: () -> Pair<List<Thought>, List<Topic>>,
    val options: Options,
    private val now: () -> Instant,
    private val detector: LanguageDetector,
) : CandidateFinding, KeywordFinding {
    data class Options(
        val recencyBonus: Double = 0.05,
        val recencyWindow: Double = 7.0 * 24 * 3600,
        val minimumScore: Double = 0.35,
        val maxScored: Int = 6,
        val maxTotal: Int = 7,
        val recentWindow: Double = 3.0 * 3600,
        val recentMax: Int = 2,
        val excerptLength: Int = 160,
        val keywordNormalization: KeywordNormalization = KeywordNormalization.selfScore,
        val scoring: Scoring = Scoring.relative,
        val zScale: Double = 4.0,
        val relativeMinimumCount: Int = 8,
        val maxRefreshPerCall: Int = 400,
    )

    enum class Scoring {
        absolute,
        relative,
    }

    enum class KeywordNormalization {
        selfScore,
        maximum,
    }

    data class Scored(
        val thoughtID: String,
        val score: Double,
        val cosine: Double?,
        val keyword: Double,
        val isRecent: Boolean,
    )

    constructor(
        store: ThoughtStore,
        options: Options = Options(),
        now: () -> Instant = Instant::now,
        detector: LanguageDetector = NoLanguageDetector,
    ) : this({ store.all() to store.topics() }, options, now, detector)

    constructor(
        thoughts: List<Thought>,
        topics: List<Topic>,
        options: Options = Options(),
        now: () -> Instant = Instant::now,
        detector: LanguageDetector = NoLanguageDetector,
    ) : this(snapshotSource(thoughts, topics), options, now, detector)

    private val mutex = Mutex()
    private val index = LocalIndex()
    private val embedder = EmbeddingIndex()

    override suspend fun topicIndex(
        forText: String,
        languages: List<String>,
    ): CandidateFinding.TopicIndex = mutex.withLock {
        val (thoughts, topics) = source()
        sync(thoughts)
        val query = analyze(forText, languages.firstOrNull())
        val clock = now()
        val haystack = TopicMentions.Haystack(forText)
        data class Ranked(
            val entry: TopicIndexEntry,
            val fit: Double,
            val hits: Int,
            val active: Boolean,
            val last: Instant,
        )
        val active = mutableListOf<Ranked>()
        val provisional = mutableListOf<Ranked>()
        val mentioned = mutableListOf<Ranked>()
        var activeTotal = 0
        for (summary in TopicIndex.summaries(topics, thoughts)) {
            val fit = TopicIndex.fit(summary, index, query)
            val hits = TopicMentions.matches(TopicMentions.terms(summary.topic), haystack)
            val entry =
                TopicIndexEntry(
                    summary.topic.id,
                    summary.topic.title,
                    summary.count,
                    fit.hint,
                    summary.topic.describedNote,
                    hits.isNotEmpty(),
                )
            val ranked =
                Ranked(
                    entry,
                    fit.score,
                    hits.size,
                    summary.isActive,
                    summary.lastActivity ?: summary.topic.createdAt,
                )
            if (summary.isActive) activeTotal++
            when {
                hits.isNotEmpty() -> mentioned.add(ranked)
                summary.isActive -> active.add(ranked)
                summary.lastActivity != null &&
                    secondsBetween(summary.lastActivity, clock) <= TopicIndex.provisionalWindow ->
                    provisional.add(ranked)
            }
        }
        val ranked =
            mentioned.sortedWith(
                compareByDescending<Ranked> { it.hits }.thenByDescending { it.fit },
            )
        val pinned = ranked.take(TopicIndex.maxMentioned)
        ranked.drop(TopicIndex.maxMentioned).forEach {
            if (it.active) active.add(it) else provisional.add(it)
        }
        val pinnedActive = pinned.count { it.active }
        val selectedActive =
            active
                .sortedWith(
                    compareByDescending<Ranked> { it.fit }.thenByDescending { it.entry.count },
                )
                .take((TopicIndex.maxActive - pinnedActive).coerceAtLeast(0))
        val selectedProvisional =
            provisional
                .sortedWith(compareByDescending<Ranked> { it.fit }.thenByDescending { it.last })
                .take((TopicIndex.maxProvisional - pinned.size + pinnedActive).coerceAtLeast(0))
        CandidateFinding.TopicIndex(
            (pinned + selectedActive + selectedProvisional).map { it.entry },
            activeTotal >= TopicIndex.maxActive,
        )
    }

    override suspend fun candidates(forText: String, languages: List<String>, excluding: String) =
        candidates(forText, languages, excluding, now())

    override suspend fun candidates(
        forText: String,
        languages: List<String>,
        excluding: String,
        relativeTo: Instant,
    ): List<CandidateEntry> = mutex.withLock {
        val (thoughts, _) = source()
        sync(thoughts)
        val byID = thoughts.associateBy { it.id }
        select(
                score(forText, languages.firstOrNull(), thoughts, excluding, relativeTo),
                options,
                thoughts.associate { it.id to it.createdAt },
            )
            .mapNotNull { item -> byID[item.thoughtID]?.let { entry(it, item.score, relativeTo) } }
    }

    override suspend fun didChange(thought: Thought) = mutex.withLock {
        if (!isIndexable(thought)) index.remove(thought.id)
        else makeEntryIfNeeded(thought)?.let(index::upsert)
        Unit
    }

    suspend fun rank(forText: String, languages: List<String>, excluding: String): List<Scored> =
        mutex.withLock {
            val (thoughts, _) = source()
            sync(thoughts)
            score(forText, languages.firstOrNull(), thoughts, excluding, now())
        }

    suspend fun selection(
        forText: String,
        languages: List<String>,
        excluding: String,
    ): List<Scored> = mutex.withLock {
        val (thoughts, _) = source()
        sync(thoughts)
        select(
            score(forText, languages.firstOrNull(), thoughts, excluding, now()),
            options,
            thoughts.associate { it.id to it.createdAt },
        )
    }

    override suspend fun keywords(forText: String, language: String?) =
        keywords(forText, language, 5)

    suspend fun keywords(forText: String, language: String?, limit: Int): List<String> =
        mutex.withLock {
            Keywords.top(Keywords.counts(Keywords.terms(forText, language)), limit, index::idf)
        }

    val embeddingsAvailable
        get() = embedder.available

    private fun score(
        text: String,
        language: String?,
        thoughts: List<Thought>,
        excluding: String,
        clock: Instant,
    ): List<Scored> {
        val query = analyze(text, language)
        val raw =
            thoughts
                .filter { it.id != excluding && isIndexable(it) }
                .mapNotNull { thought ->
                    index[thought.id]?.let { thought to index.bm25(query, it) }
                }
        val normalizer =
            when (options.keywordNormalization) {
                KeywordNormalization.selfScore -> index.selfScore(query)
                KeywordNormalization.maximum -> raw.maxOfOrNull { it.second } ?: 0.0
            }
        val relative =
            options.scoring == Scoring.relative && raw.size >= options.relativeMinimumCount
        val (mean, deviation) = meanAndDeviation(raw.map { it.second })
        return raw.map { (thought, bm25) ->
                val keyword = if (normalizer > 0) minOf(1.0, bm25 / normalizer) else 0.0
                var value =
                    if (relative) ((bm25 - mean) / deviation / options.zScale).coerceIn(0.0, 1.0)
                    else keyword
                val age = secondsBetween(thought.createdAt, clock)
                if (age >= 0 && age < options.recencyWindow) value += options.recencyBonus
                Scored(thought.id, value, null, keyword, age >= 0 && age <= options.recentWindow)
            }
            .sortedWith(compareByDescending<Scored> { it.score }.thenBy { it.thoughtID })
    }

    private fun isIndexable(thought: Thought) =
        thought.deletedAt == null &&
            thought.state != ThoughtState.recording &&
            document(thought).isNotEmpty()

    private fun makeEntryIfNeeded(thought: Thought): LocalIndex.Entry? {
        if (!isIndexable(thought)) return null
        val text = document(thought)
        val language = thought.languages.firstOrNull() ?: detectLanguage(text, detector)
        val hash = StableHash.of(text + "\u0001" + (language ?: "") + "\u0001-")
        if (index[thought.id]?.contentHash == hash) return null
        return LocalIndex.Entry(
            thought.id,
            hash,
            language,
            Keywords.counts(Keywords.terms(text, language)),
        )
    }

    private fun sync(thoughts: List<Thought>) {
        val present = mutableSetOf<String>()
        var refreshed = 0
        for (thought in thoughts.filter(::isIndexable)) {
            present.add(thought.id)
            if (refreshed >= options.maxRefreshPerCall && index[thought.id] != null) continue
            makeEntryIfNeeded(thought)?.let {
                index.upsert(it)
                refreshed++
            }
        }
        (index.entries.keys - present).forEach(index::remove)
    }

    private fun analyze(text: String, language: String?) =
        Keywords.counts(Keywords.terms(text, language ?: detectLanguage(text, detector)))

    private fun entry(thought: Thought, score: Double, clock: Instant) =
        CandidateEntry(
            thought.id,
            thought.title ?: "",
            thought.topicId,
            `when`(thought.createdAt, clock),
            TextForm.prefix(
                TextForm.trim((thought.text ?: "").replace('\n', ' ')),
                options.excerptLength,
            ),
            // Swift rounded(): half away from zero, not JVM ties-to-even.
            (if (score < 0) ceil(score * 1000 - 0.5) else floor(score * 1000 + 0.5)) / 1000,
        )

    companion object {
        private fun snapshotSource(
            thoughts: List<Thought>,
            topics: List<Topic>,
        ): () -> Pair<List<Thought>, List<Topic>> {
            val snapshot = thoughts.toList() to topics.toList()
            return { snapshot }
        }

        internal fun document(thought: Thought) =
            listOfNotNull(thought.title, thought.text)
                .map(TextForm::trim)
                .filter { it.isNotEmpty() }
                .joinToString("\n")

        internal fun secondsBetween(from: Instant, to: Instant) =
            (to.epochSecond - from.epochSecond).toDouble() + (to.nano - from.nano) / 1e9

        fun select(
            scored: List<Scored>,
            options: Options,
            createdAt: Map<String, Instant>,
        ): List<Scored> {
            if (scored.isEmpty()) return emptyList()
            val recent =
                scored
                    .filter { it.isRecent }
                    .sortedByDescending { createdAt[it.thoughtID] ?: Instant.MIN }
                    .take(options.recentMax)
            val recentIDs = recent.map { it.thoughtID }.toSet()
            val room = maxOf(0, minOf(options.maxScored, options.maxTotal - recent.size))
            val above =
                scored
                    .filter { it.score >= options.minimumScore && it.thoughtID !in recentIDs }
                    .take(room)
            return (above + recent).sortedByDescending { it.score }
        }

        internal fun meanAndDeviation(values: List<Double>): Pair<Double, Double> {
            if (values.isEmpty()) return 0.0 to 1.0
            val mean = values.average()
            val variance = values.sumOf { (it - mean) * (it - mean) } / values.size
            return mean to maxOf(sqrt(variance), 1e-6)
        }

        fun `when`(date: Instant, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
            val local = date.atZone(zone)
            val today = now.atZone(zone)
            if (local.toLocalDate() == today.toLocalDate())
                return "heute " + local.format(DateTimeFormatter.ofPattern("HH:mm", Locale.GERMANY))
            val days = ChronoUnit.DAYS.between(local.toLocalDate(), today.toLocalDate())
            if (days == 1L) return "gestern"
            if (days in 2L..6L) return "vor $days Tagen"
            return local.format(
                DateTimeFormatter.ofPattern(
                    if (local.year == today.year) "d. MMM" else "d. MMM yyyy",
                    Locale.GERMANY,
                ),
            )
        }
    }
}
