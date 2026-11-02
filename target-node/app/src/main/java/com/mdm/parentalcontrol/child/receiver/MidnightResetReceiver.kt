package com.mdm.parentalcontrol.child.receiver

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.mdm.parentalcontrol.child.data.local.DevicePolicyLocalEntity
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.data.local.UsageDao
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.Calendar
import javax.inject.Inject

/**
 * Receiver tự động kích hoạt vào đúng 00:00:00 (nửa đêm) hàng ngày theo giờ máy con.
 * Vận hành hoàn toàn Cục Bộ (Local-First / Offline-Resilient) để:
 * 1. Hoàn trả hạn mức ngày về mặc định (2 giờ = 120 phút).
 * 2. Giải phóng trạng thái khóa và Un-suspend toàn bộ ứng dụng cho ngày mới.
 * 3. Lập lịch cho đêm tiếp theo.
 */
@AndroidEntryPoint
class MidnightResetReceiver : BroadcastReceiver() {

    @Inject
    lateinit var usageDao: UsageDao

    @Inject
    lateinit var devicePreferences: DevicePreferences

    override fun onReceive(context: Context, intent: Intent) {
        Log.i(TAG, "🌙 MidnightResetReceiver triggered at 00:00:00! Performing daily reset routine.")

        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // 1. Phục hồi chính sách về hạn mức chuẩn (Mặc định 120 phút / 2 giờ)
                val currentPolicy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
                val resetPolicy = currentPolicy.copy(
                    dailyLimitMinutes = 120, // Reset về 2 giờ mặc định
                    isEmergencyLockdown = false
                )
                usageDao.savePolicy(resetPolicy)
                Log.i(TAG, "Daily quota successfully reset to 120 minutes.")

                // 2. Mở khóa (Un-suspend) toàn bộ ứng dụng cho ngày mới
                val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                val admin = ComponentName(context, MdmDeviceAdminReceiver::class.java)

                if (dpm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && dpm.isDeviceOwnerApp(context.packageName)) {
                    val toUnsuspend = context.packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
                        .map { it.packageName }
                        .toTypedArray()
                    try {
                        dpm.setPackagesSuspended(admin, toUnsuspend, false)
                        Log.i(TAG, "Midnight routine: Successfully unsuspended ${toUnsuspend.size} packages.")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to unsuspend packages at midnight", e)
                    }
                }

                // 3. Lập lịch cho nửa đêm tiếp theo
                scheduleNextMidnightAlarm(context)
            } catch (e: Exception) {
                Log.e(TAG, "Error executing midnight reset routine", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val TAG = "MidnightResetReceiver"
        private const val REQUEST_CODE = 9001

        /**
         * Lập lịch Alarm chính xác đánh thức máy con vào đúng 00:00:00 đêm tiếp theo
         */
        fun scheduleNextMidnightAlarm(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, MidnightResetReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)

            // Tính toán thời điểm 00:00:00 của ngày hôm sau
            val calendar = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val triggerAtMillis = calendar.timeInMillis

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }
                Log.i(TAG, "Next midnight reset scheduled for: ${calendar.time}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule exact midnight alarm", e)
            }
        }
    }
}
