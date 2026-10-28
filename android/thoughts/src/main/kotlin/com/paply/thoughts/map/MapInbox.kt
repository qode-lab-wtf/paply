package com.paply.thoughts.map

import com.paply.thoughts.ThoughtState
import java.time.Instant
import kotlin.math.*

enum class MapInboxStatus {
    ordering,
    network,
    key,
    limit,
    budget,
    attention;

    companion object {
        fun isPending(state: ThoughtState) =
            state != ThoughtState.done && state != ThoughtState.empty

        fun of(states: Iterable<ThoughtState>): MapInboxStatus? =
            states
                .mapNotNull {
                    when (it) {
                        ThoughtState.recording,
                        ThoughtState.captured,
                        ThoughtState.transcribing,
                        ThoughtState.transcribed,
                        ThoughtState.structuring -> ordering to 0
                        ThoughtState.waitingKey -> key to 1
                        ThoughtState.needsAttention -> attention to 2
                        ThoughtState.waitingNetwork -> network to 3
                        ThoughtState.waitingLimit -> limit to 4
                        ThoughtState.waitingBudget -> budget to 5
                        ThoughtState.done,
                        ThoughtState.empty -> null
                    }
                }
                .minByOrNull { it.second }
                ?.first
    }
}

/** Pure flight bookkeeping. The app supplies the clock and the rendered target topic. */
class MapLandings {
    data class Flight(
        val id: String,
        val topicID: String,
        val launch: Instant,
        val duration: Double,
    ) {
        val land
            get() = launch.addSeconds(duration)

        fun progress(now: Instant): Double? {
            val t = secondsBetween(launch, now)
            return if (t >= 0 && t < duration) t / duration else null
        }
    }

    var pending: Set<String> = emptySet()
        private set

    var awaiting: Map<String, Instant> = emptyMap()
        private set

    var flights: List<Flight> = emptyList()
        private set

    private var started = false

    fun observe(pending: Set<String>, existing: Set<String>, now: Instant) {
        if (!started) {
            started = true
            this.pending = pending.toSet()
            return
        }
        val next = awaiting.toMutableMap()
        for (id in this.pending) if (id !in pending && id in existing) next[id] = now
        for (id in pending) next.remove(id)
        this.pending = pending.toSet()
        awaiting = next.filter { (id, since) ->
            id in existing && secondsBetween(since, now) <= patience
        }
        flights = flights.filter {
            it.id !in pending && it.id in existing && secondsBetween(it.land, now) <= glow
        }
    }

    fun place(animate: Boolean, now: Instant, target: (String) -> String?): List<Flight> {
        data class Ready(val id: String, val since: Instant, val topic: String)
        val ready =
            awaiting
                .mapNotNull { (id, since) -> target(id)?.let { Ready(id, since, it) } }
                .sortedWith(compareBy<Ready> { it.since }.thenBy { it.id })
        if (ready.isEmpty()) return emptyList()
        awaiting = awaiting - ready.map { it.id }.toSet()
        if (!animate) return emptyList()
        val queued = flights.count { it.launch > now }
        val wave = ready.take(max(0, maxFlights - queued))
        if (wave.isEmpty()) return emptyList()
        val step = min(stagger, spread / (wave.size + queued))
        var next = flights.maxOfOrNull { it.launch }?.let { maxOf(now, it.addSeconds(step)) } ?: now
        val added = wave.map {
            val flight = Flight(it.id, it.topic, next, duration)
            next = next.addSeconds(step)
            flight
        }
        flights = flights + added
        return added
    }

    fun count(now: Instant) = pending.size + awaiting.size + flights.count { it.launch > now }

    fun launched(now: Instant) = flights.count { it.launch <= now }

    fun unlanded(now: Instant) = flights.filter { it.land > now }

    fun isRunning(now: Instant) = flights.any { secondsBetween(it.land, now) < glow }

    fun nextEvent(now: Instant): Instant? =
        (flights.flatMap { listOf(it.launch, it.land, it.land.addSeconds(glow)) } +
                listOfNotNull(awaiting.values.minOrNull()?.addSeconds(patience + .01)))
            .filter { it > now }
            .minOrNull()

    override fun equals(other: Any?) =
        other is MapLandings &&
            pending == other.pending &&
            awaiting == other.awaiting &&
            flights == other.flights &&
            started == other.started

    override fun hashCode() = listOf(pending, awaiting, flights, started).hashCode()

    companion object {
        const val stagger = .3
        const val spread = 2.4
        const val duration = .9
        const val maxFlights = 12
        const val patience = 8.0
        const val glow = .9
    }
}
