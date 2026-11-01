package com.mdm.parentalcontrol.child.ui

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.Toast
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.lifecycleScope
import com.google.firebase.messaging.FirebaseMessaging
import com.mdm.parentalcontrol.child.data.local.DevicePreferences
import com.mdm.parentalcontrol.child.network.MdmSupabaseClient
import com.mdm.parentalcontrol.child.receiver.MdmDeviceAdminReceiver
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

        // 2. Kiểm tra trạng thái ghép nối ban đầu nếu đã có deviceId
        val savedId = devicePreferences.deviceId
        if (!savedId.isNullOrEmpty() && !devicePreferences.isPaired) {
            supabaseClient.checkPairingStatus(savedId) { isClaimed ->
                if (isClaimed) {
                    devicePreferences.completePairing(savedId, devicePreferences.deviceName)
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
        var otpExpiresAt by remember { mutableStateOf<String?>(null) }
        var isGeneratingOtp by remember { mutableStateOf(false) }

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
        val isDeviceOwner = remember { dpm.isDeviceOwnerApp(context.packageName) }

        // Lắng nghe kết nối Supabase Realtime
        LaunchedEffect(deviceId) {
            val id = deviceId
            if (!id.isNullOrEmpty()) {
                supabaseClient.connectRealtime(
                    deviceId = id,
                    onPanicLockdown = { isLocked ->
                        toastMessage = if (isLocked) "🚨 Nhận lệnh khóa khẩn cấp từ Phụ huynh!" else "✅ Nhận lệnh mở khóa từ Phụ huynh!"
                        toastSuccess = !isLocked
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
                    },
                    onPairingSuccess = {
                        lifecycleScope.launch(Dispatchers.Main) {
                            devicePreferences.completePairing(id, deviceName)
                            isPaired = true
                            otpCode = null
                            toastMessage = "✨ Ghép nối thành công với Phụ huynh!"
                            toastSuccess = true
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
                ) {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(bottom = 80.dp)
                    ) {
                        // Header Large Title (Phong cách Apple Music)
                        item {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 20.dp, end = 20.dp, top = 24.dp, bottom = 12.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Column {
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

                        // --- SECTION 1: TRẠNG THÁI GHÉP NỐI (PAIRING STATUS) ---
                        item {
                            SettingsSectionHeader(title = "TRẠNG THÁI KẾT NỐI VỚI PHỤ HUYNH")

                            if (isPaired) {
                                // GIAO DIỆN KHI ĐÃ GHÉP NỐI THÀNH CÔNG: KHÔNG CÒN NÚT TẠO MÃ OTP!
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

                                    SettingsItemRow(
                                        icon = Icons.Default.PhoneAndroid,
                                        iconBackground = AppleBlue,
                                        title = "Tên máy",
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
                                // GIAO DIỆN KHI CHƯA GHÉP NỐI: CÓ NÚT TẠO MÃ OTP VÀ HIỂN THỊ MÃ
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
                                                text = "Hãy tạo mã kết nối OTP để Phụ huynh quét hoặc nhập trên app Admin.",
                                                style = MaterialTheme.typography.bodyMedium.copy(
                                                    fontSize = 13.sp
                                                ),
                                                color = Gray93
                                            )
                                        }
                                    }

                                    Spacer(modifier = Modifier.height(16.dp))

                                    if (otpCode != null) {
                                        // Khối hiển thị mã OTP nổi bật kiểu Apple
                                        Column(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .clip(RoundedCornerShape(14.dp))
                                                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                                                .padding(16.dp),
                                            horizontalAlignment = Alignment.CenterHorizontally
                                        ) {
                                            Text(
                                                text = "MÃ GHÉP NỐI CỦA THIẾT BỊ (OTP)",
                                                style = MaterialTheme.typography.labelSmall.copy(
                                                    fontWeight = FontWeight.SemiBold,
                                                    fontSize = 12.sp,
                                                    letterSpacing = 1.sp
                                                ),
                                                color = AppleEmerald
                                            )

                                            Spacer(modifier = Modifier.height(10.dp))

                                            // Hiển thị từng ký tự OTP trong các ô vuông cách điệu
                                            Row(
                                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                                verticalAlignment = Alignment.CenterVertically
                                            ) {
                                                otpCode!!.forEach { char ->
                                                    Box(
                                                        modifier = Modifier
                                                            .size(42.dp)
                                                            .clip(RoundedCornerShape(10.dp))
                                                            .background(MaterialTheme.colorScheme.surface)
                                                            .border(1.dp, AppleEmerald.copy(alpha = 0.5f), RoundedCornerShape(10.dp)),
                                                        contentAlignment = Alignment.Center
                                                    ) {
                                                        Text(
                                                            text = char.toString(),
                                                            style = MaterialTheme.typography.headlineLarge.copy(
                                                                fontWeight = FontWeight.Bold,
                                                                fontSize = 22.sp
                                                            ),
                                                            color = MaterialTheme.colorScheme.onSurface
                                                        )
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

                                            Spacer(modifier = Modifier.height(10.dp))

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
                                                    text = "Đang chờ Phụ huynh xác nhận...",
                                                    style = MaterialTheme.typography.labelSmall.copy(
                                                        fontSize = 12.sp
                                                    ),
                                                    color = AppleEmerald
                                                )
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
                                                    devicePreferences.savePairing(result.deviceId, result.otpCode, deviceName)
                                                    val fcm = devicePreferences.fcmToken
                                                    if (!fcm.isNullOrEmpty()) {
                                                        supabaseClient.updateFcmToken(result.deviceId, fcm)
                                                    }
                                                    lifecycleScope.launch(Dispatchers.Main) {
                                                        deviceId = result.deviceId
                                                        otpCode = result.otpCode
                                                        otpExpiresAt = result.expiresAt
                                                        isGeneratingOtp = false
                                                        toastMessage = "✨ Đã tạo mã OTP mới thành công!"
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
                                            .height(50.dp),
                                        shape = RoundedCornerShape(14.dp),
                                        colors = ButtonDefaults.buttonColors(
                                            containerColor = AppleEmerald
                                        ),
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
                                                    fontWeight = FontWeight.SemiBold
                                                ),
                                                color = Color.White
                                            )
                                        } else {
                                            Icon(
                                                imageVector = Icons.Default.QrCode,
                                                contentDescription = null,
                                                tint = Color.White,
                                                modifier = Modifier.size(20.dp)
                                            )
                                            Spacer(modifier = Modifier.width(10.dp))
                                            Text(
                                                text = if (otpCode != null) "Tạo Lại Mã OTP Khác" else "✨ Tạo Mã Ghép Nối Với Phụ Huynh (OTP)",
                                                style = MaterialTheme.typography.bodyLarge.copy(
                                                    fontWeight = FontWeight.SemiBold,
                                                    fontSize = 15.sp
                                                ),
                                                color = Color.White
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
                                        .height(48.dp),
                                    shape = RoundedCornerShape(14.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                                    ),
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
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        // UsageTrackingForegroundService duy trì kết nối nền 24/7
    }
}
