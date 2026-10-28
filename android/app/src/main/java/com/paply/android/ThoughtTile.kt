package com.paply.android

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import kotlinx.coroutines.*

class ThoughtTile : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var observer: Job? = null
    // A normal listening tile is rebound whenever QS opens, including after reboot/update.
    // ACTIVE_TILE metadata is unrelated to Tile.STATE_ACTIVE and can leave a stale unavailable tile.
    override fun onStartListening() {
        observer?.cancel()
        observer = scope.launch { ThoughtState.current.collect { updateTile(it.phase) } }
    }
    private fun updateTile(phase: String) {
        qsTile?.apply {
            state = when (phase) {
                "starting", "recording" -> Tile.STATE_ACTIVE
                "processing" -> Tile.STATE_UNAVAILABLE
                else -> Tile.STATE_INACTIVE
            }
            label = "Paply-Gedanke"
            subtitle = when (phase) {
                "recording" -> "Tippen: fertig"
                "processing" -> "Paply schreibt …"
                "starting" -> "Startet …"
                else -> "Aufnehmen"
            }
            updateTile()
        }
    }
    override fun onStopListening() { observer?.cancel(); observer = null }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
    override fun onClick() {
        super.onClick()
        Diag.event("tile.click active=${ThoughtState.active} locked=$isLocked direct=${Settings(this).directTile}")
        if (ThoughtState.active) { ThoughtService.command(this, ThoughtService.FINISH); return }
        if (Settings(this).directTile) {
            val error = ThoughtService.start(this)
            if (error != null) openCard(error)
        } else openCard(null)
    }
    // Pre-34 systems have only the Intent overload; the target-SDK restriction lives in 34+.
    @android.annotation.SuppressLint("StartActivityAndCollapseDeprecated")
    @Suppress("DEPRECATION")
    private fun openCard(error: String?) {
        val intent = Intent(this, CaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        error?.let { intent.putExtra("error", it) }
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 10, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else startActivityAndCollapse(intent)
    }
}
