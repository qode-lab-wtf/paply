package com.paply.android.ui

import android.Manifest
import com.paply.android.settings.AppPreferences
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class SetupPermissionTest {
    @Test fun deniedMicrophoneSurvivesRereadAndGrantClearsTheState() {
        val app = RuntimeEnvironment.getApplication()
        shadowOf(app).denyPermissions(Manifest.permission.RECORD_AUDIO)
        assertFalse(SetupStatus.read(app, AppPreferences()).microphoneDenied)
        markPermissionAsked(app, Manifest.permission.RECORD_AUDIO)
        assertTrue(SetupStatus.read(app, AppPreferences()).microphoneDenied)
        shadowOf(app).grantPermissions(Manifest.permission.RECORD_AUDIO)
        assertFalse(SetupStatus.read(app, AppPreferences()).microphoneDenied)
    }

    @Test fun notificationRequestIsRememberedIndependentlyOfMicrophone() {
        val app = RuntimeEnvironment.getApplication()
        shadowOf(app.getSystemService(android.app.NotificationManager::class.java)).setNotificationsEnabled(false)
        assertFalse(SetupStatus.read(app, AppPreferences()).notificationsDenied)
        markPermissionAsked(app, Manifest.permission.POST_NOTIFICATIONS)
        assertTrue(SetupStatus.read(app, AppPreferences()).notificationsDenied)
        assertFalse(permissionAsked(app, Manifest.permission.RECORD_AUDIO))
    }
}
