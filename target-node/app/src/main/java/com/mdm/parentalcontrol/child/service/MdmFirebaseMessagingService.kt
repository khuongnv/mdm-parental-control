package com.mdm.parentalcontrol.child.service

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.mdm.parentalcontrol.child.data.local.DevicePolicyLocalEntity
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.data.local.UsageDao
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Dịch vụ nhận thông báo đẩy ngầm ưu tiên cao (FCM High-Priority Silent Push)
 * Kênh dự phòng đánh thức thiết bị con khi ở chế độ ngủ sâu (Doze Mode) hoặc mất kết nối WebSocket
 */
@AndroidEntryPoint
class MdmFirebaseMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var devicePreferences: DevicePreferences

    @Inject
    lateinit var supabaseClient: MdmSupabaseClient

    @Inject
    lateinit var usageDao: UsageDao

    private val serviceScope = CoroutineScope(Dispatchers.IO)

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔥 New FCM Token received: $token")
        devicePreferences.fcmToken = token

        val deviceId = devicePreferences.deviceId
        if (!deviceId.isNullOrEmpty()) {
            supabaseClient.updateFcmToken(deviceId, token) { success ->
                Log.d(TAG, "FCM token synced to Supabase: $success")
            }
        }
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        Log.w(TAG, "📥 FCM High-Priority Push received: $data")

        val action = data["action"] ?: return

        when (action) {
            ACTION_PANIC_LOCKDOWN -> {
                val isLocked = data["is_locked"]?.toBoolean() ?: true
                Log.w(TAG, "🚨 Executing PANIC_LOCKDOWN via FCM: $isLocked")
                ChildNotificationHelper.showPanicLockdownNotification(this, isLocked)
                handlePanicLockdown(isLocked)
            }
            ACTION_GRANT_EXTRA_TIME, ACTION_ADJUST_TIME -> {
                val extraMinutes = data["extra_minutes"]?.toIntOrNull()
                    ?: data["delta_minutes"]?.toIntOrNull() ?: 15
                val reason = data["reason"]
                Log.i(TAG, "⏳ Granting extra time via FCM: +$extraMinutes mins")
                ChildNotificationHelper.showTimeAdjustedNotification(this, extraMinutes, reason)
                handleGrantExtraTime(extraMinutes)
            }
            ACTION_REMOTE_MESSAGE -> {
                val msgId = data["message_id"] ?: System.currentTimeMillis().toString()
                val title = data["title"] ?: "🔔 Nhắc nhở từ Ba Mẹ"
                val body = data["body"] ?: ""
                val devId = devicePreferences.deviceId ?: ""
                Log.i(TAG, "💬 Received REMOTE_MESSAGE via FCM: $title - $body")
                ChildNotificationHelper.showRemoteMessageNotification(this, devId, msgId, title, body)
            }
            ACTION_TIME_REQUEST_RESOLVED -> {
                val status = data["status"] ?: "approved"
                val granted = data["granted_minutes"]?.toIntOrNull() ?: 0
                Log.i(TAG, "✅ Received TIME_REQUEST_RESOLVED via FCM: $status (+$granted min)")
                ChildNotificationHelper.showTimeRequestResolvedNotification(this, status, granted)
                if (status == "approved" && granted > 0) {
                    handleGrantExtraTime(granted)
                }
            }
            ACTION_SYNC_POLICY -> {
                Log.i(TAG, "🔄 Sync policy requested via FCM")
                wakeUpTrackingService()
            }
        }
    }

    private fun handlePanicLockdown(isLocked: Boolean) {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, MdmDeviceAdminReceiver::class.java)

        if (dpm.isDeviceOwnerApp(packageName)) {
            val emergencyWhitelist = setOf(
                packageName,
                "com.android.phone",
                "com.android.server.telecom",
                "com.google.android.dialer",
                "com.android.emergency"
            )
            val packagesToSuspend = packageManager.getInstalledApplications(0)
                .map { it.packageName }
                .filter { it !in emergencyWhitelist }
                .toTypedArray()

            try {
                dpm.setPackagesSuspended(admin, packagesToSuspend, isLocked)
                Log.i(TAG, "✅ Device Policy setPackagesSuspended($isLocked) applied successfully via FCM")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to suspend packages via FCM", e)
            }
        }

        serviceScope.launch {
            val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
            usageDao.savePolicy(currentPolicy.copy(isEmergencyLockdown = isLocked))
        }

        wakeUpTrackingService()
    }

    private fun handleGrantExtraTime(extraMinutes: Int) {
        serviceScope.launch {
            val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
            val newTotalLimit = currentPolicy.dailyLimitMinutes + extraMinutes
            usageDao.savePolicy(currentPolicy.copy(dailyLimitMinutes = newTotalLimit))
        }
        wakeUpTrackingService()
    }

    /**
     * Đánh thức Foreground Service để đảm bảo theo dõi liên tục và tái lập WebSocket
     */
    private fun wakeUpTrackingService() {
        try {
            val intent = Intent(this, UsageTrackingForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to wake up tracking service", e)
        }
    }

    companion object {
        private const val TAG = "MdmFCMService"
        const val ACTION_PANIC_LOCKDOWN = "PANIC_LOCKDOWN"
        const val ACTION_GRANT_EXTRA_TIME = "GRANT_EXTRA_TIME"
        const val ACTION_ADJUST_TIME = "ADJUST_SCREEN_TIME"
        const val ACTION_REMOTE_MESSAGE = "REMOTE_MESSAGE"
        const val ACTION_TIME_REQUEST_RESOLVED = "TIME_REQUEST_RESOLVED"
        const val ACTION_SYNC_POLICY = "SYNC_POLICY"
    }
}
