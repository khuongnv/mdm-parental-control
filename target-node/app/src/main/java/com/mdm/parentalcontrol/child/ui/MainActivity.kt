package com.mdm.parentalcontrol.child.ui

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.widget.Toast
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.firebase.messaging.FirebaseMessaging
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {

    @Inject
    lateinit var supabaseClient: MdmSupabaseClient

    @Inject
    lateinit var devicePreferences: DevicePreferences

    private var activeDeviceId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val isDo = dpm.isDeviceOwnerApp(packageName)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 64, 48, 48)
        }

        val headerView = TextView(this).apply {
            textSize = 22f
            text = "🌱 VFam Child - Không Gian An Toàn"
            setTextColor(android.graphics.Color.parseColor("#059669")) // Mint Green
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, 0, 0, 32)
        }
        layout.addView(headerView)

        val statusView = TextView(this).apply {
            textSize = 18f
            text = if (isDo) {
                "🛡️ Trạng thái: DEVICE OWNER ĐÃ KÍCH HOẠT\n\nCác chính sách bảo mật, chống gỡ cài đặt và kiểm soát thời lượng đang có hiệu lực tuyệt đối."
            } else {
                "⚠️ Trạng thái: CHƯA KÍCH HOẠT DEVICE OWNER\n\nHãy kích hoạt thông qua ADB:\n\nadb shell dpm set-device-owner " +
                        packageName + "/" + MdmDeviceAdminReceiver::class.java.canonicalName
            }
        }
        layout.addView(statusView)

        val savedId = devicePreferences.deviceId
        val savedOtp = devicePreferences.otpCode
        val savedDeviceName = devicePreferences.deviceName
        activeDeviceId = savedId

        val initialInfo = if (!savedId.isNullOrEmpty()) {
            "⚡ Đã lưu cấu hình thiết bị:\n\n" +
                    "👉 Thiết bị: ${savedDeviceName ?: "Thiết bị con"}\n" +
                    "👉 Device ID: $savedId\n" +
                    (if (!savedOtp.isNullOrEmpty()) "👉 Mã OTP gần nhất: [ $savedOtp ]\n" else "") +
                    "\nTrạng thái: Đang kết nối nền qua Foreground Service."
        } else {
            "⚡ Kết nối Supabase: Chưa tạo mã ghép nối"
        }

        // Lấy FCM Token và đồng bộ lên Supabase
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                Log.d("MainActivity", "🔥 Firebase FCM Token: $token")
                devicePreferences.fcmToken = token
                if (!savedId.isNullOrEmpty()) {
                    supabaseClient.updateFcmToken(savedId, token)
                }
            }
        }

        val pairingInfoView = TextView(this).apply {
            textSize = 16f
            setPadding(0, 48, 0, 24)
            text = initialInfo
        }
        layout.addView(pairingInfoView)

        val pairingButton = Button(this).apply {
            text = "✨ Tạo Mã Ghép Nối Với Phụ Huynh (OTP)"
            setBackgroundColor(android.graphics.Color.parseColor("#059669")) // Mint Green
            setTextColor(android.graphics.Color.WHITE)
            setOnClickListener {
                pairingInfoView.text = "Đang kết nối Supabase để sinh mã OTP..."
                val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
                supabaseClient.createPairingSession(
                    deviceName = deviceName,
                    model = Build.MODEL,
                    osVersion = "Android ${Build.VERSION.RELEASE}",
                    onSuccess = { result ->
                        // Lưu vĩnh viễn vào DevicePreferences để không mất khi restart app/OS
                        devicePreferences.savePairing(result.deviceId, result.otpCode, deviceName)

                        val currentFcmToken = devicePreferences.fcmToken
                        if (!currentFcmToken.isNullOrEmpty()) {
                            supabaseClient.updateFcmToken(result.deviceId, currentFcmToken)
                        }

                        runOnUiThread {
                            activeDeviceId = result.deviceId
                            pairingInfoView.text = "🔑 MÃ GHÉP NỐI CỦA BÉ:\n\n" +
                                    "👉 OTP: [ ${result.otpCode} ]\n\n" +
                                    "Thiết bị: $deviceName\n" +
                                    "Device ID: ${result.deviceId}\n" +
                                    "Hết hạn lúc: ${result.expiresAt}\n\n" +
                                    "Phụ huynh hãy mở Admin App và nhập mã OTP trên để kết nối."

                            // Lắng nghe Realtime Broadcast từ phụ huynh
                            supabaseClient.connectRealtime(
                                deviceId = result.deviceId,
                                onPanicLockdown = { isLocked ->
                                    runOnUiThread {
                                        pairingInfoView.append("\n\n🚨 NHẬN LỆNH KHÓA: $isLocked")
                                        if (isLocked) {
                                            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as? android.app.admin.DevicePolicyManager
                                            val admin = ComponentName(this@MainActivity, com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver::class.java)
                                            if (dpm != null && dpm.isAdminActive(admin)) {
                                                try {
                                                    dpm.lockNow()
                                                } catch (e: Exception) {
                                                    android.util.Log.e("MainActivity", "lockNow failed", e)
                                                }
                                            }
                                        }
                                    }
                                },
                                onExtraTime = { mins ->
                                    runOnUiThread {
                                        pairingInfoView.append("\n\n⏳ NHẬN THƯỞNG GIỜ: +$mins phút")
                                        Toast.makeText(this@MainActivity, "🎁 Ba mẹ đã thưởng thêm $mins phút sử dụng!", Toast.LENGTH_LONG).show()
                                    }
                                }
                            )
                        }
                    },
                    onError = { err ->
                        runOnUiThread {
                            pairingInfoView.text = "❌ Lỗi tạo phiên ghép nối: $err"
                        }
                    }
                )
            }
        }
        layout.addView(pairingButton)

        setContentView(layout)
    }

    override fun onDestroy() {
        super.onDestroy()
        // Không ngắt kết nối supabaseClient tại đây vì UsageTrackingForegroundService
        // cần duy trì kết nối WebSocket thời gian thực ngầm 24/7.
    }
}
