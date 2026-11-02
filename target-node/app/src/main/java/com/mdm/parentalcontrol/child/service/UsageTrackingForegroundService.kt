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
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.util.Log
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import com.mdm.parentalcontrol.child.data.local.AppUsageEventEntity
import com.mdm.parentalcontrol.child.data.local.DailyAppUsageEntity
import com.mdm.parentalcontrol.child.data.local.DevicePolicyLocalEntity
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.data.local.UsageDao
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
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

    @Inject
    lateinit var devicePreferences: DevicePreferences

    @Inject
    lateinit var supabaseClient: MdmSupabaseClient

    private var pollingJob: Job? = null
    private var isScreenOn = true
    private var lastEventQueryTime = System.currentTimeMillis()
    private var lastTelemetryReportTime = 0L
    private var hasShown5MinWarningToday = false
    private var currentActivePackage = "Màn hình chính"

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    Log.d(TAG, "Screen ON: Resuming high-frequency usage polling")
                    isScreenOn = true
                    startAdaptivePolling()
                    ensureSupabaseConnection()
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
        ensureSupabaseConnection()
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(screenReceiver)
        stopAdaptivePolling()
        supabaseClient.disconnect()
    }

    /**
     * Duy trì kết nối Supabase Realtime ngầm trong Foreground Service
     * Nhận lệnh Panic Lockdown, Thưởng/Phạt động, Tin nhắn nhắc nhở và Duyệt xin giờ
     */
    fun ensureSupabaseConnection() {
        val deviceId = devicePreferences.deviceId
        if (!deviceId.isNullOrEmpty()) {
            supabaseClient.connectRealtime(
                deviceId = deviceId,
                onPanicLockdown = { isLocked ->
                    Log.w(TAG, "🚨 Foreground Service handling PANIC_LOCKDOWN: $isLocked")
                    ChildNotificationHelper.showPanicLockdownNotification(this@UsageTrackingForegroundService, isLocked)
                    lifecycleScope.launch(Dispatchers.Main) {
                        Toast.makeText(
                            this@UsageTrackingForegroundService,
                            if (isLocked) "🚨 Thiết bị đã bị ba mẹ khóa khẩn cấp!" else "✅ Thiết bị đã được ba mẹ mở khóa!",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                    lifecycleScope.launch(Dispatchers.IO) {
                        val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
                        usageDao.savePolicy(currentPolicy.copy(isEmergencyLockdown = isLocked))
                        enforceLockdown(isLocked)
                    }
                },
                onExtraTime = { minutes ->
                    Log.i(TAG, "⏳ Foreground Service handling GRANT_EXTRA_TIME: +$minutes minutes")
                    ChildNotificationHelper.showTimeAdjustedNotification(this@UsageTrackingForegroundService, minutes, "Ba mẹ thưởng thêm")
                    lifecycleScope.launch(Dispatchers.Main) {
                        Toast.makeText(
                            this@UsageTrackingForegroundService,
                            "🎁 Ba mẹ đã thưởng thêm $minutes phút sử dụng!",
                            Toast.LENGTH_LONG
                        ).show()
                    }
                    lifecycleScope.launch(Dispatchers.IO) {
                        hasShown5MinWarningToday = false
                        val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
                        usageDao.savePolicy(currentPolicy.copy(dailyLimitMinutes = currentPolicy.dailyLimitMinutes + minutes, isEmergencyLockdown = false))
                        enforceLockdown(false)
                    }
                },
                onAdjustTime = { deltaMinutes, reason ->
                    Log.i(TAG, "⚡ Foreground Service handling ADJUST_SCREEN_TIME: delta=$deltaMinutes, reason=$reason")
                    ChildNotificationHelper.showTimeAdjustedNotification(this@UsageTrackingForegroundService, deltaMinutes, reason)
                    lifecycleScope.launch(Dispatchers.Main) {
                        val msg = if (deltaMinutes >= 0) {
                            "🎁 Ba mẹ đã thưởng thêm $deltaMinutes phút sử dụng!"
                        } else {
                            "⚠️ Ba mẹ đã trừ ${-deltaMinutes} phút giờ chơi! ${reason ?: ""}"
                        }
                        Toast.makeText(this@UsageTrackingForegroundService, msg, Toast.LENGTH_LONG).show()
                    }
                    lifecycleScope.launch(Dispatchers.IO) {
                        val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
                        val newLimit = (currentPolicy.dailyLimitMinutes + deltaMinutes).coerceAtLeast(0)
                        usageDao.savePolicy(currentPolicy.copy(dailyLimitMinutes = newLimit))

                        // Nếu phạt trừ giờ khiến đã vượt quota, lập tức khóa ngay
                        val today = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
                        val totalMs = usageDao.getTotalScreenTimeMs(today) ?: 0L
                        val totalMinutes = totalMs / (1000 * 60)
                        if (totalMinutes >= newLimit) {
                            enforceLockdown(true)
                        } else {
                            enforceLockdown(false)
                        }
                    }
                },
                onRemoteMessage = { msgId, title, body, _ ->
                    Log.i(TAG, "💬 Foreground Service handling REMOTE_MESSAGE: $title - $body")
                    showRemoteMessageNotification(msgId, title, body)
                },
                onTimeRequestResolved = { status, grantedMinutes ->
                    Log.i(TAG, "✅ Foreground Service handling TIME_REQUEST_RESOLVED: $status (+$grantedMinutes min)")
                    ChildNotificationHelper.showTimeRequestResolvedNotification(this@UsageTrackingForegroundService, status, grantedMinutes)
                    lifecycleScope.launch(Dispatchers.Main) {
                        if (status == "approved" && grantedMinutes > 0) {
                            Toast.makeText(this@UsageTrackingForegroundService, "🎉 Ba mẹ đã đồng ý cho con thêm $grantedMinutes phút!", Toast.LENGTH_LONG).show()
                        } else if (status == "rejected") {
                            Toast.makeText(this@UsageTrackingForegroundService, "Ba mẹ chưa đồng ý lúc này. Con hãy nghỉ ngơi nhé!", Toast.LENGTH_LONG).show()
                        }
                    }
                    if (status == "approved" && grantedMinutes > 0) {
                        lifecycleScope.launch(Dispatchers.IO) {
                            hasShown5MinWarningToday = false
                            val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
                            usageDao.savePolicy(currentPolicy.copy(dailyLimitMinutes = currentPolicy.dailyLimitMinutes + grantedMinutes, isEmergencyLockdown = false))
                            enforceLockdown(false)
                        }
                    }
                },
                onDeviceUnpaired = {
                    Log.w(TAG, "⚠️ Foreground Service handling DEVICE_UNPAIRED: Resetting local pairing state.")
                    devicePreferences.unpair()
                    lifecycleScope.launch(Dispatchers.IO) {
                        enforceLockdown(false)
                    }
                },
                onPairingSuccess = {
                    Log.i(TAG, "✨ Foreground Service: Device pairing claimed by parent!")
                    devicePreferences.isPaired = true
                }
            )
        }
    }

    private fun enforceLockdown(isLocked: Boolean) {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager ?: return
        val admin = ComponentName(this, MdmDeviceAdminReceiver::class.java)

        if (isLocked) {
            // 1. Nếu là Device Admin: Khóa màn hình ngay lập tức
            if (dpm.isAdminActive(admin)) {
                try {
                    dpm.lockNow()
                    Log.i(TAG, "Device Admin: dpm.lockNow() executed successfully")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to lockNow", e)
                }
            }

            // 2. Nếu là Device Owner: Làm xám icon và khóa khởi chạy các ứng dụng
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && dpm.isDeviceOwnerApp(packageName)) {
                val whitelist = setOf(packageName, "com.android.dialer", "com.google.android.dialer", "com.samsung.android.dialer", "com.android.emergency")
                val toSuspend = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
                    .filter { (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 && !whitelist.contains(it.packageName) }
                    .map { it.packageName }
                    .toTypedArray()
                try {
                    dpm.setPackagesSuspended(admin, toSuspend, true)
                    Log.i(TAG, "Device Owner: Suspended ${toSuspend.size} packages")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to setPackagesSuspended", e)
                }
            }
        } else {
            // Mở khóa: gỡ bỏ suspended apps
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && dpm.isDeviceOwnerApp(packageName)) {
                val toUnsuspend = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
                    .map { it.packageName }
                    .toTypedArray()
                try {
                    dpm.setPackagesSuspended(admin, toUnsuspend, false)
                    Log.i(TAG, "Device Owner: Unsuspended packages")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to unsuspend packages", e)
                }
            }
        }
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
                    checkAndReportTelemetry()
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
                    currentActivePackage = currentPackage
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
        if (sessionMs <= 0 || packageName == this.packageName) return // Ignore self
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
            Log.w(TAG, "Quota exceeded ($totalMinutes >= ${policy.dailyLimitMinutes}) or emergency lockdown active! Enforcing suspension.")
            enforceLockdown(true)
        } else {
            // Kiểm tra cảnh báo trước 5 phút
            val remainingMins = (policy.dailyLimitMinutes - totalMinutes).toInt()
            if (remainingMins in 1..5 && !hasShown5MinWarningToday) {
                hasShown5MinWarningToday = true
                showFiveMinuteWarning(remainingMins)
            }
        }
    }

    private fun checkAndReportTelemetry() {
        val now = System.currentTimeMillis()
        if (now - lastTelemetryReportTime > 30000L) { // Gửi telemetry mỗi 30 giây
            lastTelemetryReportTime = now
            val deviceId = devicePreferences.deviceId ?: return
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            val batteryLevel = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
            val isCharging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                bm?.isCharging == true
            } else false

            var appLabel = currentActivePackage
            try {
                val appInfo = packageManager.getApplicationInfo(currentActivePackage, 0)
                appLabel = packageManager.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {}

            supabaseClient.updateTelemetry(deviceId, batteryLevel, isCharging, appLabel)
        }
    }

    private fun showFiveMinuteWarning(minutesLeft: Int) {
        ChildNotificationHelper.showFiveMinuteWarning(this, minutesLeft)
    }

    private fun showRemoteMessageNotification(msgId: String, title: String, body: String) {
        val deviceId = devicePreferences.deviceId ?: ""
        ChildNotificationHelper.showRemoteMessageNotification(
            context = this,
            deviceId = deviceId,
            msgId = msgId,
            title = title,
            body = body
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val fgsChannel = NotificationChannel(
                CHANNEL_ID,
                "Device Protection & Screen Time Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Running in background to enforce parental screen time limits."
                setShowBadge(false)
            }
            manager.createNotificationChannel(fgsChannel)

            val alertChannel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "MDM Warnings & Parent Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "High priority notifications for remaining time warnings and parent reminders."
                enableVibration(true)
                setShowBadge(true)
            }
            manager.createNotificationChannel(alertChannel)
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
        const val ALERT_CHANNEL_ID = "mdm_alerts_channel"
        const val NOTIFICATION_ID = 1001
        const val ALERT_NOTIFICATION_ID = 1002
        private const val TAG = "UsageTrackingService"
    }
}
