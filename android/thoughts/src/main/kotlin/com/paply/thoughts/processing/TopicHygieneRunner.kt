package com.paply.thoughts.processing

import com.paply.core.*
import com.paply.thoughts.*
import com.paply.thoughts.ai.*
import com.paply.thoughts.budget.TokenLedger
import com.paply.thoughts.model.*
import com.paply.thoughts.store.ThoughtStore
import java.time.Instant
import kotlinx.coroutines.CancellationException
import okhttp3.HttpUrl

/** Only suggestions and lastHygieneAt are writable here; no topic/thought mutation. */
object TopicHygieneRunner {
    const val model = "openai/gpt-oss-20b"

    sealed interface Outcome {
        data class Suggestions(val suggestions: List<TopicSuggestion>) : Outcome

        data object NotDue : Outcome

        data class Skipped(val code: String) : Outcome
    }

    suspend fun run(
        store: ThoughtStore,
        ledger: TokenLedger,
        apiKey: String?,
        topicIndex: TopicSummarizing,
        force: Boolean = false,
        transport: GroqTransport = GroqTransport.shared,
        baseURL: HttpUrl = GroqClient.defaultBaseURL,
        now: Instant = Instant.now(),
    ): Outcome {
        val thoughts = store.all()
        val topics = store.topics()
        val info = store.topicsInfo()
        val summaries = topicIndex.summaries(topics, thoughts).filter { it.isActive }
        if (!force && !TopicHygiene.isSuggestionDue(summaries.size, info.lastHygieneAt, now))
            return Outcome.NotDue
        val byID = thoughts.associateBy { it.id }
        val profiles = summaries.map { s ->
            val members = s.memberIDs.mapNotNull(byID::get).sortedByDescending { it.createdAt }
            val keywords =
                members
                    .flatMap { it.keywords }
                    .groupingBy { it }
                    .eachCount()
                    .entries
                    .sortedWith(
                        compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key },
                    )
                    .take(5)
                    .map { it.key }
            TopicHygiene.Profile(
                s.topic.id,
                s.topic.title,
                s.count,
                keywords,
                exampleTitles = members.mapNotNull { it.title }.take(3),
                language = members.firstOrNull()?.languages?.firstOrNull(),
                isUserDefined = s.topic.isUserDefined,
            )
        }
        val protected = profiles.filter { it.isUserDefined }.map { it.topicID }.toSet()
        val declined = info.declinedMerges.map { it.sorted() }.toSet()
        val pairs = TopicHygiene.candidatePairs(profiles, declined).map { it.a to it.b }
        if (pairs.isEmpty()) {
            runCatching {
                store.setLastHygieneAt(now)
                store.setPendingSuggestions(emptyList())
            }
            return Outcome.Suggestions(emptyList())
        }
        val key =
            apiKey?.let(TextForm::trim)?.takeIf { it.isNotEmpty() } ?: return Outcome.Skipped("key")
        val schema = ThoughtSchema.data(TopicHygiene.suggestionSchema)
        val request =
            StructuredChatRequest(
                model,
                TopicHygiene.suggestionSystem,
                TopicHygiene.suggestionMessage(pairs, profiles),
                "topic_pairs",
                schema,
                1200,
            )
        val estimate =
            (request.system.toByteArray().size + request.user.toByteArray().size + schema.size) /
                3 + 1200 + 256
        val reservation =
            try {
                ledger.reserve(model, estimate, TokenLedger.Unit.tokens)
            } catch (_: TokenLedger.Refusal) {
                return Outcome.Skipped("budget")
            }
        return try {
            val reply =
                GroqClient(key, baseUrl = baseURL, transport = transport).chatStructured(request)
            ledger.settle(reservation, reply.usage?.total ?: estimate)
            if (reply.finishReason != "stop" || reply.content == null)
                return Outcome.Skipped("invalid")
            // Re-read rights after the await: a topic described/claimed while the call ran remains
            // protected.
            val currentProtected =
                store.topics().filter { it.isUserDefined }.map { it.id }.toSet() + protected
            val suggestions =
                TopicHygiene.validateSuggestions(reply.content, pairs, currentProtected)
            runCatching {
                store.setPendingSuggestions(suggestions)
                store.setLastHygieneAt(now)
            }
            Outcome.Suggestions(suggestions)
        } catch (e: GroqFailure) {
            ledger.settle(reservation, 0)
            Outcome.Skipped(if (e.status > 0) "http-${e.status}" else e.code)
        } catch (e: CancellationException) {
            ledger.settle(reservation, 0)
            throw e
        }
    }
}
