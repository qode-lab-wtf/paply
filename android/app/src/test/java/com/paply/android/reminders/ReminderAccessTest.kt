package com.paply.android.reminders

import android.app.AlarmManager
import android.provider.Settings
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [35])
class ReminderAccessTest {
    @Test fun missingAccessOpensPackageSpecificSystemPage() {
        val app = RuntimeEnvironment.getApplication()
        shadowOf(app.getSystemService(AlarmManager::class.java)).setCanScheduleExactAlarms(false)
        val intent = ReminderAlarms(app).exactAccessIntent()!!
        assertEquals(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, intent.action)
        assertEquals("package:${app.packageName}", intent.dataString)
        shadowOf(app.getSystemService(AlarmManager::class.java)).setCanScheduleExactAlarms(true)
        assertNull(ReminderAlarms(app).exactAccessIntent())
    }
    @Test @Config(sdk = [29]) fun oldAndroidDoesNotRequestSpecialAccess() {
        assertNull(ReminderAlarms(RuntimeEnvironment.getApplication()).exactAccessIntent())
    }
}
