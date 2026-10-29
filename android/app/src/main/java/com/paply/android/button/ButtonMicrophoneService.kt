package com.paply.android.button

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import com.paply.android.R

/** Only the connected accessibility service can request this non-exported, short-lived owner. */
class ButtonMicrophoneService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val owner = PaplyButtonService.connected
        if (owner == null || !owner.awaitingForeground) { stopSelf(); return START_NOT_STICKY }
        try {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel("button-microphone", "Paply-Diktat", NotificationManager.IMPORTANCE_LOW))
            val notification = Notification.Builder(this, "button-microphone")
                .setSmallIcon(R.drawable.ic_stat_paply).setContentTitle("Paply hört zu")
                .setContentText("Mit der Paply-Pille fertigstellen oder verwerfen.")
                .setOngoing(true).setUsesChronometer(true).build()
            startForeground(410, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            owner.foregroundReady()
        } catch (_: Exception) { owner.foregroundFailed(); stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() { PaplyButtonService.connected?.foregroundStopped(); super.onDestroy() }
}
