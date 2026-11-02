package com.mdm.parentalcontrol.child

import android.app.Application
import com.mdm.parentalcontrol.child.receiver.MidnightResetReceiver
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class MdmChildApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Kích hoạt lịch tự động reset hạn mức cục bộ lúc 00:00:00
        MidnightResetReceiver.scheduleNextMidnightAlarm(this)
    }
}
