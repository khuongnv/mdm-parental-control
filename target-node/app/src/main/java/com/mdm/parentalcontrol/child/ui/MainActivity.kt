package com.mdm.parentalcontrol.child.ui

import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.lifecycleScope
import com.google.firebase.messaging.FirebaseMessaging
import com.mdm.parentalcontrol.child.data.local.DevicePolicyLocalEntity
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.data.local.UsageDao
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
import com.mdm.parentalcontrol.child.service.ChildNotificationHelper
import com.mdm.parentalcontrol.child.ui.components.*
import com.mdm.parentalcontrol.child.ui.theme.*
import com.mdm.parentalcontrol.child.updater.GitHubReleaseUpdater
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : AppCompatActivity() {

    @Inject
    lateinit var supabaseClient: MdmSupabaseClient

    @Inject
    lateinit var devicePreferences: DevicePreferences

    @Inject
    lateinit var releaseUpdater: GitHubReleaseUpdater

    @Inject
    lateinit var usageDao: UsageDao

    private val currentAppVersion = "1.2.4"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Đồng bộ FCM Token
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val token = task.result
                Log.d("MainActivity", "🔥 Firebase FCM Token: $token")
                devicePreferences.fcmToken = token
                val savedId = devicePreferences.deviceId
                if (!savedId.isNullOrEmpty()) {
                    supabaseClient.updateFcmToken(savedId, token)
                }
            }
        }

        setContent {
            ChildAppScreen()
        }
    }

    @Composable
    fun ChildAppScreen() {
        var isDarkMode by remember { mutableStateOf(true) }
        var isPaired by remember { mutableStateOf(devicePreferences.isPaired) }
        var deviceId by remember { mutableStateOf(devicePreferences.deviceId) }
        var deviceName by remember { mutableStateOf(devicePreferences.deviceName ?: "${Build.MANUFACTURER} ${Build.MODEL}") }
        var otpCode by remember { mutableStateOf(devicePreferences.otpCode) }
        var qrToken by remember { mutableStateOf(devicePreferences.qrToken) }
        var isGeneratingOtp by remember { mutableStateOf(false) }
        var selectedPairingTab by remember { mutableStateOf(0) } // 0: Mã Số OTP, 1: QR Code

        // Dữ liệu giám sát thời lượng sử dụng hôm nay
        var todayScreenTimeMinutes by remember { mutableStateOf(0) }
        var currentPolicy by remember { mutableStateOf(DevicePolicyLocalEntity()) }

        // Trạng thái đếm ngược 5 phút ghép nối (Pairing TTL - P2-CHILD-04)
        var pairingRemainingSeconds by remember { mutableStateOf(300) }

        // Trạng thái Xin Thêm Giờ (P2-CHILD-02)
        var showRequestTimeDialog by remember { mutableStateOf(false) }
        var requestTimeCooldownUntil by remember { mutableStateOf(0L) }
        var selectedExtraMinutes by remember { mutableStateOf(15) }
        var selectedReason by remember { mutableStateOf("Con chưa làm xong bài tập") }
        var isSendingTimeRequest by remember { mutableStateOf(false) }

        // Trạng thái Tin Nhắn Từ Phụ Huynh (P2-ADMIN-06 receiver)
        var remoteMessageTitle by remember { mutableStateOf<String?>(null) }
        var remoteMessageBody by remember { mutableStateOf<String?>(null) }
        var remoteMessageId by remember { mutableStateOf<String?>(null) }
        var showRemoteMessageDialog by remember { mutableStateOf(false) }

        // Trạng thái kiểm tra & cập nhật phiên bản
        var isCheckingUpdate by remember { mutableStateOf(false) }
        var updateInfo by remember { mutableStateOf<GitHubReleaseUpdater.ReleaseInfo?>(null) }
        var showUpdateDialog by remember { mutableStateOf(false) }
        var downloadProgress by remember { mutableStateOf<Int?>(null) }
        var isDownloading by remember { mutableStateOf(false) }

        // Toast HUD
        var toastMessage by remember { mutableStateOf<String?>(null) }
        var toastSuccess by remember { mutableStateOf(true) }

        val context = LocalContext.current
        val dpm = remember { context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager }
        var isDeviceOwner by remember { mutableStateOf(dpm.isDeviceOwnerApp(context.packageName)) }

        val todayDate = remember {
            SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date())
        }

        // Tự động kiểm tra trạng thái pairing và nạp thống kê sử dụng
        fun refreshAllStatus() {
            isDeviceOwner = dpm.isDeviceOwnerApp(context.packageName)
            val currentId = devicePreferences.deviceId
            deviceId = currentId

            // Nạp thống kê từ Room Database
            lifecycleScope.launch(Dispatchers.IO) {
                val totalMs = usageDao.getTotalScreenTimeMs(todayDate) ?: 0L
                val policy = usageDao.getLocalPolicy() ?: DevicePolicyLocalEntity()
                withContext(Dispatchers.Main) {
                    todayScreenTimeMinutes = (totalMs / (1000 * 60)).toInt()
                    currentPolicy = policy
                }
            }

            // Kiểm tra trạng thái đã ghép nối trên Supabase
            if (!currentId.isNullOrEmpty()) {
                supabaseClient.checkPairingStatus(currentId) { isClaimed ->
                    if (isClaimed) {
                        devicePreferences.completePairing(currentId, deviceName)
                        lifecycleScope.launch(Dispatchers.Main) {
                            isPaired = true
                            otpCode = null
                            qrToken = null
                        }
                    }
                }
            }
        }

        // Đếm lùi thời gian hiệu lực mã ghép nối 5 phút (TTL 300s)
        LaunchedEffect(otpCode) {
            if (otpCode != null) {
                while (true) {
                    val created = devicePreferences.pairingCreatedAt
                    val elapsed = if (created > 0) ((System.currentTimeMillis() - created) / 1000).toInt() else 0
                    val left = (300 - elapsed).coerceAtLeast(0)
                    pairingRemainingSeconds = left
                    if (left <= 0) break
                    delay(1000L)
                }
            }
        }

        LaunchedEffect(Unit) {
            refreshAllStatus()
            val intentMsgId = intent?.getStringExtra("SHOW_REMOTE_MESSAGE_ID")
            if (!intentMsgId.isNullOrEmpty()) {
                remoteMessageId = intentMsgId
                remoteMessageTitle = intent?.getStringExtra("SHOW_REMOTE_MESSAGE_TITLE") ?: "Tin Nhắn Từ Ba Mẹ"
                remoteMessageBody = intent?.getStringExtra("SHOW_REMOTE_MESSAGE_BODY") ?: ""
                showRemoteMessageDialog = true
            }
        }

        // Lắng nghe kết nối Supabase Realtime
        LaunchedEffect(deviceId) {
            val id = deviceId
            if (!id.isNullOrEmpty()) {
                supabaseClient.connectRealtime(
                    deviceId = id,
                    onPanicLockdown = { isLocked ->
                        toastMessage = if (isLocked) "🚨 Nhận lệnh khóa khẩn cấp từ Phụ huynh!" else "✅ Nhận lệnh mở khóa từ Phụ huynh!"
                        toastSuccess = !isLocked
                        ChildNotificationHelper.showPanicLockdownNotification(this@MainActivity, isLocked)
                        if (isLocked) {
                            val admin = ComponentName(this@MainActivity, MdmDeviceAdminReceiver::class.java)
                            if (dpm.isAdminActive(admin)) {
                                try {
                                    dpm.lockNow()
                                } catch (e: Exception) {
                                    Log.e("MainActivity", "lockNow error", e)
                                }
                            }
                        }
                    },
                    onExtraTime = { mins ->
                        toastMessage = "🎁 Ba mẹ đã thưởng thêm $mins phút sử dụng!"
                        toastSuccess = true
                        refreshAllStatus()
                        ChildNotificationHelper.showTimeAdjustedNotification(this@MainActivity, mins, "Ba mẹ thưởng thêm")
                    },
                    onAdjustTime = { delta, reason ->
                        toastMessage = if (delta >= 0) "🎁 Ba mẹ đã thưởng thêm $delta phút sử dụng!" else "⚠️ Ba mẹ đã trừ ${-delta} phút giờ chơi!"
                        toastSuccess = delta >= 0
                        refreshAllStatus()
                        ChildNotificationHelper.showTimeAdjustedNotification(this@MainActivity, delta, reason)
                    },
                    onRemoteMessage = { msgId, title, body, _ ->
                        remoteMessageId = msgId
                        remoteMessageTitle = title
                        remoteMessageBody = body
                        showRemoteMessageDialog = true
                        val currentDevId = (deviceId?.takeIf { it.isNotEmpty() } ?: devicePreferences.deviceId) ?: ""
                        ChildNotificationHelper.showRemoteMessageNotification(
                            this@MainActivity,
                            currentDevId,
                            msgId,
                            title,
                            body
                        )
                    },
                    onTimeRequestResolved = { status, granted ->
                        if (status == "approved" && granted > 0) {
                            toastMessage = "🎉 Ba mẹ đã đồng ý cho con thêm $granted phút!"
                            toastSuccess = true
                        } else {
                            toastMessage = "Ba mẹ chưa đồng ý lúc này. Con hãy nghỉ ngơi nhé!"
                            toastSuccess = false
                        }
                        refreshAllStatus()
                        ChildNotificationHelper.showTimeRequestResolvedNotification(this@MainActivity, status, granted)
                    },
                    onDeviceUnpaired = {
                        lifecycleScope.launch(Dispatchers.Main) {
                            devicePreferences.unpair()
                            isPaired = false
                            otpCode = null
                            qrToken = null
                            toastMessage = "Ba mẹ đã hủy quản lý thiết bị này."
                            toastSuccess = false
                            refreshAllStatus()
                        }
                    },
                    onPairingSuccess = {
                        lifecycleScope.launch(Dispatchers.Main) {
                            devicePreferences.completePairing(id, deviceName)
                            isPaired = true
                            otpCode = null
                            qrToken = null
                            toastMessage = "✨ Ghép nối thành công với Phụ huynh!"
                            toastSuccess = true
                            refreshAllStatus()
                        }
                    }
                )
            }
        }

        // Tự động ẩn Toast HUD sau 3.5 giây
        LaunchedEffect(toastMessage) {
            if (toastMessage != null) {
                delay(3500)
                toastMessage = null
            }
        }

        ChildTheme(darkTheme = isDarkMode) {
            Scaffold(
                containerColor = MaterialTheme.colorScheme.background
            ) { paddingValues ->
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(paddingValues)
                        .navigationBarsPadding()
                ) {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 120.dp)
                    ) {
                        // Header Large Title (Phong cách Apple Music)
                        item {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 12.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = "VFam Child",
                                        style = MaterialTheme.typography.displayLarge.copy(
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 32.sp
                                        ),
                                        color = MaterialTheme.colorScheme.onBackground
                                    )
                                    Spacer(modifier = Modifier.height(2.dp))
                                    Text(
                                        text = "Không Gian An Toàn & Bảo Vệ",
                                        style = MaterialTheme.typography.bodyMedium.copy(
                                            fontSize = 15.sp
                                        ),
                                        color = Gray93
                                    )
                                }

                                Row(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    // Nút làm mới trạng thái
                                    Box(
                                        modifier = Modifier
                                            .size(38.dp)
                                            .clip(CircleShape)
                                            .background(MaterialTheme.colorScheme.surfaceVariant)
                                            .clickable {
                                                refreshAllStatus()
                                                toastMessage = "🔄 Đã làm mới trạng thái thiết bị!"
                                                toastSuccess = true
                                            },
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Refresh,
                                            contentDescription = "Làm mới",
                                            tint = MaterialTheme.colorScheme.onSurface,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }

                                    // Nút chuyển đổi Theme Dark/Light
                                    Box(
                                        modifier = Modifier
                                            .size(38.dp)
                                            .clip(CircleShape)
                                            .background(MaterialTheme.colorScheme.surfaceVariant)
                                            .clickable { isDarkMode = !isDarkMode },
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Icon(
                                            imageVector = if (isDarkMode) Icons.Default.LightMode else Icons.Default.DarkMode,
                                            contentDescription = "Chuyển Theme",
                                            tint = if (isDarkMode) AppleOrange else AppleBlue,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }
                                }
                            }
                        }

                        // --- SECTION 1: TRẠNG THÁI GHÉP NỐI (PAIRING STATUS) ---
                        item {
                            SettingsSectionHeader(title = "TRẠNG THÁI KẾT NỐI VỚI PHỤ HUYNH")

                            if (isPaired) {
                                // GIAO DIỆN KHI ĐÃ GHÉP NỐI THÀNH CÔNG: KHÔNG CÒN NÚT TẠO MÃ OTP/QR!
                                SettingsGroupCard {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(48.dp)
                                                .clip(RoundedCornerShape(12.dp))
                                                .background(AppleEmerald.copy(alpha = 0.15f)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Icon(
                                                imageVector = Icons.Default.VerifiedUser,
                                                contentDescription = null,
                                                tint = AppleEmerald,
                                                modifier = Modifier.size(28.dp)
                                            )
                                        }
                                        Spacer(modifier = Modifier.width(16.dp))
                                        Column(modifier = Modifier.weight(1f)) {
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                Text(
                                                    text = "Đã Ghép Nối An Toàn",
                                                    style = MaterialTheme.typography.headlineLarge.copy(
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 18.sp
                                                    ),
                                                    color = MaterialTheme.colorScheme.onSurface
                                                )
                                                Spacer(modifier = Modifier.width(8.dp))
                                                StatusBadge(text = "ĐANG BẢO VỆ", isSuccess = true)
                                            }
                                            Spacer(modifier = Modifier.height(4.dp))
                                            Text(
                                                text = "Thiết bị này đã được liên kết với tài khoản Phụ huynh và nhận bảo vệ 24/7.",
                                                style = MaterialTheme.typography.bodyMedium.copy(
                                                    fontSize = 13.sp
                                                ),
                                                color = Gray93
                                            )
                                        }
                                    }

                                    HorizontalDivider(
                                        modifier = Modifier.padding(vertical = 14.dp),
                                        color = GrayBorder,
                                        thickness = 0.5.dp
                                    )

                                    // Thống kê thời gian sử dụng trong ngày
                                    val limitMins = currentPolicy.dailyLimitMinutes
                                    val progress = if (limitMins > 0) (todayScreenTimeMinutes.toFloat() / limitMins).coerceIn(0f, 1f) else 0f

                                    Column(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                                            .padding(14.dp)
                                    ) {
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = "Thời gian dùng hôm nay",
                                                style = MaterialTheme.typography.bodyMedium.copy(
                                                    fontWeight = FontWeight.Medium,
                                                    fontSize = 14.sp
                                                ),
                                                color = MaterialTheme.colorScheme.onSurface
                                            )
                                            Text(
                                                text = "${todayScreenTimeMinutes}m / ${limitMins}m",
                                                style = MaterialTheme.typography.bodyLarge.copy(
                                                    fontWeight = FontWeight.Bold,
                                                    fontSize = 15.sp
                                                ),
                                                color = if (progress >= 1f) AppleRed else AppleEmerald
                                            )
                                        }

                                        Spacer(modifier = Modifier.height(10.dp))

                                        LinearProgressIndicator(
                                            progress = { progress },
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .height(8.dp)
                                                .clip(RoundedCornerShape(4.dp)),
                                            color = if (progress >= 1f) AppleRed else AppleEmerald,
                                            trackColor = MaterialTheme.colorScheme.surface
                                        )

                                        Spacer(modifier = Modifier.height(8.dp))

                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween
                                        ) {
                                            Text(
                                                text = "Giờ đi ngủ: ${currentPolicy.bedtimeStart} - ${currentPolicy.bedtimeEnd}",
                                                style = MaterialTheme.typography.labelSmall.copy(fontSize = 12.sp),
                                                color = Gray93
                                            )
                                            Text(
                                                text = if (currentPolicy.isEmergencyLockdown) "🚨 Đang khóa" else "Khả dụng",
                                                style = MaterialTheme.typography.labelSmall.copy(
                                                    fontWeight = FontWeight.SemiBold,
                                                    fontSize = 12.sp
                                                ),
                                                color = if (currentPolicy.isEmergencyLockdown) AppleRed else AppleEmerald
                                            )
                                        }
                                    }

                                    // Cảnh báo thời gian còn lại 5 phút (P2-CHILD-03)
                                    val remainingMins = (limitMins - todayScreenTimeMinutes).coerceAtLeast(0)
                                    if (remainingMins in 1..5 && !currentPolicy.isEmergencyLockdown) {
                                        Spacer(modifier = Modifier.height(10.dp))
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(10.dp))
                                                .background(AppleOrange.copy(alpha = 0.16f))
                                                .border(1.dp, AppleOrange.copy(alpha = 0.4f), RoundedCornerShape(10.dp))
                                                .padding(horizontal = 12.dp, vertical = 8.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Icon(
                                                imageVector = Icons.Default.Warning,
                                                contentDescription = null,
                                                tint = AppleOrange,
                                                modifier = Modifier.size(20.dp)
                                            )
                                            Spacer(modifier = Modifier.width(10.dp))
                                            Column {
                                                Text(
                                                    text = "⚠️ SẮP HẾT THỜI GIAN (Còn $remainingMins phút)",
                                                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold, fontSize = 12.sp),
                                                    color = AppleOrange
                                                )
                                                Text(
                                                    text = "Thiết bị sẽ tự động khóa. Hãy lưu bài tập / game và chuẩn bị tắt máy nhé!",
                                                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp),
                                                    color = MaterialTheme.colorScheme.onSurface
                                                )
                                            }
                                        }
                                    }

                                    Spacer(modifier = Modifier.height(10.dp))

                                    // Nút Xin Thêm Giờ Chơi (P2-CHILD-02)
                                    Button(
                                        onClick = { showRequestTimeDialog = true },
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .height(44.dp),
                                        shape = RoundedCornerShape(10.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = AppleEmerald)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Add,
                                            contentDescription = null,
                                            tint = Color.White,
                                            modifier = Modifier.size(16.dp)
                                        )
                                        Spacer(modifier = Modifier.width(6.dp))
                                        Text(
                                            text = "🙋 Xin Ba Mẹ Thêm Giờ Chơi",
                                            style = MaterialTheme.typography.bodyMedium.copy(
                                                fontWeight = FontWeight.Bold,
                                                fontSize = 14.sp
                                            ),
                                            color = Color.White
                                        )
                                    }

                                    Spacer(modifier = Modifier.height(12.dp))

                                    SettingsItemRow(
                                        icon = Icons.Default.PhoneAndroid,
                                        iconBackground = AppleBlue,
                                        title = "Tên thiết bị",
                                        subtitle = deviceName
                                    )

                                    SettingsItemRow(
                                        icon = Icons.Default.Fingerprint,
                                        iconBackground = ApplePurple,
                                        title = "Device ID",
                                        subtitle = deviceId ?: "Chưa xác định"
                                    )

                                    SettingsItemRow(
                                        icon = Icons.Default.WifiTethering,
                                        iconBackground = AppleEmerald,
                                        title = "Kênh điều khiển Realtime",
                                        subtitle = "Supabase WebSocket & FCM High-Priority",
                                        trailing = {
                                            StatusBadge(text = "TRỰC TUYẾN", isSuccess = true)
                                        }
                                    )
                                }
                            } else {
                                // GIAO DIỆN KHI CHƯA GHÉP NỐI: CÓ NÚT TẠO MÃ OTP/QR VÀ HIỂN THỊ
                                SettingsGroupCard {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        verticalAlignment = Alignment.CenterVertically
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .size(44.dp)
                                                .clip(RoundedCornerShape(12.dp))
                                                .background(AppleOrange.copy(alpha = 0.15f)),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Icon(
                                                imageVector = Icons.Default.LinkOff,
                                                contentDescription = null,
                                                tint = AppleOrange,
                                                modifier = Modifier.size(24.dp)
                                            )
                                        }
                                        Spacer(modifier = Modifier.width(14.dp))
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = "Chưa Kết Nối Phụ Huynh",
                                                style = MaterialTheme.typography.headlineLarge.copy(
                                                    fontWeight = FontWeight.Bold,
                                                    fontSize = 17.sp
                                                ),
                                                color = MaterialTheme.colorScheme.onSurface
                                            )
                                            Spacer(modifier = Modifier.height(2.dp))
                                            Text(
                                                text = "Hãy tạo mã kết nối OTP hoặc QR để Phụ huynh quét hoặc nhập trên app Admin.",
                                                style = MaterialTheme.typography.bodyMedium.copy(
                                                    fontSize = 13.sp
                                                ),
                                                color = Gray93
                                            )
                                        }
                                    }

                                    // Nếu đã có cấu hình thiết bị trước đó nhưng chưa đánh dấu claimed
                                    if (!deviceId.isNullOrEmpty()) {
                                        Spacer(modifier = Modifier.height(12.dp))
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(10.dp))
                                                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                                                .padding(horizontal = 12.dp, vertical = 8.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Column(modifier = Modifier.weight(1f)) {
                                                Text(
                                                    text = "Mã thiết bị (Device ID):",
                                                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                                                    color = Gray93
                                                )
                                                Spacer(modifier = Modifier.height(2.dp))
                                                Text(
                                                    text = deviceId!!,
                                                    style = MaterialTheme.typography.bodySmall.copy(
                                                        fontFamily = FontFamily.Monospace,
                                                        fontWeight = FontWeight.Medium,
                                                        fontSize = 11.sp
                                                    ),
                                                    color = MaterialTheme.colorScheme.onSurface,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis
                                                )
                                            }
                                            Spacer(modifier = Modifier.width(8.dp))
                                            Button(
                                                onClick = {
                                                    toastMessage = "Đang kiểm tra ghép nối trên máy chủ..."
                                                    toastSuccess = true
                                                    supabaseClient.checkPairingStatus(deviceId!!) { isClaimed ->
                                                        if (isClaimed) {
                                                            devicePreferences.completePairing(deviceId!!, deviceName)
                                                            lifecycleScope.launch(Dispatchers.Main) {
                                                                isPaired = true
                                                                otpCode = null
                                                                qrToken = null
                                                                toastMessage = "✨ Đã xác nhận ghép nối thành công!"
                                                                toastSuccess = true
                                                            }
                                                        } else {
                                                            lifecycleScope.launch(Dispatchers.Main) {
                                                                toastMessage = "Mã OTP chưa được Phụ huynh nhập."
                                                                toastSuccess = false
                                                            }
                                                        }
                                                    }
                                                },
                                                shape = RoundedCornerShape(8.dp),
                                                colors = ButtonDefaults.buttonColors(
                                                    containerColor = AppleEmerald.copy(alpha = 0.2f)
                                                ),
                                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                                            ) {
                                                Text(
                                                    text = "Kiểm tra",
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 12.sp
                                                    ),
                                                    color = AppleEmerald,
                                                    maxLines = 1
                                                )
                                            }
                                        }
                                    }

                                    Spacer(modifier = Modifier.height(14.dp))

                                    if (otpCode != null) {
                                        // Khối hiển thị mã OTP hoặc QR Code kiểu Apple
                                        Column(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(14.dp))
                                                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                                                .padding(14.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally
                                        ) {
                                            // Tab chuyển đổi: [ Mã Số OTP ] | [ Mã QR Code ]
                                            Row(
                                                modifier = Modifier
                                                    .fillMaxWidth()
                                                    .clip(RoundedCornerShape(10.dp))
                                                    .background(MaterialTheme.colorScheme.surface)
                                                    .padding(3.dp)
                                            ) {
                                                Box(
                                                    modifier = Modifier
                                                        .weight(1f)
                                                        .clip(RoundedCornerShape(8.dp))
                                                        .background(if (selectedPairingTab == 0) AppleEmerald else Color.Transparent)
                                                        .clickable { selectedPairingTab = 0 }
                                                        .padding(vertical = 7.dp),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                                        Icon(
                                                            imageVector = Icons.Default.Pin,
                                                            contentDescription = null,
                                                            tint = if (selectedPairingTab == 0) Color.White else Gray93,
                                                            modifier = Modifier.size(15.dp)
                                                        )
                                                        Spacer(modifier = Modifier.width(6.dp))
                                                        Text(
                                                            text = "Mã Số OTP",
                                                            style = MaterialTheme.typography.bodyMedium.copy(
                                                                fontWeight = if (selectedPairingTab == 0) FontWeight.Bold else FontWeight.Normal,
                                                                fontSize = 13.sp
                                                            ),
                                                            color = if (selectedPairingTab == 0) Color.White else Gray93
                                                        )
                                                    }
                                                }

                                                Box(
                                                    modifier = Modifier
                                                        .weight(1f)
                                                        .clip(RoundedCornerShape(8.dp))
                                                        .background(if (selectedPairingTab == 1) AppleEmerald else Color.Transparent)
                                                        .clickable { selectedPairingTab = 1 }
                                                        .padding(vertical = 7.dp),
                                                    contentAlignment = Alignment.Center
                                                ) {
                                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                                        Icon(
                                                            imageVector = Icons.Default.QrCode,
                                                            contentDescription = null,
                                                            tint = if (selectedPairingTab == 1) Color.White else Gray93,
                                                            modifier = Modifier.size(15.dp)
                                                        )
                                                        Spacer(modifier = Modifier.width(6.dp))
                                                        Text(
                                                            text = "Mã QR Code",
                                                            style = MaterialTheme.typography.bodyMedium.copy(
                                                                fontWeight = if (selectedPairingTab == 1) FontWeight.Bold else FontWeight.Normal,
                                                                fontSize = 13.sp
                                                            ),
                                                            color = if (selectedPairingTab == 1) Color.White else Gray93
                                                        )
                                                    }
                                                }
                                            }

                                            Spacer(modifier = Modifier.height(14.dp))

                                            if (selectedPairingTab == 0) {
                                                // TAB 1: HIỂN THỊ MÃ SỐ OTP 6 Ô VUÔNG CĂN CHỈNH VỪA VẶN
                                                Text(
                                                    text = "MÃ GHÉP NỐI 6 CHỮ SỐ (OTP)",
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontWeight = FontWeight.SemiBold,
                                                        fontSize = 11.sp,
                                                        letterSpacing = 0.8.sp
                                                    ),
                                                    color = AppleEmerald
                                                )

                                                Spacer(modifier = Modifier.height(10.dp))

                                                // 6 ô số được căn giữa cân đối, kích thước 36dp x 36dp
                                                Row(
                                                    modifier = Modifier.fillMaxWidth(),
                                                    horizontalArrangement = Arrangement.Center,
                                                    verticalAlignment = Alignment.CenterVertically
                                                ) {
                                                    otpCode!!.forEachIndexed { index, char ->
                                                        Box(
                                                            modifier = Modifier
                                                                .size(36.dp)
                                                                .clip(RoundedCornerShape(8.dp))
                                                                .background(MaterialTheme.colorScheme.surface)
                                                                .border(1.dp, AppleEmerald.copy(alpha = 0.6f), RoundedCornerShape(8.dp)),
                                                            contentAlignment = Alignment.Center
                                                        ) {
                                                            Text(
                                                                text = char.toString(),
                                                                style = MaterialTheme.typography.headlineLarge.copy(
                                                                    fontWeight = FontWeight.Bold,
                                                                    fontSize = 19.sp
                                                                ),
                                                                color = MaterialTheme.colorScheme.onSurface
                                                            )
                                                        }
                                                        if (index < otpCode!!.length - 1) {
                                                            Spacer(modifier = Modifier.width(6.dp))
                                                        }
                                                    }
                                                }

                                                Spacer(modifier = Modifier.height(12.dp))

                                                Text(
                                                    text = "👉 Mở ứng dụng VFam Admin và nhập mã 6 số này để kết nối.",
                                                    style = MaterialTheme.typography.bodyMedium.copy(
                                                        fontSize = 13.sp,
                                                        textAlign = TextAlign.Center
                                                    ),
                                                    color = Gray93
                                                )
                                            } else {
                                                // TAB 2: HIỂN THỊ MÃ QR CODE
                                                Text(
                                                    text = "QUÉT MÃ QR TỪ MÁY PHỤ HUYNH",
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontWeight = FontWeight.SemiBold,
                                                        fontSize = 11.sp,
                                                        letterSpacing = 0.8.sp
                                                    ),
                                                    color = AppleEmerald
                                                )

                                                Spacer(modifier = Modifier.height(10.dp))

                                                val qrData = "vfam://pair?otp=$otpCode&device=$deviceId&token=${qrToken ?: ""}"
                                                QrCodeCard(
                                                    content = qrData,
                                                    size = 170.dp
                                                )

                                                Spacer(modifier = Modifier.height(10.dp))

                                                Text(
                                                    text = "Mã OTP: [ $otpCode ]",
                                                    style = MaterialTheme.typography.bodyLarge.copy(
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 16.sp
                                                    ),
                                                    color = AppleEmerald
                                                )

                                                Spacer(modifier = Modifier.height(4.dp))

                                                Text(
                                                    text = "Mở app VFam Admin và quét mã QR trên để liên kết tức thì.",
                                                    style = MaterialTheme.typography.bodyMedium.copy(
                                                        fontSize = 12.sp,
                                                        textAlign = TextAlign.Center
                                                    ),
                                                    color = Gray93
                                                )
                                            }

                                            Spacer(modifier = Modifier.height(12.dp))

                                            // Đồng hồ đếm ngược hiệu lực mã ghép nối (5 phút TTL - P2-CHILD-04)
                                            val isExpired = pairingRemainingSeconds <= 0
                                            val timerColor = when {
                                                isExpired -> AppleRed
                                                pairingRemainingSeconds <= 60 -> AppleOrange
                                                else -> AppleEmerald
                                            }
                                            val mins = pairingRemainingSeconds / 60
                                            val secs = pairingRemainingSeconds % 60

                                            Row(
                                                modifier = Modifier
                                                    .clip(RoundedCornerShape(8.dp))
                                                    .background(timerColor.copy(alpha = 0.15f))
                                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Icon(
                                                    imageVector = if (isExpired) Icons.Default.Warning else Icons.Default.Timer,
                                                    contentDescription = null,
                                                    tint = timerColor,
                                                    modifier = Modifier.size(15.dp)
                                                )
                                                Spacer(modifier = Modifier.width(6.dp))
                                                Text(
                                                    text = if (isExpired) "⚠️ Mã đã hết hạn hiệu lực (5 phút)" else "Hiệu lực trong: %02d:%02d".format(mins, secs),
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 12.sp
                                                    ),
                                                    color = timerColor
                                                )
                                            }

                                            Spacer(modifier = Modifier.height(8.dp))

                                            if (!isExpired) {
                                                Row(
                                                    verticalAlignment = Alignment.CenterVertically
                                                ) {
                                                    CircularProgressIndicator(
                                                        modifier = Modifier.size(14.dp),
                                                        strokeWidth = 2.dp,
                                                        color = AppleEmerald
                                                    )
                                                    Spacer(modifier = Modifier.width(8.dp))
                                                    Text(
                                                        text = "Đang chờ Phụ huynh quét / nhập mã...",
                                                        style = MaterialTheme.typography.labelSmall.copy(
                                                            fontSize = 12.sp
                                                        ),
                                                        color = AppleEmerald
                                                    )
                                                }
                                            }
                                        }

                                        Spacer(modifier = Modifier.height(14.dp))
                                    }

                                    // Nút tạo mã kết nối
                                    Button(
                                        onClick = {
                                            isGeneratingOtp = true
                                            val model = Build.MODEL
                                            val osVersion = "Android ${Build.VERSION.RELEASE}"
                                            supabaseClient.createPairingSession(
                                                deviceName = deviceName,
                                                model = model,
                                                osVersion = osVersion,
                                                onSuccess = { result ->
                                                    devicePreferences.savePairing(result.deviceId, result.otpCode, deviceName, result.qrToken, System.currentTimeMillis())
                                                    val fcm = devicePreferences.fcmToken
                                                    if (!fcm.isNullOrEmpty()) {
                                                        supabaseClient.updateFcmToken(result.deviceId, fcm)
                                                    }
                                                    lifecycleScope.launch(Dispatchers.Main) {
                                                        deviceId = result.deviceId
                                                        otpCode = result.otpCode
                                                        qrToken = result.qrToken
                                                        pairingRemainingSeconds = 300
                                                        isGeneratingOtp = false
                                                        toastMessage = "✨ Đã tạo mã ghép nối mới thành công!"
                                                        toastSuccess = true
                                                    }
                                                },
                                                onError = { err ->
                                                    lifecycleScope.launch(Dispatchers.Main) {
                                                        isGeneratingOtp = false
                                                        toastMessage = "❌ Lỗi tạo mã: $err"
                                                        toastSuccess = false
                                                    }
                                                }
                                            )
                                        },
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .defaultMinSize(minHeight = 52.dp),
                                        shape = RoundedCornerShape(14.dp),
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = AppleEmerald
                                        ),
                                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                                        enabled = !isGeneratingOtp
                                    ) {
                                        if (isGeneratingOtp) {
                                            CircularProgressIndicator(
                                                modifier = Modifier.size(20.dp),
                                                color = Color.White,
                                                strokeWidth = 2.dp
                                            )
                                            Spacer(modifier = Modifier.width(10.dp))
                                            Text(
                                                text = "Đang kết nối Supabase...",
                                                style = MaterialTheme.typography.bodyLarge.copy(
                                                    fontWeight = FontWeight.SemiBold,
                                                    fontSize = 15.sp
                                                ),
                                                color = Color.White,
                                                maxLines = 1
                                            )
                                        } else {
                                            Icon(
                                                imageVector = Icons.Default.QrCode,
                                                contentDescription = null,
                                                tint = Color.White,
                                                modifier = Modifier.size(20.dp)
                                            )
                                            Spacer(modifier = Modifier.width(8.dp))
                                            Text(
                                                text = if (otpCode != null) (if (pairingRemainingSeconds <= 0) "Tạo Lại Mã Mới (Hết Hạn)" else "Tạo Lại Mã OTP / QR Khác") else "Tạo Mã Ghép Nối (OTP / QR)",
                                                style = MaterialTheme.typography.bodyLarge.copy(
                                                    fontWeight = FontWeight.SemiBold,
                                                    fontSize = 15.sp
                                                ),
                                                color = Color.White,
                                                maxLines = 1
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        // --- SECTION 2: BẢO MẬT & ĐẶC QUYỀN HỆ ĐIỀU HÀNH ---
                        item {
                            SettingsSectionHeader(title = "BẢO MẬT & ĐẶC QUYỀN HỆ THỐNG")
                            SettingsGroupCard {
                                SettingsItemRow(
                                    icon = if (isDeviceOwner) Icons.Default.Security else Icons.Default.Warning,
                                    iconBackground = if (isDeviceOwner) AppleEmerald else AppleOrange,
                                    title = "Device Owner MDM",
                                    subtitle = if (isDeviceOwner) {
                                        "Đã kích hoạt. Ứng dụng được bảo vệ chống gỡ cài đặt, chặn Safe Boot và vô hiệu hóa reset máy."
                                    } else {
                                        "Chưa kích hoạt. Cần cấp quyền Device Owner qua lệnh ADB để bảo đảm không bị bypass."
                                    },
                                    trailing = {
                                        StatusBadge(
                                            text = if (isDeviceOwner) "ACTIVE 🛡️" else "CHƯA CẤP ⚠️",
                                            isSuccess = isDeviceOwner
                                        )
                                    }
                                )

                                // Hiển thị lệnh ADB kèm nút sao chép nếu chưa cấp Device Owner
                                if (!isDeviceOwner) {
                                    Spacer(modifier = Modifier.height(10.dp))
                                    val adbCommand = "adb shell dpm set-device-owner ${context.packageName}/${MdmDeviceAdminReceiver::class.java.canonicalName}"
                                    Surface(
                                        shape = RoundedCornerShape(10.dp),
                                        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f),
                                        border = androidx.compose.foundation.BorderStroke(0.5.dp, GrayBorder),
                                        modifier = Modifier.fillMaxWidth()
                                    ) {
                                        Column(modifier = Modifier.padding(12.dp)) {
                                            Row(
                                                modifier = Modifier.fillMaxWidth(),
                                                horizontalArrangement = Arrangement.SpaceBetween,
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                Text(
                                                    text = "LỆNH KÍCH HOẠT ADB:",
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontWeight = FontWeight.Bold,
                                                        fontSize = 11.sp,
                                                        letterSpacing = 0.5.sp
                                                    ),
                                                    color = AppleOrange
                                                )
                                                Text(
                                                    text = "Sao chép lệnh",
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontWeight = FontWeight.SemiBold,
                                                        fontSize = 12.sp
                                                    ),
                                                    color = AppleBlue,
                                                    modifier = Modifier.clickable {
                                                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                                        clipboard.setPrimaryClip(ClipData.newPlainText("ADB Command", adbCommand))
                                                        toastMessage = "📋 Đã sao chép lệnh ADB vào bộ nhớ tạm!"
                                                        toastSuccess = true
                                                    }
                                                )
                                            }
                                            Spacer(modifier = Modifier.height(6.dp))
                                            Text(
                                                text = adbCommand,
                                                style = MaterialTheme.typography.bodySmall.copy(
                                                    fontFamily = FontFamily.Monospace,
                                                    fontSize = 11.sp,
                                                    lineHeight = 16.sp
                                                ),
                                                color = MaterialTheme.colorScheme.onSurface
                                            )
                                        }
                                    }
                                }

                                HorizontalDivider(
                                    modifier = Modifier.padding(vertical = 12.dp),
                                    color = GrayBorder,
                                    thickness = 0.5.dp
                                )

                                SettingsItemRow(
                                    icon = Icons.Default.Timer,
                                    iconBackground = AppleBlue,
                                    title = "Dịch Vụ Giám Sát Ngầm",
                                    subtitle = "Foreground Service theo dõi thời lượng sử dụng & tự động áp đặt quota hàng ngày.",
                                    trailing = {
                                        StatusBadge(text = "ĐANG CHẠY", isSuccess = true)
                                    }
                                )
                            }
                        }

                        // --- SECTION 3: PHIÊN BẢN & CẬP NHẬT TỰ ĐỘNG (AUTO-UPDATE) ---
                        item {
                            SettingsSectionHeader(title = "PHIÊN BẢN & CẬP NHẬT")
                            SettingsGroupCard {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Box(
                                        modifier = Modifier
                                            .size(44.dp)
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(AppleEmerald),
                                        contentAlignment = Alignment.Center
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.Shield,
                                            contentDescription = null,
                                            tint = Color.White,
                                            modifier = Modifier.size(26.dp)
                                        )
                                    }
                                    Spacer(modifier = Modifier.width(14.dp))
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            text = "VFam Child Agent",
                                            style = MaterialTheme.typography.bodyLarge.copy(
                                                fontWeight = FontWeight.Bold,
                                                fontSize = 16.sp
                                            ),
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                        Spacer(modifier = Modifier.height(2.dp))
                                        Text(
                                            text = "Phiên bản $currentAppVersion (Build 6) • GitHub Release",
                                            style = MaterialTheme.typography.bodyMedium.copy(
                                                fontSize = 13.sp
                                            ),
                                            color = Gray93
                                        )
                                    }
                                }

                                Spacer(modifier = Modifier.height(16.dp))

                                // Nút Kiểm tra Cập nhật
                                Button(
                                    onClick = {
                                        isCheckingUpdate = true
                                        lifecycleScope.launch {
                                            val info = releaseUpdater.checkLatestRelease(currentVersion = currentAppVersion)
                                            isCheckingUpdate = false
                                            if (info != null && info.isNewer) {
                                                updateInfo = info
                                                showUpdateDialog = true
                                            } else {
                                                toastMessage = "🎉 Bạn đang ở phiên bản mới nhất ($currentAppVersion)!"
                                                toastSuccess = true
                                            }
                                        }
                                    },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .defaultMinSize(minHeight = 48.dp),
                                    shape = RoundedCornerShape(14.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                                    ),
                                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                                    enabled = !isCheckingUpdate
                                ) {
                                    if (isCheckingUpdate) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(18.dp),
                                            color = AppleEmerald,
                                            strokeWidth = 2.dp
                                        )
                                        Spacer(modifier = Modifier.width(10.dp))
                                        Text(
                                            text = "Đang kiểm tra từ GitHub...",
                                            style = MaterialTheme.typography.bodyMedium.copy(
                                                fontWeight = FontWeight.SemiBold
                                            ),
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                    } else {
                                        Icon(
                                            imageVector = Icons.Default.CloudDownload,
                                            contentDescription = null,
                                            tint = AppleEmerald,
                                            modifier = Modifier.size(18.dp)
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text(
                                            text = "Kiểm Tra Cập Nhật",
                                            style = MaterialTheme.typography.bodyMedium.copy(
                                                fontWeight = FontWeight.SemiBold,
                                                fontSize = 15.sp
                                            ),
                                            color = MaterialTheme.colorScheme.onSurface
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Floating Liquid Glass Toast HUD
                    LiquidGlassToastHud(
                        visible = toastMessage != null,
                        message = toastMessage ?: "",
                        isSuccess = toastSuccess
                    )
                }

                // Dialog Thông Báo Bản Cập Nhật Mới
                if (showUpdateDialog && updateInfo != null) {
                    val info = updateInfo!!
                    Dialog(onDismissRequest = { if (!isDownloading) showUpdateDialog = false }) {
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = MaterialTheme.colorScheme.surface,
                            border = androidx.compose.foundation.BorderStroke(1.dp, GrayBorder),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(20.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(52.dp)
                                        .clip(CircleShape)
                                        .background(AppleEmerald.copy(alpha = 0.15f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.SystemUpdate,
                                        contentDescription = null,
                                        tint = AppleEmerald,
                                        modifier = Modifier.size(28.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.height(14.dp))

                                Text(
                                    text = "Đã Có Bản Cập Nhật Mới!",
                                    style = MaterialTheme.typography.headlineLarge.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 19.sp
                                    ),
                                    color = MaterialTheme.colorScheme.onSurface
                                )

                                Spacer(modifier = Modifier.height(4.dp))

                                Text(
                                    text = "Phiên bản: ${info.tagName}",
                                    style = MaterialTheme.typography.bodyMedium.copy(
                                        fontWeight = FontWeight.SemiBold,
                                        fontSize = 14.sp
                                    ),
                                    color = AppleEmerald
                                )

                                if (info.releaseNotes.isNotEmpty()) {
                                    Spacer(modifier = Modifier.height(12.dp))
                                    Text(
                                        text = info.releaseNotes,
                                        style = MaterialTheme.typography.bodyMedium.copy(
                                            fontSize = 13.sp
                                        ),
                                        color = Gray93,
                                        maxLines = 6
                                    )
                                }

                                Spacer(modifier = Modifier.height(20.dp))

                                if (isDownloading) {
                                    Column(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalAlignment = Alignment.CenterHorizontally
                                    ) {
                                        LinearProgressIndicator(
                                            progress = { (downloadProgress ?: 0) / 100f },
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .height(8.dp)
                                                .clip(RoundedCornerShape(4.dp)),
                                            color = AppleEmerald,
                                        )
                                        Spacer(modifier = Modifier.height(8.dp))
                                        Text(
                                            text = "Đang tải xuống: ${downloadProgress ?: 0}%",
                                            style = MaterialTheme.typography.labelSmall.copy(
                                                fontSize = 12.sp
                                            ),
                                            color = Gray93
                                        )
                                    }
                                } else {
                                    Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                                    ) {
                                        OutlinedButton(
                                            onClick = { showUpdateDialog = false },
                                            modifier = Modifier
                                                .weight(1f)
                                                .height(46.dp),
                                            shape = RoundedCornerShape(12.dp)
                                        ) {
                                            Text(text = "Để Sau", color = Gray93)
                                        }

                                        Button(
                                            onClick = {
                                                isDownloading = true
                                                downloadProgress = 0
                                                lifecycleScope.launch {
                                                    val apkFile = File(context.cacheDir, "vfam-child-${info.tagName}.apk")
                                                    val success = releaseUpdater.downloadApk(
                                                        downloadUrl = info.apkDownloadUrl,
                                                        destinationFile = apkFile,
                                                        onProgress = { p -> downloadProgress = p }
                                                    )
                                                    isDownloading = false
                                                    showUpdateDialog = false
                                                    if (success && apkFile.exists()) {
                                                        toastMessage = "🚀 Đang tiến hành cài đặt bản cập nhật..."
                                                        toastSuccess = true
                                                        releaseUpdater.installApk(apkFile)
                                                    } else {
                                                        toastMessage = "❌ Tải bản cập nhật thất bại."
                                                        toastSuccess = false
                                                    }
                                                }
                                            },
                                            modifier = Modifier
                                                .weight(1.5f)
                                                .height(46.dp),
                                            shape = RoundedCornerShape(12.dp),
                                            colors = ButtonDefaults.buttonColors(
                                                containerColor = AppleEmerald
                                            )
                                        ) {
                                            Text(
                                                text = "Cập Nhật Ngay",
                                                style = MaterialTheme.typography.bodyMedium.copy(
                                                    fontWeight = FontWeight.SemiBold
                                                ),
                                                color = Color.White
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Dialog Xin Thêm Giờ Chơi (P2-CHILD-02)
                if (showRequestTimeDialog) {
                    val isCoolingDown = System.currentTimeMillis() < requestTimeCooldownUntil
                    val cooldownLeftSecs = ((requestTimeCooldownUntil - System.currentTimeMillis()) / 1000).coerceAtLeast(0)

                    Dialog(onDismissRequest = { if (!isSendingTimeRequest) showRequestTimeDialog = false }) {
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = MaterialTheme.colorScheme.surface,
                            border = androidx.compose.foundation.BorderStroke(1.dp, GrayBorder),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(20.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(50.dp)
                                        .clip(CircleShape)
                                        .background(AppleEmerald.copy(alpha = 0.15f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Add,
                                        contentDescription = null,
                                        tint = AppleEmerald,
                                        modifier = Modifier.size(26.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.height(12.dp))

                                Text(
                                    text = "Xin Thêm Giờ Chơi",
                                    style = MaterialTheme.typography.headlineLarge.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 18.sp
                                    ),
                                    color = MaterialTheme.colorScheme.onSurface
                                )

                                Spacer(modifier = Modifier.height(4.dp))

                                Text(
                                    text = "Yêu cầu sẽ được gửi tức thì đến ứng dụng của Ba Mẹ.",
                                    style = MaterialTheme.typography.bodySmall.copy(
                                        fontSize = 12.sp,
                                        textAlign = TextAlign.Center
                                    ),
                                    color = Gray93
                                )

                                Spacer(modifier = Modifier.height(14.dp))

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                                ) {
                                    listOf(15, 30, 45).forEach { mins ->
                                        val isSelected = selectedExtraMinutes == mins
                                        Box(
                                            modifier = Modifier
                                                .weight(1f)
                                                .clip(RoundedCornerShape(10.dp))
                                                .background(if (isSelected) AppleEmerald else MaterialTheme.colorScheme.surfaceVariant)
                                                .clickable { selectedExtraMinutes = mins }
                                                .padding(vertical = 10.dp),
                                            contentAlignment = Alignment.Center
                                        ) {
                                            Text(
                                                text = "+$mins phút",
                                                style = MaterialTheme.typography.bodyMedium.copy(
                                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                                                    fontSize = 13.sp
                                                ),
                                                color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface
                                            )
                                        }
                                    }
                                }

                                Spacer(modifier = Modifier.height(12.dp))

                                Column(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    listOf(
                                        "📚 Con chưa làm xong bài tập",
                                        "🎮 Con chơi nốt trận này với bạn",
                                        "🎥 Con xem nốt video học tập",
                                        "💬 Con cần trao đổi bài với bạn"
                                    ).forEach { reason ->
                                        val isSelected = selectedReason == reason
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(8.dp))
                                                .background(if (isSelected) AppleEmerald.copy(alpha = 0.15f) else Color.Transparent)
                                                .clickable { selectedReason = reason }
                                                .padding(horizontal = 10.dp, vertical = 8.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = reason,
                                                style = MaterialTheme.typography.bodySmall.copy(
                                                    fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                                    fontSize = 12.5.sp
                                                ),
                                                color = if (isSelected) AppleEmerald else MaterialTheme.colorScheme.onSurface
                                            )
                                        }
                                    }
                                }

                                Spacer(modifier = Modifier.height(16.dp))

                                if (isCoolingDown) {
                                    Text(
                                        text = "⏳ Vui lòng chờ ${cooldownLeftSecs}s trước khi gửi tiếp",
                                        style = MaterialTheme.typography.labelSmall.copy(color = AppleOrange),
                                        modifier = Modifier.padding(bottom = 8.dp)
                                    )
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    OutlinedButton(
                                        onClick = { showRequestTimeDialog = false },
                                        modifier = Modifier.weight(1f).height(44.dp),
                                        shape = RoundedCornerShape(10.dp)
                                    ) {
                                        Text(text = "Đóng", color = Gray93)
                                    }

                                    Button(
                                        onClick = {
                                            val currentId = deviceId
                                            if (!currentId.isNullOrEmpty() && !isCoolingDown) {
                                                isSendingTimeRequest = true
                                                supabaseClient.sendTimeRequest(
                                                    deviceId = currentId,
                                                    minutes = selectedExtraMinutes,
                                                    reason = selectedReason
                                                ) {
                                                    isSendingTimeRequest = false
                                                    showRequestTimeDialog = false
                                                    requestTimeCooldownUntil = System.currentTimeMillis() + 180000L
                                                    toastMessage = "✨ Đã gửi yêu cầu xin thêm ${selectedExtraMinutes}p tới Ba Mẹ!"
                                                    toastSuccess = true
                                                }
                                            }
                                        },
                                        modifier = Modifier.weight(1.3f).height(44.dp),
                                        shape = RoundedCornerShape(10.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = AppleEmerald),
                                        enabled = !isSendingTimeRequest && !isCoolingDown && !deviceId.isNullOrEmpty()
                                    ) {
                                        if (isSendingTimeRequest) {
                                            CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                                        } else {
                                            Text(text = "Gửi Yêu Cầu", fontWeight = FontWeight.Bold, color = Color.White)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Dialog Nhận Tin Nhắn Nhắc Nhở Từ Phụ Huynh (P2-ADMIN-06 receiver)
                if (showRemoteMessageDialog && remoteMessageTitle != null) {
                    Dialog(onDismissRequest = {}) {
                        Surface(
                            shape = RoundedCornerShape(22.dp),
                            color = MaterialTheme.colorScheme.surface,
                            border = androidx.compose.foundation.BorderStroke(1.5.dp, AppleEmerald),
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp)
                        ) {
                            Column(
                                modifier = Modifier.padding(22.dp),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(56.dp)
                                        .clip(CircleShape)
                                        .background(AppleEmerald.copy(alpha = 0.2f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Notifications,
                                        contentDescription = null,
                                        tint = AppleEmerald,
                                        modifier = Modifier.size(30.dp)
                                    )
                                }

                                Spacer(modifier = Modifier.height(14.dp))

                                Text(
                                    text = remoteMessageTitle ?: "Tin Nhắn Từ Ba Mẹ",
                                    style = MaterialTheme.typography.headlineLarge.copy(
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 18.sp,
                                        textAlign = TextAlign.Center
                                    ),
                                    color = MaterialTheme.colorScheme.onSurface
                                )

                                Spacer(modifier = Modifier.height(10.dp))

                                Text(
                                    text = remoteMessageBody ?: "",
                                    style = MaterialTheme.typography.bodyLarge.copy(
                                        fontSize = 15.sp,
                                        textAlign = TextAlign.Center,
                                        lineHeight = 22.sp
                                    ),
                                    color = MaterialTheme.colorScheme.onSurface
                                )

                                Spacer(modifier = Modifier.height(20.dp))

                                Button(
                                    onClick = {
                                val currentId: String = (deviceId?.takeIf { it.isNotEmpty() } ?: devicePreferences.deviceId) ?: ""
                                val msgId: String = (remoteMessageId?.takeIf { it.isNotEmpty() } ?: System.currentTimeMillis().toString())
                                if (currentId.isNotEmpty()) {
                                    supabaseClient.sendAckMessage(currentId, msgId)
                                }
                                val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                                notifManager.cancel(msgId.hashCode())
                                showRemoteMessageDialog = false
                                toastMessage = "✅ Đã phản hồi cho Ba Mẹ: Dạ con nghe rồi!"
                                toastSuccess = true
                                    },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .height(48.dp),
                                    shape = RoundedCornerShape(12.dp),
                                    colors = ButtonDefaults.buttonColors(containerColor = AppleEmerald)
                                ) {
                                    Text(
                                        text = "Dạ Con Nghe Rồi! 👍",
                                        style = MaterialTheme.typography.bodyMedium.copy(
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 15.sp
                                        ),
                                        color = Color.White
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // UsageTrackingForegroundService duy trì kết nối nền 24/7
    }
}
