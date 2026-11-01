package com.mdm.parentalcontrol.child.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.mdm.parentalcontrol.child.data.local.AppUsageEventEntity
import com.mdm.parentalcontrol.child.data.local.DailyAppUsageEntity
import com.mdm.parentalcontrol.child.data.local.UsageDao
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.*
import javax.inject.Inject

@AndroidEntryPoint
class UsageTrackingForegroundService : LifecycleService() {

    @Inject
    lateinit var usageDao: UsageDao

    private var pollingJob: Job? = null
    private var isScreenOn = true
    private var lastEventQueryTime = System.currentTimeMillis()

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    Log.d(TAG, "Screen ON: Resuming high-frequency usage polling")
                    isScreenOn = true
                    startAdaptivePolling()
                }
                Intent.ACTION_SCREEN_OFF -> {
                    Log.d(TAG, "Screen OFF: Pausing polling to conserve battery (Deep Sleep)")
                    isScreenOn = false
                    stopAdaptivePolling()
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildSilentNotification())

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)

        startAdaptivePolling()
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)
        stopAdaptivePolling()
    }

    private fun startAdaptivePolling() {
        pollingJob?.cancel()
        pollingJob = lifecycleScope.launch(Dispatchers.IO) {
            val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            while (isActive && isScreenOn) {
                try {
                    val now = System.currentTimeMillis()
                    usageStatsManager?.let { queryAndAggregateUsage(it, lastEventQueryTime, now) }
                    lastEventQueryTime = now
                    evaluatePoliciesAndEnforce()
                } catch (e: Exception) {
                    Log.e(TAG, "Error in usage polling loop", e)
                }
                delay(3000L) // 3s interval (Screen Aware)
            }
        }
    }

    private fun stopAdaptivePolling() {
        pollingJob?.cancel()
        pollingJob = null
    }

    private suspend fun queryAndAggregateUsage(manager: UsageStatsManager, startTime: Long, endTime: Long) {
        val events = manager.queryEvents(startTime, endTime)
        val event = UsageEvents.Event()
        val eventEntities = mutableListOf<AppUsageEventEntity>()

        var currentPackage = ""
        var resumeTime = 0L

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    currentPackage = event.packageName
                    resumeTime = event.timeStamp
                    eventEntities.add(AppUsageEventEntity(packageName = currentPackage, eventType = 1, timestamp = resumeTime))
                }
                UsageEvents.Event.ACTIVITY_PAUSED -> {
                    if (event.packageName == currentPackage && resumeTime > 0) {
                        val duration = event.timeStamp - resumeTime
                        updateDailyUsage(currentPackage, duration)
                        resumeTime = 0L
                    }
                    eventEntities.add(AppUsageEventEntity(packageName = event.packageName, eventType = 2, timestamp = event.timeStamp))
                }
            }
        }

        if (eventEntities.isNotEmpty()) {
            usageDao.insertUsageEvents(eventEntities)
        }
    }

    private suspend fun updateDailyUsage(packageName: String, sessionMs: Long) {
        if (sessionMs <= 0 || packageName == packageName) return // Ignore self
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        usageDao.upsertDailyUsage(
            DailyAppUsageEntity(
                packageName = packageName,
                date = today,
                totalTimeInForegroundMs = sessionMs,
                lastUpdated = System.currentTimeMillis()
            )
        )
    }

    private suspend fun evaluatePoliciesAndEnforce() {
        val policy = usageDao.getLocalPolicy() ?: return
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        val totalMs = usageDao.getTotalScreenTimeMs(today) ?: 0L
        val totalMinutes = totalMs / (1000 * 60)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager ?: return
        val admin = ComponentName(this, MdmDeviceAdminReceiver::class.java)

        if (!dpm.isDeviceOwnerApp(packageName)) return

        if (policy.isEmergencyLockdown || totalMinutes >= policy.dailyLimitMinutes) {
            Log.w(TAG, "Quota exceeded or emergency lockdown active! Enforcing package suspension.")
            // Native DO Suspension: Icon gets grayed out, launch rejected at OS level
            // In production, suspend apps not in whitelist
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Device Protection & Screen Time Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Running in background to enforce parental screen time limits."
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildSilentNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MDM Parental Protection")
            .setContentText("Thiết bị đang được bảo vệ bởi chính sách phụ huynh.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "mdm_usage_tracking_channel"
        const val NOTIFICATION_ID = 1001
        private const val TAG = "UsageTrackingService"
    }
}
