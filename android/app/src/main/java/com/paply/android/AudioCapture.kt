package com.paply.android

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.*
import android.os.SystemClock
import com.paply.core.WavWriter
import com.paply.core.trimQuietEdges
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlin.math.sqrt

/** One microphone owner in the app; IME and thought service must never compete. */
object MicrophoneLease {
    private var owner: Any? = null
    @Synchronized fun acquire(value: Any): Boolean { if (owner != null) return false; owner = value; return true }
    @Synchronized fun release(value: Any) { if (owner === value) owner = null }
}

data class CaptureResult(val file: File, val durationMs: Long, val voicedSamples: Long, val silenced: Boolean, val error: String?) {
    val usable get() = error == null && !silenced && voicedSamples >= 1600
}

/** AudioRecord ownership, reads and release stay on one worker; no read exception escapes. */
class AudioCapture(private val context: Context, val file: File, private val maxMs: Long = 10 * 60_000L) {
    private val running = AtomicBoolean(false)
    private val completed = CompletableDeferred<CaptureResult>()
    @Volatile var level = 0f; private set
    @Volatile var startedAt = 0L; private set
    @Volatile private var wasSilenced = false
    private var recorder: AudioRecord? = null
    private val callback = object : AudioManager.AudioRecordingCallback() {
        override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
            val session = recorder?.audioSessionId ?: return
            configs.filter { it.clientAudioSessionId == session }.forEach {
                if (it.isClientSilenced) wasSilenced = true
                Diag.event("audio.callback isClientSilenced=${it.isClientSilenced} session=$session route=${it.audioDevice?.type}")
            }
        }
    }
    fun start() {
        check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) { "permission" }
        check(MicrophoneLease.acquire(this)) { "microphone-busy" }
        try {
            val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            check(minimum > 0)
            val audio = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                .setAudioFormat(AudioFormat.Builder().setSampleRate(16000).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setBufferSizeInBytes(maxOf(minimum * 2, 6400)).build()
            recorder = audio
            check(audio.state == AudioRecord.STATE_INITIALIZED)
            val manager = context.getSystemService(AudioManager::class.java)
            manager.getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
                ?.let { Diag.event("audio.preferredBuiltin=${audio.setPreferredDevice(it)}") }
            audio.registerAudioRecordingCallback(context.mainExecutor, callback)
            audio.startRecording()
            check(audio.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            startedAt = SystemClock.elapsedRealtime(); running.set(true)
            Diag.event("audio.start session=${audio.audioSessionId} source=VOICE_RECOGNITION rate=16000")
            Thread({ record(audio) }, "PaplyAudio").start()
        } catch (e: Exception) {
            release()
            file.delete()
            throw e
        }
    }
    fun requestStop() { running.set(false) }
    suspend fun finish(): CaptureResult { requestStop(); return completed.await() }
    suspend fun awaitEnd(): CaptureResult = completed.await()
    private fun record(audio: AudioRecord) {
        var frames = 0L; var voiced = 0L; var firstVoiced = -1L; var lastVoiced = 0L; var error: String? = null; var lastReport = 0L
        try {
            WavWriter(file).use { writer ->
                val samples = ShortArray(320)
                while (running.get() && SystemClock.elapsedRealtime() - startedAt < maxMs) {
                    val count = audio.read(samples, 0, samples.size, AudioRecord.READ_NON_BLOCKING)
                    if (count < 0) { error = "read-$count"; Diag.event("audio.read.error code=$count"); break }
                    if (count == 0) { Thread.sleep(10); continue }
                    writer.append(samples, count); frames += count
                    var sum = 0.0
                    for (i in 0 until count) sum += samples[i].toDouble() * samples[i]
                    val rms = sqrt(sum / count)
                    level = (rms / 5000).toFloat().coerceIn(0f, 1f)
                    if (rms >= 100) {
                        voiced += count
                        if (firstVoiced < 0) firstVoiced = frames - count
                        lastVoiced = frames
                    }
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastReport >= 1000) {
                        val config = audio.activeRecordingConfiguration
                        if (config?.isClientSilenced == true) wasSilenced = true
                        Diag.event("audio.sample isClientSilenced=${config?.isClientSilenced} rms=${rms.toInt()} ms=${frames / 16} route=${audio.routedDevice?.type}")
                        lastReport = now
                    }
                }
            }
            if (error == null && !wasSilenced && voiced >= 1600) {
                val trimmed = trimQuietEdges(file, firstVoiced, lastVoiced)
                Diag.event("audio.trim beforeMs=${frames / 16} uploadMs=${trimmed / 16}")
            }
        } catch (e: Exception) { error = e.javaClass.simpleName; Diag.event("audio.error type=$error")
        } finally {
            running.set(false); level = 0f
            release()
            val result = CaptureResult(file, frames / 16, voiced, wasSilenced, error)
            Diag.event("audio.stop ms=${result.durationMs} voiced=$voiced silenced=$wasSilenced usable=${result.usable}")
            completed.complete(result)
        }
    }
    private fun release() {
        recorder?.let { audio ->
            runCatching { audio.unregisterAudioRecordingCallback(callback) }
            runCatching { if (audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) audio.stop() }
            runCatching { audio.release() }
        }
        recorder = null
        MicrophoneLease.release(this)
        Diag.event("audio.released")
    }
}
