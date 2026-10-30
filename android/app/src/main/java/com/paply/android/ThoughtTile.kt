package com.paply.android

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.paply.android.settings.SettingsRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.combine

class ThoughtTile : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var observer: Job? = null
    override fun onStartListening() {
        observer?.cancel()
        observer = scope.launch {
            combine(ThoughtState.current, SettingsRepository.get(this@ThoughtTile).state) { state, prefs -> state to prefs.betaThoughts }
                .collect { (capture, enabled) -> qsTile?.apply {
                    state = if (ThoughtState.active) Tile.STATE_ACTIVE else if (!enabled) Tile.STATE_UNAVAILABLE else Tile.STATE_INACTIVE
                    label = "Paply-Gedanke"
                    subtitle = if (ThoughtState.active) "Tippen: fertig" else if (!enabled) "Beta in Paply einschalten" else "Aufnehmen"
                    updateTile()
                } }
        }
    }
    override fun onStopListening() { observer?.cancel(); observer = null }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
    @android.annotation.SuppressLint("StartActivityAndCollapseDeprecated")
    @Suppress("DEPRECATION")
    override fun onClick() {
        super.onClick()
        Diag.event("tile.click active=${ThoughtState.active} locked=$isLocked")
        // Both taps travel through the same visible card, including an already open singleTop card.
        val intent = Intent(this, CaptureActivity::class.java).setAction(ThoughtService.TOGGLE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(PendingIntent.getActivity(this, 10, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_CANCEL_CURRENT))
        else startActivityAndCollapse(intent)
    }
}
