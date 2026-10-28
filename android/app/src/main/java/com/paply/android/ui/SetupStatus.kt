package com.paply.android.ui

import androidx.core.net.toUri
import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import com.paply.android.R
import com.paply.android.ThoughtTile
import com.paply.android.settings.AppPreferences

data class SetupStatus(val microphone: Boolean, val notifications: Boolean, val keyboardEnabled: Boolean,
    val keyboardSelected: Boolean, val tileAdded: Boolean,
) {
    companion object {
        fun read(context: Context, prefs: AppPreferences): SetupStatus {
            val manager = context.getSystemService(InputMethodManager::class.java)
            val enabled = manager.enabledInputMethodList.any { it.packageName == context.packageName }
            val selected = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
                ?.let { ComponentName.unflattenFromString(it)?.packageName == context.packageName } == true
            // API 29–32 may hide/omit the tile; a manual confirmation is authoritative there.
            val tiles = runCatching { Settings.Secure.getString(context.contentResolver, "sysui_qs_tiles") }.getOrNull()
            val tile = tileAdded(tiles, context.packageName, prefs.tileAdded, Build.VERSION.SDK_INT)
            return SetupStatus(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED,
                context.getSystemService(NotificationManager::class.java).areNotificationsEnabled(), enabled, selected, tile)
        }
    }
}

internal fun tileAdded(tiles: String?, packageName: String, confirmed: Boolean, sdk: Int): Boolean {
    if (sdk < 33 && confirmed) return true
    if (tiles == null) return confirmed
    return tiles.split(',').any { it == "custom($packageName/.ThoughtTile)" ||
        it == "custom($packageName/com.paply.android.ThoughtTile)" ||
        it == "$packageName/.ThoughtTile" || it == "$packageName/com.paply.android.ThoughtTile" }
}

fun Activity.openKeyboardSettings() { startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)) }
fun Activity.chooseKeyboard() { getSystemService(InputMethodManager::class.java).showInputMethodPicker() }
fun Activity.openAppSettings() { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:$packageName".toUri())) }

/** True is returned only for the system's added/already-added result, never for a dismissed prompt. */
fun Activity.requestThoughtTile(onResult: (Boolean) -> Unit) {
    if (Build.VERSION.SDK_INT >= 33) {
        getSystemService(StatusBarManager::class.java).requestAddTileService(
            ComponentName(this, ThoughtTile::class.java), "Paply-Gedanke", Icon.createWithResource(this, R.drawable.ic_mic),
            mainExecutor,
        ) { result -> onResult(result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
            result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED) }
    }
}
