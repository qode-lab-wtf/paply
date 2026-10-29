package com.paply.android.thoughts

import android.content.Context
import android.content.pm.ServiceInfo
import androidx.work.*
import com.paply.android.Diag
import com.paply.thoughts.*
import com.paply.thoughts.local.TopicIndex
import com.paply.thoughts.processing.*
import com.paply.android.settings.KeyVault
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.first
import com.paply.android.settings.SettingsRepository

/** Only durable WorkManager jobs perform network work. No microphone FGS extension. */
internal object ThoughtWork {
    private fun request(delayMs: Long = 0) = OneTimeWorkRequestBuilder<ThoughtWorker>()
        .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        .apply {
            if (delayMs > 0) setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            else setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }.build()
    fun enqueue(context: Context) {
        if (!SettingsRepository.get(context).state.value.betaThoughts) return
        // Append avoids losing a capture arriving just as the preceding worker finishes its drain.
        WorkManager.getInstance(context).enqueueUniqueWork("paply-thoughts", ExistingWorkPolicy.APPEND_OR_REPLACE, request())
    }
    fun retry(context: Context, at: Instant?) {
        if (!SettingsRepository.get(context).state.value.betaThoughts) return
        val delay = maxOf(30_000L, (at?.toEpochMilli() ?: System.currentTimeMillis() + 60_000) - System.currentTimeMillis())
        WorkManager.getInstance(context).enqueueUniqueWork("paply-thoughts-retry", ExistingWorkPolicy.REPLACE, OneTimeWorkRequestBuilder<ThoughtWakeWorker>().setInitialDelay(delay, TimeUnit.MILLISECONDS).build())
    }
    fun pause(context: Context) {
        val work = WorkManager.getInstance(context)
        listOf("paply-thoughts", "paply-thoughts-retry", "paply-thoughts-maintenance").forEach { work.cancelUniqueWork(it) }
    }
    fun installMaintenance(context: Context) {
        if (!SettingsRepository.get(context).state.value.betaThoughts) return
        WorkManager.getInstance(context).enqueueUniquePeriodicWork("paply-thoughts-maintenance", ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<ThoughtMaintenanceWorker>(24, TimeUnit.HOURS).build())
    }
}

class ThoughtWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun getForegroundInfo() = ForegroundInfo(3,
        ThoughtNotifications.processing(applicationContext), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val repository = ThoughtsRepository.get(applicationContext)
        if (!repository.enabled()) return@withContext Result.success()
        // Covers already-running HTTP and hygiene, as well as queued WorkManager jobs.
        val owner = currentCoroutineContext().job
        val betaWatcher = launch(start = CoroutineStart.UNDISPATCHED) {
            SettingsRepository.get(applicationContext).state.first { !it.betaThoughts }
            owner.cancel(CancellationException("thoughts-beta-off"))
        }
        try {
            repository.workMutex.withLock {
                if (!repository.enabled()) return@withLock
                val b = repository.backend()
                CaptureDiscardJournal.recover(b.store.root.toFile(), b.store)
                // A still-pending destructive intent must never be transcribed after a failed unlink.
                if (CaptureDiscardJournal.unsafePending(b.store.root.toFile(), b.store)) return@withContext Result.retry()
                repository.maintenance()
                val processor = repository.processor(b)
                val events = launch(start = CoroutineStart.UNDISPATCHED) {
                    processor.events.collect { event ->
                        ThoughtNotifications.result(applicationContext, event)
                        repository.publish(b.store)
                    }
                }
                try {
                    Diag.event("thought.work.begin")
                    processor.kick("worker")
                    processor.waitUntilIdle()
                    currentCoroutineContext().ensureActive()
                    if (repository.enabled() && !repository.dictationBusy() && repository.online()) {
                        TopicHygieneRunner.run(b.store, b.ledger, KeyVault(applicationContext).read(), TopicIndex)
                    }
                    repository.refreshUsage()
                    repository.publish(b.store)
                    // A key change wakes waitingKey; never schedule a periodic key poll.
                    if (processor.hasPendingWork()) {
                        val at = processor.nextRetryDate() ?: Instant.now().plusSeconds(15 * 60)
                        ThoughtWork.retry(applicationContext, at)
                    }
                    Diag.event("thought.work.end")
                } finally {
                    // Processor owns a scope; explicitly join cancellation before another job can run.
                    withContext(NonCancellable) {
                        processor.cancelRunning(); processor.waitUntilIdle(); processor.close()
                        events.join()
                    }
                }
            }
            Result.success()
        } catch (e: CancellationException) { throw e
        } catch (_: Exception) {
            Diag.event("thought.work.retry")
            Result.retry()
        } finally { betaWatcher.cancel() }
    }
}

class ThoughtMaintenanceWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        val repo = ThoughtsRepository.get(applicationContext)
        repo.workMutex.withLock { repo.maintenance() }
        repo.kick("maintenance")
        Result.success()
    } catch (e: CancellationException) { throw e
    } catch (_: Exception) { Result.retry() }
}

/** A retry alarm only enqueues; it never replaces the worker that is currently processing. */
class ThoughtWakeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result { ThoughtWork.enqueue(applicationContext); return Result.success() }
}
