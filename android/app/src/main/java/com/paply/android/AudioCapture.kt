package com.paply.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import android.os.SystemClock
import com.paply.thoughts.store.WAVWriter
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlin.math.sqrt

class MicrophoneBusyException : IllegalStateException("microphone-busy")

/** One microphone owner, including during a recorder rebuild. */
object MicrophoneLease {
    private var owner: Any? = null
    @Synchronized fun acquire(value: Any): Boolean { if (owner != null) return false; owner = value; return true }
    @Synchronized fun release(value: Any) { if (owner === value) owner = null }
    @Synchronized fun isBusy() = owner != null
}

/** Only the DUMP-protected debug receiver/tests can set these. Never a product preference. */
internal object CaptureDebug {
    @Volatile var silenced = false
    @Volatile var deadObject = false
    @Volatile var nudgeEveryMs = 120_000L
}

data class CaptureResult(val file: File, val durationMs: Long, val voicedSamples: Long, val silenced: Boolean, val error: String?) {
    // A call/read failure never invalidates speech already written to disk.
    val usable get() = voicedSamples >= 1600 && file.length() > 44
}

/** Single owning worker for read/rebuild/release. No focus, DND, ringer or communication routing. */
class AudioCapture(private val context: Context, val file: File, private val maxMs: Long = 10 * 60_000L,
    private val onSamples: ((ShortArray) -> Unit)? = null, private val thoughtWriter: WAVWriter? = null) {
    private val running = AtomicBoolean(false)
    private val completed = CompletableDeferred<CaptureResult>()
    private val manager = context.getSystemService(AudioManager::class.java)
    @Volatile var level = 0f; private set
    @Volatile var startedAt = 0L; private set
    @Volatile var interrupted = false; private set
    @Volatile private var clientSilenced = false
    @Volatile private var recorder: AudioRecord? = null
    private var wasSilenced = false
    private val callback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            val session = recorder?.audioSessionId ?: return
            configs.firstOrNull { it.clientAudioSessionId == session }?.let { clientSilenced = it.isClientSilenced }
        }
    }
    fun start() {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) throw SecurityException("microphone")
        if (!MicrophoneLease.acquire(this)) throw MicrophoneBusyException()
        try {
            recorder = freshRecorder()
            startedAt = SystemClock.elapsedRealtime(); running.set(true)
            Thread(::record, "PaplyAudio").start()
        } catch (e: Exception) {
            releaseRecorder(); MicrophoneLease.release(this)
            thoughtWriter?.close()
            completed.complete(CaptureResult(file, 0, 0, false, "start-failed"))
            throw e
        }
    }
    private fun freshRecorder(): AudioRecord {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) throw SecurityException("microphone")
        val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0)
        val audio = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(AudioFormat.Builder().setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setBufferSizeInBytes(maxOf(minimum * 2, 6400)).build()
        try {
            check(audio.state == AudioRecord.STATE_INITIALIZED)
            manager.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                ?.let { audio.setPreferredDevice(it) }
            clientSilenced = false
            audio.registerAudioRecordingCallback(context.mainExecutor, callback)
            audio.startRecording()
            check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            Diag.event("audio.start session=${audio.audioSessionId} source=VOICE_RECOGNITION rate=16000")
            return audio
        } catch (e: Exception) { runCatching { audio.release() }; throw e }
    }
    fun requestStop() { running.set(false) }
    suspend fun finish(): CaptureResult { requestStop(); return completed.await() }
    suspend fun awaitEnd(): CaptureResult = completed.await()
    private fun inCall() = manager.mode in listOf(AudioManager.MODE_IN_CALL, AudioManager.MODE_IN_COMMUNICATION, AudioManager.MODE_RINGTONE)
    private fun setInterrupted(value: Boolean) {
        if (value) wasSilenced = true
        if (interrupted != value) { interrupted = value; Diag.event("audio.interrupted value=$value") }
        if (value) level = 0f
    }
    private fun record() {
        var voiced = 0L; var frames = 0L; var firstVoiced = -1L; var lastVoiced = 0L
        var error: String? = null; var lastReport = 0L; var rebuilt = false
        var writer: WAVWriter? = null; var duration = 0
        try {
            writer = thoughtWriter ?: WAVWriter(file.toPath())
            val samples = ShortArray(320)
            while (running.get() && SystemClock.elapsedRealtime() - startedAt < maxMs) {
                // After DEAD_OBJECT, wait for the call to end before building exactly one new recorder.
                if (recorder == null) {
                    setInterrupted(true)
                    if (inCall() || manager.isMicrophoneMute) { Thread.sleep(40); continue }
                    recorder = freshRecorder(); Diag.event("audio.rebuilt")
                }
                val audio = requireNotNull(recorder)
                val count = if (BuildConfig.DEBUG && CaptureDebug.deadObject) {
                    CaptureDebug.deadObject = false; AudioRecord.ERROR_DEAD_OBJECT
                } else audio.read(samples, 0, samples.size, AudioRecord.READ_NON_BLOCKING)
                if (count < 0) {
                    Diag.event("audio.read.error code=$count")
                    if (count == AudioRecord.ERROR_DEAD_OBJECT && !rebuilt) {
                        rebuilt = true; releaseRecorder(); setInterrupted(true); continue
                    }
                    error = "read-$count"; break
                }
                val silenced = clientSilenced || audio.activeRecordingConfiguration?.isClientSilenced == true ||
                    manager.isMicrophoneMute || inCall() || (BuildConfig.DEBUG && CaptureDebug.silenced)
                setInterrupted(silenced)
                if (count == 0) { Thread.sleep(10); continue }
                // Exclude interrupted blocks from BOTH retained WAV and the IME pipeline.
                if (silenced) continue
                writer.append(FloatArray(count) { samples[it] / 32768f }); frames += count
                onSamples?.invoke(samples.copyOf(count))
                var sum = 0.0
                for (i in 0 until count) sum += samples[i].toDouble() * samples[i]
                val rms = sqrt(sum / count)
                level = (rms / 5000).toFloat().coerceIn(0f, 1f)
                if (rms >= 100) {
                    voiced += count
                    if (firstVoiced < 0) firstVoiced = frames - count
                    lastVoiced = frames
                }
                if (writer.hasFailed) { error = "storage"; break }
                val now = SystemClock.elapsedRealtime()
                if (now - lastReport >= 1000) {
                    Diag.event("audio.sample isClientSilenced=false rms=${rms.toInt()} ms=${frames / 16} route=${audio.routedDevice?.type}")
                    lastReport = now
                }
            }
        } catch (e: Exception) { error = e.javaClass.simpleName; Diag.event("audio.error type=$error")
        } finally {
            running.set(false); level = 0f
            // Free the microphone BEFORE disk finalization or any processing.
            releaseRecorder(); MicrophoneLease.release(this)
            duration = runCatching { writer?.close() ?: 0 }.getOrElse {
                error = "storage"; runCatching { WAVWriter.repair(file.toPath()) }.getOrDefault(0)
            }
            if (onSamples == null && voiced >= 1600 && error == null) {
                // Trim a copy; a failed trim/rename can never corrupt the only recording.
                val copy = File(file.parentFile, "audio.trim.tmp")
                runCatching {
                    file.copyTo(copy, overwrite = true)
                    @Suppress("DEPRECATION") val trimmed = com.paply.core.trimQuietEdges(copy, firstVoiced, lastVoiced)
                    Files.move(copy.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                    duration = (trimmed / 16).toInt()
                }.onFailure { Diag.event("audio.trim.skipped") }
                copy.delete()
            }
            val result = CaptureResult(file, duration.toLong(), voiced, wasSilenced, error)
            Diag.event("audio.stop ms=${result.durationMs} voiced=$voiced silenced=$wasSilenced usable=${result.usable}")
            completed.complete(result)
        }
    }
    private fun releaseRecorder() {
        val audio = recorder; recorder = null
        audio?.let {
            runCatching { it.unregisterAudioRecordingCallback(callback) }
            runCatching { if (it.recordingState == AudioRecord.RECORDSTATE_RECORDING) it.stop() }
            runCatching { it.release() }
        }
        Diag.event("audio.released")
    }
}
