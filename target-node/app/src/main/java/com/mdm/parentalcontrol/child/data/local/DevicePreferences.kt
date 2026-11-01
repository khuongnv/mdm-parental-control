package com.mdm.parentalcontrol.child.data.local

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Quản lý cấu hình định danh thiết bị con cục bộ
 * Lưu trữ vĩnh viễn Device ID nhận được từ Supabase sau khi ghép nối
 */
@Singleton
class DevicePreferences @Inject constructor(
    @ApplicationContext context: Context
) {
    private val prefs: SharedPreferences = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)

    var deviceId: String?
        get() = prefs.getString(KEY_DEVICE_ID, null)
        set(value) = prefs.edit().putString(KEY_DEVICE_ID, value).apply()

    var isPaired: Boolean
        get() = prefs.getBoolean(KEY_IS_PAIRED, false)
        set(value) = prefs.edit().putBoolean(KEY_IS_PAIRED, value).apply()

    var otpCode: String?
        get() = prefs.getString(KEY_OTP_CODE, null)
        set(value) = prefs.edit().putString(KEY_OTP_CODE, value).apply()

    var qrToken: String?
        get() = prefs.getString(KEY_QR_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_QR_TOKEN, value).apply()

    var deviceName: String?
        get() = prefs.getString(KEY_DEVICE_NAME, null)
        set(value) = prefs.edit().putString(KEY_DEVICE_NAME, value).apply()

    var fcmToken: String?
        get() = prefs.getString(KEY_FCM_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_FCM_TOKEN, value).apply()

    var pairedAt: Long
        get() = prefs.getLong(KEY_PAIRED_AT, 0L)
        set(value) = prefs.edit().putLong(KEY_PAIRED_AT, value).apply()

    fun savePairing(deviceId: String, otpCode: String?, deviceName: String?, qrToken: String? = null) {
        prefs.edit()
            .putString(KEY_DEVICE_ID, deviceId)
            .putString(KEY_OTP_CODE, otpCode)
            .putString(KEY_DEVICE_NAME, deviceName)
            .putString(KEY_QR_TOKEN, qrToken)
            .apply()
    }

    fun completePairing(deviceId: String, deviceName: String?) {
        prefs.edit()
            .putString(KEY_DEVICE_ID, deviceId)
            .putString(KEY_DEVICE_NAME, deviceName)
            .putBoolean(KEY_IS_PAIRED, true)
            .remove(KEY_OTP_CODE)
            .remove(KEY_QR_TOKEN)
            .putLong(KEY_PAIRED_AT, System.currentTimeMillis())
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREF_NAME = "mdm_child_device_config"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_IS_PAIRED = "is_paired"
        private const val KEY_OTP_CODE = "otp_code"
        private const val KEY_QR_TOKEN = "qr_token"
        private const val KEY_DEVICE_NAME = "device_name"
        private const val KEY_FCM_TOKEN = "fcm_token"
        private const val KEY_PAIRED_AT = "paired_at"
    }
}
