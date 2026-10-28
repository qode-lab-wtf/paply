package com.paply.thoughts.display

import com.paply.thoughts.Topic
import com.paply.thoughts.model.ThoughtJSON
import com.paply.thoughts.store.FileSafety
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import kotlinx.serialization.Serializable

/** Assign once, free only known retired slots, and follow merged topic aliases. */
class TopicColorRegister(slots: Map<String, Int> = emptyMap(), last: Int? = null) {
    var slots: Map<String, Int> = slots.toMap()
        private set

    var last: Int? = last
        private set

    private var aliases = emptyMap<String, String>()
    private val retired = mutableMapOf<String, Int>()

    fun slot(id: String): Int? {
        var current = id
        val seen = mutableSetOf<String>()
        while (aliases[current] != null && seen.add(current)) current = aliases.getValue(current)
        return slots[current]
    }

    fun update(topics: List<Topic>, order: List<Int>): Boolean {
        aliases =
            topics
                .filter { it.mergedInto != null && it.mergedInto != it.id }
                .associate { it.id to it.mergedInto!! }
        val living = topics.filter { it.mergedInto == null }
        if (living.isEmpty() || order.isEmpty()) return false
        val before = slots
        val beforeLast = last
        val next = slots.toMutableMap()
        val valid = order.toSet()
        val livingIDs = living.map { it.id }.toSet()
        for ((id, slot) in slots) if (id !in livingIDs || slot !in valid) {
            if (slot in valid) retired[id] = slot
            next.remove(id)
        }
        val fresh =
            living
                .filter { it.id !in next }
                .sortedWith(compareBy<Topic> { it.createdAt }.thenBy { it.id })
                .distinctBy { it.id }
        for (topic in fresh) {
            val usage = next.values.groupingBy { it }.eachCount()
            val old = retired[topic.id]
            val slot =
                if (old != null && old in valid && (usage[old] ?: 0) == 0) old
                else pick(usage, order, last)
            next[topic.id] = slot
            retired.remove(topic.id)
            last = slot
        }
        slots = next.toMap()
        return slots != before || last != beforeLast
    }

    override fun equals(other: Any?) =
        other is TopicColorRegister && slots == other.slots && last == other.last

    override fun hashCode() = 31 * slots.hashCode() + (last ?: 0)

    companion object {
        internal fun pick(usage: Map<Int, Int>, order: List<Int>, avoiding: Int?): Int {
            val ranked = order.sortedBy { usage[it] ?: 0 }
            val first = ranked.firstOrNull() ?: return 0
            return if ((usage[first] ?: 0) == 0) first
            else ranked.firstOrNull { it != avoiding } ?: first
        }
    }
}

object TopicColorFile {
    const val fileName = "topic-colors.json"

    sealed interface Loaded {
        data object Missing : Loaded

        data class Register(val register: TopicColorRegister) : Loaded

        data object Unreadable : Loaded

        data object Damaged : Loaded
    }

    @Serializable
    private data class Payload(val version: Int, val slots: Map<String, Int>, val last: Int? = null)

    fun load(from: Path): Loaded {
        if (Files.notExists(from, NOFOLLOW_LINKS)) return Loaded.Missing
        if (Files.isSymbolicLink(from)) return Loaded.Unreadable
        val bytes =
            try {
                Files.readAllBytes(from)
            } catch (_: Exception) {
                return Loaded.Unreadable
            }
        val payload =
            try {
                ThoughtJSON.decode<Payload>(bytes)
            } catch (_: Exception) {
                return Loaded.Damaged
            }
        return Loaded.Register(
            TopicColorRegister(
                payload.slots.filterValues { it >= 0 },
                payload.last?.takeIf { it >= 0 },
            ),
        )
    }

    fun save(register: TopicColorRegister, to: Path) {
        FileSafety.createDirectory(to.toAbsolutePath().parent)
        FileSafety.writeAtomically(
            ThoughtJSON.encode(Payload(1, register.slots, register.last)),
            to,
        )
    }
}
