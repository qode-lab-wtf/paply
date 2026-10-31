package com.paply.thoughts.budget

import com.paply.thoughts.model.ThoughtJSON
import com.paply.thoughts.store.FileSafety
import java.nio.file.Path
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.Serializable

/** Sliding 24h budget; unfinished reservations deliberately retain their estimate. */
class TokenLedger(
    val fileURL: Path,
    private val limits: () -> Limits = { Limits() },
    private val now: () -> Instant = Instant::now,
) {
    data class Limits(
        var dailyTokens: Int = 80_000,
        var dailyAudioSeconds: Int = 7200,
        var minuteTokens: Int = 7600,
        var minuteRequests: Int = 15,
    )

    @Serializable
    enum class Unit {
        tokens,
        audio,
    }

    data class Reservation(val id: String)

    sealed class Refusal : Exception() {
        data class Budget(val retryAt: Instant) : Refusal()

        data object BudgetTooSmall : Refusal()

        data class Minute(val retryAt: Instant) : Refusal()
    }

    @Serializable
    data class Record(
        val id: String,
        val at: Double,
        val model: String,
        val amount: Int,
        val unit: Unit,
        val pending: Boolean,
    )

    data class Summary(val tokens: Int, val audioSeconds: Int, val requests: Int)

    private var records = load()

    private fun load(): MutableList<Record> {
        val data =
            try {
                java.nio.file.Files.readAllBytes(fileURL)
            } catch (_: java.io.IOException) {
                return mutableListOf()
            }
        return try {
            ThoughtJSON.decode<List<Record>>(data).toMutableList()
        } catch (_: kotlinx.serialization.SerializationException) {
            quarantine()
            mutableListOf()
        } catch (_: IllegalArgumentException) {
            quarantine()
            mutableListOf()
        }
    }

    private fun quarantine() {
        runCatching {
            var stamp = now().toEpochMilli()
            var target = fileURL.resolveSibling("damaged-$stamp.json")
            while (java.nio.file.Files.exists(target)) {
                stamp++
                target = fileURL.resolveSibling("damaged-$stamp.json")
            }
            java.nio.file.Files.move(fileURL, target)
        }
    }

    private fun nowMs() = now().toEpochMilli().toDouble()

    private fun clean() {
        val cutoff = nowMs() - 86_400_000
        records.removeAll { it.at <= cutoff }
    }

    private fun save() {
        runCatching {
            FileSafety.createDirectory(fileURL.parent)
            FileSafety.writeAtomically(ThoughtJSON.encode(records.toList()), fileURL)
            FileSafety.syncDirectory(fileURL.parent)
        }
    }

    @Synchronized
    fun reserve(model: String, amount: Int, unit: Unit): Reservation {
        clean()
        val l = limits()
        val a = maxOf(0, amount)
        val limit = if (unit == Unit.tokens) l.dailyTokens else l.dailyAudioSeconds
        if (a > limit) throw Refusal.BudgetTooSmall
        val same = records.filter { it.unit == unit }
        val now = nowMs()
        val minute = records.filter { it.model == model && it.at > now - 60_000 }
        if (same.sumOf { it.amount.toLong() } + a > limit)
            throw Refusal.Budget(
                Instant.ofEpochMilli(
                    (now + maxOf(60_000.0, (same.minOfOrNull { it.at } ?: now) + 86_400_000 - now))
                        .toLong(),
                ),
            )
        if (
            minute.sumOf { it.amount.toLong() } + a >
                (if (unit == Unit.tokens) l.minuteTokens else 1800) ||
                minute.size >= l.minuteRequests
        )
            throw Refusal.Minute(Instant.ofEpochMilli((now + 61_000).toLong()))
        val r =
            Record("q_" + UUID.randomUUID().toString().replace("-", ""), now, model, a, unit, true)
        records.add(r)
        save()
        return Reservation(r.id)
    }

    /** Already sent live audio must be recorded even when it exceeded a budget. */
    @Synchronized
    fun recordAudio(model: String, seconds: Double) {
        if (seconds <= 0) return
        clean()
        records.add(Record(UUID.randomUUID().toString(), nowMs(), model,
            kotlin.math.ceil(seconds).toInt(), Unit.audio, false))
        save()
    }

    @Synchronized
    fun settle(reservation: Reservation, actual: Int?) {
        val i = records.indexOfFirst { it.id == reservation.id }
        if (i < 0) return
        records[i] =
            records[i].copy(
                amount = actual?.takeIf { it >= 0 } ?: records[i].amount,
                pending = false,
            )
        save()
    }

    @Synchronized
    fun summary(): Summary {
        clean()
        return Summary(
            records.filter { it.unit == Unit.tokens }.sumOf { it.amount },
            records.filter { it.unit == Unit.audio }.sumOf { it.amount },
            records.size,
        )
    }

    @Synchronized
    fun used(model: String): Int {
        clean()
        return records.filter { it.model == model && it.unit == Unit.tokens }.sumOf { it.amount }
    }
}
