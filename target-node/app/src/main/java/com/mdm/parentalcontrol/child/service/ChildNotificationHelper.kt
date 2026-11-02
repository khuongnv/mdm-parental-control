package com.mdm.parentalcontrol.child.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.mdm.parentalcontrol.child.R
import com.mdm.parentalcontrol.child.receiver.NotificationActionReceiver
import com.mdm.parentalcontrol.child.ui.MainActivity

/**
 * Quản lý tập trung toàn bộ thông báo hệ thống (System Notification Center) cho máy Con
 * Đảm bảo mọi thông báo từ Ba Mẹ đều xuất hiện trên Thanh trạng thái / Trung tâm thông báo
 * ngay cả khi máy con đang tắt màn hình, ở màn hình chính hoặc đang mở ứng dụng khác.
 */
object ChildNotificationHelper {

    const val CHANNEL_ALERTS_ID = "mdm_child_alerts_channel"
    const val CHANNEL_ALERTS_NAME = "Thông Báo & Nhắc Nhở Từ Ba Mẹ"
    const val CHANNEL_ALERTS_DESC = "Nhận thông điệp nhắc nhở, thưởng phạt giờ chơi và phê duyệt từ phụ huynh"

    private const val NOTIF_ID_TIME_ADJUST = 1001
    private const val NOTIF_ID_TIME_RESOLVE = 1002
    private const val NOTIF_ID_LOCKDOWN = 1003
    private const val NOTIF_ID_WARNING_5MIN = 1004

    /**
     * Khởi tạo Notification Channel ưu tiên cao (Heads-up, rung, âm thanh)
     */
    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                CHANNEL_ALERTS_ID,
                CHANNEL_ALERTS_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_ALERTS_DESC
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }
    }

    /**
     * 1. Hiển thị thông báo tin nhắn / lời nhắc từ Ba Mẹ với Action Button trả lời ngay
     */
    fun showRemoteMessageNotification(
        context: Context,
        deviceId: String,
        msgId: String,
        title: String,
        body: String
    ) {
        createChannels(context)
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notifId = msgId.hashCode()

        // Intent khi bé nhấn vào thân thông báo -> Mở MainActivity và hiển thị dialog
        val contentIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("SHOW_REMOTE_MESSAGE_ID", msgId)
            putExtra("SHOW_REMOTE_MESSAGE_TITLE", title)
            putExtra("SHOW_REMOTE_MESSAGE_BODY", body)
        }
        val contentPendingIntent = PendingIntent.getActivity(
            context,
            notifId,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action Intent khi bé nhấn trực tiếp nút "Dạ Con Nghe Rồi! 👍" trên thanh thông báo
        val ackIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = NotificationActionReceiver.ACTION_ACK_MESSAGE
            putExtra(NotificationActionReceiver.EXTRA_MSG_ID, msgId)
            putExtra(NotificationActionReceiver.EXTRA_DEVICE_ID, deviceId)
            putExtra(NotificationActionReceiver.EXTRA_NOTIF_ID, notifId)
        }
        val ackPendingIntent = PendingIntent.getBroadcast(
            context,
            notifId + 1,
            ackIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ALERTS_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)
            .addAction(
                android.R.drawable.checkbox_on_background,
                "Dạ Con Nghe Rồi! 👍",
                ackPendingIntent
            )

        notificationManager.notify(notifId, builder.build())
    }

    /**
     * 2. Thông báo kết quả Ba Mẹ duyệt yêu cầu xin thêm giờ chơi
     */
    fun showTimeRequestResolvedNotification(
        context: Context,
        status: String,
        grantedMinutes: Int
    ) {
        createChannels(context)
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val isApproved = status == "approved" && grantedMinutes > 0
        val title = if (isApproved) "🎉 Ba Mẹ Đã Duyệt Giờ Chơi!" else "Ba Mẹ Chưa Duyệt Giờ Chơi"
        val body = if (isApproved) {
            "Ba Mẹ đã cộng thêm +$grantedMinutes phút vào thời gian sử dụng hôm nay của con!"
        } else {
            "Ba mẹ chưa đồng ý lúc này. Con hãy nghỉ ngơi và chuẩn bị học bài nhé!"
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_TIME_RESOLVE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ALERTS_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        notificationManager.notify(NOTIF_ID_TIME_RESOLVE, builder.build())
    }

    /**
     * 3. Thông báo thưởng / phạt giờ chơi từ Ba Mẹ
     */
    fun showTimeAdjustedNotification(
        context: Context,
        deltaMinutes: Int,
        reason: String?
    ) {
        createChannels(context)
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val isBonus = deltaMinutes >= 0
        val title = if (isBonus) "🎁 Ba Mẹ Đã Thưởng Giờ Chơi!" else "⚠️ Ba Mẹ Đã Trừ Giờ Chơi!"
        val reasonStr = if (!reason.isNullOrBlank()) " Lý do: $reason" else ""
        val body = if (isBonus) {
            "Con được cộng thêm +$deltaMinutes phút sử dụng.$reasonStr"
        } else {
            "Hạn mức hôm nay bị trừ ${-deltaMinutes} phút.$reasonStr"
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_TIME_ADJUST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ALERTS_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        notificationManager.notify(NOTIF_ID_TIME_ADJUST, builder.build())
    }

    /**
     * 4. Thông báo chế độ Khóa khẩn cấp (Panic Lockdown)
     */
    fun showPanicLockdownNotification(
        context: Context,
        isLocked: Boolean
    ) {
        createChannels(context)
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val title = if (isLocked) "🚨 Thiết Bị Đã Bị Khóa Khẩn Cấp!" else "🔓 Thiết Bị Đã Được Mở Khóa"
        val body = if (isLocked) {
            "Ba Mẹ đã kích hoạt chế độ khóa khẩn cấp. Các ứng dụng giải trí tạm thời bị vô hiệu hóa."
        } else {
            "Ba Mẹ đã mở khóa thiết bị. Con có thể tiếp tục sử dụng theo hạn mức quy định."
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_LOCKDOWN,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ALERTS_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        notificationManager.notify(NOTIF_ID_LOCKDOWN, builder.build())
    }

    /**
     * 5. Cảnh báo còn 5 phút sử dụng
     */
    fun showFiveMinuteWarning(context: Context, minutesLeft: Int) {
        createChannels(context)
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val title = "⚠️ Chú ý: Còn $minutesLeft phút sử dụng!"
        val body = "Thiết bị sẽ tự động khóa sau $minutesLeft phút nữa. Con hãy lưu bài tập và chuẩn bị tắt máy nhé!"

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIF_ID_WARNING_5MIN,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ALERTS_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)

        notificationManager.notify(NOTIF_ID_WARNING_5MIN, builder.build())
    }
}
