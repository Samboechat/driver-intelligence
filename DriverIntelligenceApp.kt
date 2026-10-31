package com.driverintelligence

import android.app.Application
import com.driverintelligence.capture.CaptureNotifications
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class DriverIntelligenceApp : Application() {
    override fun onCreate() {
        super.onCreate()
        CaptureNotifications.createChannel(this)
    }
}
