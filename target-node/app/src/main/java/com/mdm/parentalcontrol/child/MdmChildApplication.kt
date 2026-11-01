package com.mdm.parentalcontrol.child

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class MdmChildApplication : Application() {
    override fun onCreate() {
        super.onCreate()
    }
}
