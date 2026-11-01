package com.mdm.parentalcontrol.child.ui

import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.mdm.parentalcontrol.child.R
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val isDo = dpm.isDeviceOwnerApp(packageName)

        val statusView = TextView(this).apply {
            textSize = 18f
            setPadding(48, 64, 48, 48)
            text = if (isDo) {
                "🛡️ Trạng thái: DEVICE OWNER ĐÃ KÍCH HOẠT\n\nCác chính sách bảo mật và chống gỡ cài đặt đang có hiệu lực tuyệt đối."
            } else {
                "⚠️ Trạng thái: CHƯA KÍCH HOẠT DEVICE OWNER\n\nHãy kích hoạt thông qua ADB:\n\nadb shell dpm set-device-owner " +
                        packageName + "/" + MdmDeviceAdminReceiver::class.java.canonicalName
            }
        }

        setContentView(statusView)
    }
}
