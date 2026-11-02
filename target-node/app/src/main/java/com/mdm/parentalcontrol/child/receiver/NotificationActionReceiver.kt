package com.mdm.parentalcontrol.child.receiver

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.widget.Toast
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/**
 * Receiver xử lý tương tác trực tiếp từ thanh thông báo hệ thống (Notification Actions)
 * Cho phép bé bấm "Dạ Con Nghe Rồi! 👍" ngay từ Trung tâm thông báo mà không cần mở app
 */
@AndroidEntryPoint
class NotificationActionReceiver : BroadcastReceiver() {

    @Inject
    lateinit var supabaseClient: MdmSupabaseClient

    @Inject
    lateinit var devicePreferences: DevicePreferences

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.i(TAG, "Received notification action: $action")

        if (action == ACTION_ACK_MESSAGE) {
            val pendingResult = goAsync()
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val wakeLock = powerManager?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Mdm:NotificationActionAckWakeLock"
            )?.apply {
                acquire(5000L) // Giữ tối đa 5 giây cho OkHttp request
            }

            val msgId = intent.getStringExtra(EXTRA_MSG_ID) ?: ""
            val notifId = intent.getIntExtra(EXTRA_NOTIF_ID, 0)
            val deviceId = intent.getStringExtra(EXTRA_DEVICE_ID)?.takeIf { it.isNotEmpty() }
                ?: devicePreferences.deviceId ?: ""

            // 1. Đóng thông báo trên thanh trạng thái
            if (notifId != 0) {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notifId)
            }

            // 2. Gửi phản hồi ACK ngay lập tức lên Supabase
            if (deviceId.isNotEmpty() && msgId.isNotEmpty()) {
                supabaseClient.sendAckMessage(deviceId, msgId) { ok ->
                    Log.i(TAG, "Completed sendAckMessage in NotificationActionReceiver: success=$ok")
                    try {
                        if (wakeLock?.isHeld == true) wakeLock.release()
                    } catch (e: Exception) {
                        Log.w(TAG, "Error releasing wakeLock: ${e.message}")
                    }
                    pendingResult.finish()
                }
            } else {
                try {
                    if (wakeLock?.isHeld == true) wakeLock.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Error releasing wakeLock: ${e.message}")
                }
                pendingResult.finish()
            }

            // 3. Phản hồi Toast cho bé
            Handler(Looper.getMainLooper()).post {
                Toast.makeText(context, "✅ Đã phản hồi cho Ba Mẹ: Dạ con nghe rồi! 👍", Toast.LENGTH_LONG).show()
            }
        }
    }

    companion object {
        private const val TAG = "NotificationActionReceiver"
        const val ACTION_ACK_MESSAGE = "com.mdm.parentalcontrol.child.ACTION_ACK_MESSAGE"
        const val EXTRA_MSG_ID = "extra_msg_id"
        const val EXTRA_DEVICE_ID = "extra_device_id"
        const val EXTRA_NOTIF_ID = "extra_notif_id"
    }
}
