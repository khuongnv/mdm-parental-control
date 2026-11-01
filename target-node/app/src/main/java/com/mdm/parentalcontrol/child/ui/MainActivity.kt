package com.mdm.parentalcontrol.child.ui

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {

    @Inject
    lateinit var supabaseClient: MdmSupabaseClient

    private var activeDeviceId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val isDo = dpm.isDeviceOwnerApp(packageName)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 64, 48, 48)
        }

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

        val pairingInfoView = TextView(this).apply {
            textSize = 16f
            setPadding(0, 48, 0, 24)
            text = "⚡ Kết nối Supabase: Chưa tạo mã ghép nối"
        }
        layout.addView(pairingInfoView)

        val pairingButton = Button(this).apply {
            text = "Tạo Mã Ghép Nối Với Phụ Huynh (OTP)"
            setOnClickListener {
                pairingInfoView.text = "Đang kết nối Supabase để sinh mã OTP..."
                val deviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
                supabaseClient.createPairingSession(
                    deviceName = deviceName,
                    model = Build.MODEL,
                    osVersion = "Android ${Build.VERSION.RELEASE}",
                    onSuccess = { result ->
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
                                    }
                                },
                                onExtraTime = { mins ->
                                    runOnUiThread {
                                        pairingInfoView.append("\n\n⏳ NHẬN THƯỞNG GIỜ: +$mins phút")
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
        supabaseClient.disconnect()
    }
}
