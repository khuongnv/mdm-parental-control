package com.mdm.parentalcontrol.child.service

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient

/**
 * DeviceTelemetryCollector (R2)
 *
 * Thu thập toàn bộ các chỉ số telemetry mở rộng của thiết bị con:
 * - Pin: battery_level, is_charging
 * - Độ sáng: screen_brightness (0..100%), is_auto_brightness
 * - Chế độ màn hình: screen_mode (on_unlocked, on_locked, off, doze), is_screen_on, is_dark_mode
 * - Âm lượng: media_volume, ring_volume, notification_volume, alarm_volume, ringer_mode, is_media_muted
 */
object DeviceTelemetryCollector {

    fun collect(
        context: Context,
        isScreenOn: Boolean,
        currentActivePackage: String
    ): MdmSupabaseClient.DeviceTelemetry {
        val (batteryLevel, isCharging) = getBatteryStatus(context)

        // 1. Độ sáng màn hình (screen_brightness: 0..100) & Chế độ tự động (is_auto_brightness)
        val brightnessRaw = try {
            Settings.System.getInt(context.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128)
        } catch (_: Exception) { 128 }
        val screenBrightness = (brightnessRaw * 100 / 255).coerceIn(0, 100)

        val isAutoBrightness = try {
            val mode = Settings.System.getInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            mode == Settings.System.SCREEN_BRIGHTNESS_MODE_AUTOMATIC
        } catch (_: Exception) { false }

        // 2. Chế độ màn hình: on_unlocked, on_locked, off, doze
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val isKeyguardLocked = keyguardManager?.isKeyguardLocked ?: false
        val screenMode = if (!isScreenOn) {
            "off"
        } else if (isKeyguardLocked) {
            "on_locked"
        } else {
            "on_unlocked"
        }

        // 3. Dark Mode / Theme
        val isDarkMode = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        // 4. Các kênh âm lượng & Ringer mode
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val maxMedia = (audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15).coerceAtLeast(1)
        val curMedia = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 7
        val mediaVolume = (curMedia * 100 / maxMedia).coerceIn(0, 100)

        val maxRing = (audioManager?.getStreamMaxVolume(AudioManager.STREAM_RING) ?: 7).coerceAtLeast(1)
        val curRing = audioManager?.getStreamVolume(AudioManager.STREAM_RING) ?: 4
        val ringVolume = (curRing * 100 / maxRing).coerceIn(0, 100)

        val maxNotif = (audioManager?.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION) ?: 7).coerceAtLeast(1)
        val curNotif = audioManager?.getStreamVolume(AudioManager.STREAM_NOTIFICATION) ?: 4
        val notificationVolume = (curNotif * 100 / maxNotif).coerceIn(0, 100)

        val maxAlarm = (audioManager?.getStreamMaxVolume(AudioManager.STREAM_ALARM) ?: 7).coerceAtLeast(1)
        val curAlarm = audioManager?.getStreamVolume(AudioManager.STREAM_ALARM) ?: 6
        val alarmVolume = (curAlarm * 100 / maxAlarm).coerceIn(0, 100)

        val ringerMode = when (audioManager?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "silent"
            AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
            else -> "normal"
        }
        val isMediaMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.isStreamMute(AudioManager.STREAM_MUSIC) ?: (mediaVolume == 0)
        } else {
            mediaVolume == 0
        }

        var appLabel = currentActivePackage
        var pkgName: String? = null
        try {
            if (currentActivePackage != "Màn hình chính") {
                pkgName = currentActivePackage
                val appInfo = context.packageManager.getApplicationInfo(currentActivePackage, 0)
                appLabel = context.packageManager.getApplicationLabel(appInfo).toString()
            }
        } catch (_: Exception) {}

        return MdmSupabaseClient.DeviceTelemetry(
            batteryLevel = batteryLevel,
            isCharging = isCharging,
            currentApp = appLabel,
            currentPackageName = pkgName,
            screenBrightness = screenBrightness,
            isAutoBrightness = isAutoBrightness,
            screenMode = screenMode,
            isScreenOn = isScreenOn,
            isDarkMode = isDarkMode,
            mediaVolume = mediaVolume,
            ringVolume = ringVolume,
            notificationVolume = notificationVolume,
            alarmVolume = alarmVolume,
            ringerMode = ringerMode,
            isMediaMuted = isMediaMuted
        )
    }

    private fun getBatteryStatus(context: Context): Pair<Int, Boolean> {
        val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus: Intent? = context.registerReceiver(null, ifilter)

        val level = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 50

        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        return Pair(batteryPct, isCharging)
    }
}
